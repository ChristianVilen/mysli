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

/// Update Notes never writes `error.md`: the meeting stays done, and its old `summary.md` stays
/// when every CLI fails.
enum NotesUpdateOutcome: Equatable {
    case updated(summary: URL)
    case summaryToolFailed(failures: [SummaryFailure])
    case failed(message: String)
    case cancelled
    /// Another recorder or processor holds the folder's lock.
    case busy
    /// The meeting is not done, or its folder is gone.
    case notReady
}

@MainActor
struct MeetingProcessor {
    private let transcribers: [Transcribing]
    private let roomLabeller: RoomLabelling
    private let summarizer: Summarizer
    private let knownWords: () -> KnownWordsList
    private let locale: () -> Locale
    private let trash: (URL) throws -> Void
    private let now: () -> Date

    /// Reads the known-words list once per summary; the list is never cached.
    init(transcribers: [Transcribing] = [WhisperKitTranscriber(), SpeechTranscriberAdapter()],
         roomLabeller: RoomLabelling,
         summarizer: Summarizer = Summarizer(),
         knownWords: @escaping () -> KnownWordsList,
         locale: @escaping () -> Locale = { Locale(identifier: "en-US") },
         trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
         now: @escaping () -> Date = { Date() }) {
        self.transcribers = transcribers
        self.roomLabeller = roomLabeller
        self.summarizer = summarizer
        self.knownWords = knownWords
        self.locale = locale
        self.trash = trash
        self.now = now
    }

    /// Asks no new questions and leaves both review files alone.
    func updateNotes(_ meeting: MeetingFolder, tool: SummaryTool,
                     summaryInput: (String) -> Void = { _ in }) async -> NotesUpdateOutcome {
        await update(meeting, source: .correctedTranscript, tool: tool, summaryInput: summaryInput)
    }

    func updateSummary(_ meeting: MeetingFolder, tool: SummaryTool,
                       summaryInput: (String) -> Void = { _ in }) async -> NotesUpdateOutcome {
        await update(meeting, source: .savedTranscript, tool: tool, summaryInput: summaryInput)
    }

    private enum SummarySource { case correctedTranscript, savedTranscript }

    private func update(_ meeting: MeetingFolder, source: SummarySource, tool: SummaryTool,
                        summaryInput: (String) -> Void) async -> NotesUpdateOutcome {
        let lock: FileLock
        do {
            lock = try meeting.lock()
        } catch MeetingLockError.held {
            return .busy
        } catch {
            return .notReady
        }
        defer { lock.release() }
        guard meeting.stage() == .done else { return .notReady }
        do {
            let typedNotes = try MeetingTypedNotesFile.read(in: meeting)
            let content: String
            let list: KnownWordsList
            switch source {
            case .correctedTranscript:
                (content, list) = try correctedContent(in: meeting)
            case .savedTranscript:
                content = Transcript.contentForSummary(Transcript.withoutCorrectionNote(try meeting.read(.transcript)))
                list = knownWords()
            }
            let result = try await summarizeContent(content, in: meeting, list: list, typedNotes: typedNotes,
                                                    tool: tool, summaryInput: summaryInput)
            switch result {
            case .written(let notes, _, _, _):
                try meeting.write(SummaryDocument.markdown(title: meeting.title, body: notes), to: .summary)
            case .failed(let failures):
                if Task.isCancelled { return .cancelled }
                return .summaryToolFailed(failures: failures)
            }
        } catch {
            if Task.isCancelled { return .cancelled }
            return .failed(message: error.localizedDescription)
        }
        return .updated(summary: meeting.url(for: .summary))
    }

