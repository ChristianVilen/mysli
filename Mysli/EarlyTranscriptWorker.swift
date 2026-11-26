import Foundation

/// Transcribes the finished parts of each track with Whisper while a meeting records, into the
/// meeting's early transcripts, so that after Stop only the last part of each track is left.
/// When Whisper is not ready or a pass fails, the worker ends, and the processor transcribes
/// after Stop what the early transcripts do not cover.
@MainActor
final class EarlyTranscriptWorker {
    /// A pass is sure to settle part of a track only with two 30 s Whisper windows of new audio
    /// or more. 210 s keeps the passes few, and each one short.
    private static let minimumNewAudio = 210 * EarlyTranscript.framesPerSecond

    private let meeting: MeetingFolder
    private let transcriber: any EarlyTranscribing
    private let locale: Locale
    private let frameCount: @MainActor (URL) throws -> Int64
    private let wait: @MainActor () async throws -> Void
    private var task: Task<Void, Never>?
    /// What the last pass of each track returned. The file is only for the processor.
    private var transcripts: [MeetingTrack: EarlyTranscript] = [:]

    init(meeting: MeetingFolder, transcriber: any EarlyTranscribing, locale: Locale,
         frameCount: @escaping @MainActor (URL) throws -> Int64 = AudioTrackWriter.frameCount(at:),
         wait: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .seconds(30)) }) {
        self.meeting = meeting
        self.transcriber = transcriber
        self.locale = locale
        self.frameCount = frameCount
        self.wait = wait
    }

    func start() {
        guard task == nil else { return }
        task = Task { await run() }
    }

    /// The recorder calls this before it hands the folder to the processor. A pass in flight is
    /// thrown away, and the worker writes nothing after this call.
    func cancel() {
        task?.cancel()
    }

    /// For tests, which must see that the worker did nothing.
    func waitUntilEnded() async {
        await task?.value
    }

    private func run() async {
        do {
            guard try await !transcriber.needsDownload(for: locale) else {
                Log.meeting.notice("Early text is off for this recording: the Whisper model is not installed")
                return
            }
        } catch {
            if !Task.isCancelled { Log.meeting.notice("Early text is off for this recording: \(error.localizedDescription)") }
            return
        }
        while true {
            do {
                try await wait()
                try await runPasses(dueTracks())
            } catch {
                if !Task.isCancelled { Log.meeting.error("Early text stopped for this recording: \(error.localizedDescription)") }
                return
            }
        }
    }

    private func dueTracks() -> [MeetingTrack] {
        MeetingTrack.allCases.filter { track in
            guard let length = try? frameCount(meeting.audioURL(track)) else { return false }
            return length - (transcripts[track]?.covered ?? 0) >= Self.minimumNewAudio
        }
    }

    /// The passes of one tick share one session, which ends with them. So between ticks the model
    /// stays in memory only while something else holds it, such as dictation.
    private func runPasses(_ due: [MeetingTrack]) async throws {
        guard !due.isEmpty else { return }
        let loadStart = ContinuousClock.now
        let session = try await transcriber.loadEarly(for: locale)
        Log.meeting.notice("Early text: Whisper ready after \(Self.seconds(since: loadStart)) s")
        for track in due {
            let passStart = ContinuousClock.now
            let covered = transcripts[track]?.covered ?? 0
            let early = try await session.extend(transcripts[track], of: meeting.audioURL(track))
            // Stop cancels this task on the main actor before it hands the folder to the processor,
            // and nothing suspends between this check and the write, so a cancelled pass writes nothing.
            try Task.checkCancellation()
            try meeting.saveEarlyTranscript(early, for: track)
            transcripts[track] = early
            Log.meeting.notice("Early text: \(String(describing: track), privacy: .public) pass covered \((early.covered - covered) / EarlyTranscript.framesPerSecond) s more in \(Self.seconds(since: passStart)) s")
        }
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Int {
        Int(((ContinuousClock.now - start) / .seconds(1)).rounded())
    }
}
