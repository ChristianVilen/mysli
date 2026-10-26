import Foundation

enum MeetingOutcome: Equatable {
    case done(summary: URL)
    case noSpeech
    case failed(MeetingStep, message: String)
    case cancelled
    /// Another recorder or processor holds the folder's lock.
    case busy
    /// The folder was moved or deleted.
    case gone
}

@MainActor
struct MeetingProcessor {
    private let transcriber: Transcribing
    private let summarizer: Summarizer
    private let locale: () -> Locale
    private let trash: (URL) throws -> Void
    private let now: () -> Date

    init(transcriber: Transcribing = SpeechTranscriberAdapter(),
         summarizer: Summarizer = Summarizer(),
         locale: @escaping () -> Locale = { Locale(identifier: "en-US") },
         trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
         now: @escaping () -> Date = { Date() }) {
        self.transcriber = transcriber
        self.summarizer = summarizer
        self.locale = locale
        self.trash = trash
        self.now = now
    }

    /// `onDownload` runs when the speech model must be downloaded before
    /// the transcription can start, and `onStep(.transcribe)` runs again
    /// once it is installed.
    func process(_ meeting: MeetingFolder, onStep: (MeetingStep) -> Void,
                 onDownload: () -> Void = {}) async -> MeetingOutcome {
        let lock: MeetingLock
        do {
            lock = try meeting.lock()
        } catch MeetingLockError.held {
            return .busy
        } catch {
            switch meeting.stage() {
            case nil: return .gone
            case .done?: return .done(summary: meeting.url(for: .summary))
            case .pending(let step)?, .failed(let step)?: return fail(meeting, at: step, message: error.localizedDescription)
            }
        }
        defer { lock.release() }
        while true {
            if Task.isCancelled { return .cancelled }
            let stage = meeting.stage()
            switch stage {
            case nil:
                return .gone
            case .done?:
                return .done(summary: meeting.url(for: .summary))
            case .failed(let step)?:
                return .failed(step, message: "An earlier attempt failed. See error.md in the meeting folder.")
            case .pending(let step)?:
                onStep(step)
                do {
                    switch step {
                    case .transcribe:
                        guard try await transcribe(meeting, onStep: onStep, onDownload: onDownload) else { return .noSpeech }
                    case .summarize:
                        try await summarize(meeting)
                    }
                } catch {
                    if Task.isCancelled { return .cancelled }
                    return fail(meeting, at: step, message: (error as? MeetingStepError)?.message ?? error.localizedDescription)
                }
                if meeting.stage() == stage {
                    return fail(meeting, at: step, message: "The step finished, but the meeting folder did not change.")
                }
            }
        }
    }

    private func fail(_ meeting: MeetingFolder, at step: MeetingStep, message: String) -> MeetingOutcome {
        try? meeting.write(Self.failureText(step: step, message: message, at: now()), to: .failure)
        return .failed(step, message: message)
    }

    /// False when nobody spoke. The meeting is then done, and its audio stays
    /// in the folder.
    private func transcribe(_ meeting: MeetingFolder, onStep: (MeetingStep) -> Void,
                            onDownload: () -> Void) async throws -> Bool {
        let locale = self.locale()
        if try await transcriber.needsDownload(for: locale) {
            onDownload()
            try await transcriber.download(for: locale)
            onStep(.transcribe)
        }
        var tracks: [MeetingTrack: TrackTranscript] = [:]
        for track in MeetingTrack.allCases where FileManager.default.fileExists(atPath: meeting.audioURL(track).path) {
            tracks[track] = try await transcriber.transcribe(meeting.audioURL(track), locale: locale)
        }
        let lines = Transcript.merge(tracks)
        let duration = tracks.values.map(\.duration).max() ?? 0
        if lines.isEmpty {
            // Summary first: it marks the meeting done, so a crash before the
            // transcript is written cannot run the summary step, which would
            // trash the audio.
            try meeting.write(SummaryDocument.noSpeech(title: meeting.title), to: .summary)
        }
        try meeting.write(Transcript.markdown(lines, title: meeting.title, duration: duration), to: .transcript)
        return !lines.isEmpty
    }

    private func summarize(_ meeting: MeetingFolder) async throws {
        // Trash the audio here, not right after writing transcript.md: this
        // step runs only once transcript.md exists, so it also cleans up after
        // a crash between the two.
        do {
            try meeting.discardAudio(trash: trash)
        } catch {
            NSLog("Ku-Ka: could not move meeting audio to the Trash: \(error)")
        }
        let transcript = try meeting.read(.transcript)
        switch await summarizer.summarize(transcript: transcript) {
        case .written(let markdown, let cli, let earlier):
            try meeting.write(SummaryDocument.markdown(title: meeting.title, body: markdown, by: cli, after: earlier),
                              to: .summary)
        case .failed(let failures):
            throw MeetingStepError(failures.map(\.description).joined(separator: "\n"))
        }
    }

    static func failureText(step: MeetingStep, message: String, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return """
        # \(step.failureHeading)

        \(formatter.string(from: date))

        \(message)

        Choose Retry Failed Meeting in the Ku-Ka menu to try again.

        """
    }
}

struct MeetingStepError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