    func process(_ meeting: MeetingFolder, speakers: TeamsSpeakerEvidence = .empty, tool: SummaryTool,
                 summaryInput: (String) -> Void = { _ in },
                 progress: (MeetingProgress) -> Void) async -> MeetingOutcome {
        let lock: FileLock
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
                progress(.step(step))
                do {
                    switch step {
                    case .transcribe:
                        try await transcribe(meeting, speakers: speakers, progress: progress)
                    case .summarize:
                        if try await summarize(meeting, tool: tool, summaryInput: summaryInput) == .noSpeech {
                            return .noSpeech
                        }
                    }
                } catch {
                    if Task.isCancelled { return .cancelled }
                    return fail(meeting, at: step, message: error.localizedDescription)
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

    private func transcribe(_ meeting: MeetingFolder, speakers: TeamsSpeakerEvidence,
                            progress: (MeetingProgress) -> Void) async throws {
        let (tracks, transcriber, failures) = try await transcribeTracks(meeting, progress: progress)
        let rooms = try await labelRooms(meeting, tracks: tracks, progress: progress)
        try Task.checkCancellation()
        let lines = Transcript.merge(tracks.mapValues(\.segments), rooms: rooms, speakers: speakers)
        if let line = speakers.scans.mergeLine(for: lines) { Log.teams.notice(line) }
        let duration = tracks.values.map(\.duration).max() ?? 0
        let heard = Transcript.markdown(lines, title: meeting.title, duration: duration,
                                        by: transcriber, after: failures, rooms: rooms, teams: speakers.scans)
        try meeting.write(heard, to: .heardTranscript)
        try meeting.write(heard, to: .transcript)
    }

    /// The session lives only in here, so the Whisper model is released
    /// before the room labeller loads its own model. A transcription error
    /// fails the step with no fallback, so both tracks come from one transcriber.
    private func transcribeTracks(_ meeting: MeetingFolder, progress: (MeetingProgress) -> Void)
        async throws -> (tracks: [MeetingTrack: TrackTranscript], transcriber: String, failures: [TranscriberFailure]) {
        let (session, transcriber, failures) = try await startTranscriber(progress: progress)
        try Task.checkCancellation()
        var tracks: [MeetingTrack: TrackTranscript] = [:]
        for track in MeetingTrack.allCases where FileManager.default.fileExists(atPath: meeting.audioURL(track).path) {
            tracks[track] = try await session.transcribe(meeting.audioURL(track))
            try Task.checkCancellation()
        }
        return (tracks, transcriber, failures)
    }

    /// Skips downloading and diarization when no microphone segment passes the text and segment-echo filters.
    /// Throws only when the meeting folder cannot be written.
    private func labelRooms(_ meeting: MeetingFolder, tracks: [MeetingTrack: TrackTranscript],
                            progress: (MeetingProgress) -> Void) async throws -> RoomLabels {
        guard !Transcript.microphoneSpeech(tracks.mapValues(\.segments)).isEmpty else { return .notDiarized }
        guard !meeting.roomLabelsStarted else { return .failed(.earlierAttemptStopped) }
        guard (tracks[.microphone]?.duration ?? 0) <= RoomLabelFailure.longestTrack else { return .failed(.tooLong) }
        if roomLabeller.needsDownload {
            do {
                try await downloading(.speaker, progress: progress) { try await roomLabeller.download(onStart: $0) }
            } catch {
                return .failed(.download(error.localizedDescription))
            }
        }
        try meeting.markRoomLabelsStarted()
        let rooms = await withTaskCancellationHandler {
            await roomLabeller.label(meeting.audioURL(.microphone))
        } onCancel: {
            // A quit ends the process before `label` returns. `onCancel` runs inside `cancel()`,
            // so the marker is gone before `MeetingNotesController.shutDown()` returns.
            try? meeting.clearRoomLabelsStarted()
        }
        try meeting.clearRoomLabelsStarted()
        return rooms
    }

    /// Reports downloading only after `onStart`, then restores Transcribing even on failure.
    /// `download` does not escape, but Swift requires `@escaping` to pass it a closure that captures `progress`.
    private func downloading(_ model: MeetingModel, progress: (MeetingProgress) -> Void,
                             _ download: @escaping (_ onStart: @MainActor () -> Void) async throws -> Void) async throws {
        var started = false
        defer { if started { progress(.step(.transcribe)) } }
        try await download {
            started = true
            progress(.downloading(model))
        }
    }

    private func startTranscriber(progress: (MeetingProgress) -> Void) async throws
        -> (session: any TranscriptionSession, transcriber: String, failures: [TranscriberFailure]) {
        let locale = self.locale()
        var failures: [TranscriberFailure] = []
        for transcriber in transcribers {
            try Task.checkCancellation()
            var stage = TranscriberFailure.Stage.unavailable
            do {
                let needsDownload = try await transcriber.needsDownload(for: locale)
                try Task.checkCancellation()
                if needsDownload {
                    stage = .download
                    try await downloading(.speech, progress: progress) {
                        try await transcriber.download(for: locale, onStart: $0)
                    }
                }
                try Task.checkCancellation()
                stage = .load
                let session = try await transcriber.load(for: locale)
                try Task.checkCancellation()
                return (session, transcriber.name, failures)
            } catch {
                // URLSession reports a cancelled download as URLError(.cancelled),
                // not CancellationError, so the task is asked instead.
                if Task.isCancelled { throw error }
                failures.append(TranscriberFailure(transcriber: transcriber.name, stage: stage,
                                                   message: error.localizedDescription))
            }
        }
        throw MeetingStepError(failures.map(\.description).joined(separator: "\n"))
    }

    private enum SummaryCompletion { case written, noSpeech }

    private func summarize(_ meeting: MeetingFolder, tool: SummaryTool,
                           summaryInput: (String) -> Void) async throws -> SummaryCompletion {
        let typedNotes = try MeetingTypedNotesFile.read(in: meeting)
        let (content, list) = try correctedContent(in: meeting)
        if Transcript.isSilent(content), typedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try meeting.write(SummaryDocument.noSpeech(title: meeting.title), to: .summary)
            return .noSpeech
        }
        // Trash the audio here, not right after writing transcript.md: this
        // step runs only once transcript.md exists, so it also cleans up after
        // a crash between the two.
        do {
            try meeting.discardAudio(trash: trash)
        } catch {
            Log.meeting.error("Could not move meeting audio to the Trash (code \((error as NSError).code)): \(error.localizedDescription)")
        }
        let result = try await summarizeContent(content, in: meeting, list: list, typedNotes: typedNotes,
                                                tool: tool, summaryInput: summaryInput)
        switch result {
        case .written(let notes, let suspects, _, _):
            // The questions, or the removal of old ones, go before `summary.md`, which marks the meeting done.
            try meeting.saveQuestions(WordQuestions.select(suspects, in: content, knownWords: list))
            try meeting.write(SummaryDocument.markdown(title: meeting.title, body: notes), to: .summary)
        case .failed(let failures):
            throw MeetingStepError(failures.map(\.description).joined(separator: "\n"))
        }
        return .written
    }

    /// Rebuilds `transcript.md` from the heard copy, so corrections never apply twice and a removed
    /// list line undoes its replacement. This also replaces hand edits to `transcript.md`.
    private func correctedContent(in meeting: MeetingFolder) throws -> (content: String, list: KnownWordsList) {
        let heard = try meeting.heardTranscript()
        let list = knownWords()
        let corrected = Transcript.corrected(heard, by: list.corrector)
        try meeting.write(corrected.markdown, to: .transcript)
        let content = Transcript.contentForSummary(corrected.body)
        return (content, list)
    }

    private func summarizeContent(_ content: String, in meeting: MeetingFolder, list: KnownWordsList,
                                  typedNotes: String, tool: SummaryTool,
                                  summaryInput: (String) -> Void) async throws -> SummaryResult {
        // The saved text, not `summaryText`: the notes editor compares this snapshot with its own text.
        summaryInput(typedNotes)
        let result = await summarizer.summarize(transcript: content, knownWords: list.relevant(to: content), tool: tool,
                                                typedNotes: MeetingNoteDocument.summaryText(MeetingNoteDocument.parse(typedNotes)))
        try Task.checkCancellation()
        if case .written(_, _, let cli, let earlier) = result, !earlier.isEmpty {
            for failure in earlier {
                Log.meeting.notice("\(cli.rawValue, privacy: .public) wrote the notes of \(meeting.name, privacy: .public). Earlier failure: \(failure.logMessage)")
            }
        }
        return result
    }

    static func failureText(step: MeetingStep, message: String, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return """
        # \(step.failureHeading)

        \(formatter.string(from: date))

        \(message)

        Choose Retry Failed Meeting in the Mysli menu to try again.

        """
    }
}

struct MeetingStepError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
