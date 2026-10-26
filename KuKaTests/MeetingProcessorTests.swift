import XCTest
@testable import KuKa

@MainActor
final class MeetingProcessorTests: XCTestCase {
    private struct TestError: LocalizedError {
        let errorDescription: String?
    }

    private var whisper: FakeTranscriber!
    private var apple: FakeTranscriber!
    private var runner: FakeCommandRunner!
    private var trashed: [String] = []
    private var steps: [MeetingStep] = []

    override func setUp() async throws {
        whisper = makeTranscriber(named: "Whisper")
        apple = makeTranscriber(named: "Apple")
        runner = FakeCommandRunner()
        runner.results["agy"] = .success(CommandResult(termination: .exited(0), stdout: "## Summary\nShip Friday.", stderr: ""))
        trashed = []
        steps = []
    }

    private func makeTranscriber(named name: String) -> FakeTranscriber {
        let transcriber = FakeTranscriber(name: name)
        transcriber.byFileName["them.caf"] = .success(TrackTranscript(
            segments: [TranscriptSegment(start: 1, end: 3, text: "Let's ship on Friday")], duration: 60))
        transcriber.byFileName["me.caf"] = .success(TrackTranscript(
            segments: [TranscriptSegment(start: 4, end: 5, text: "Sounds good")], duration: 59))
        return transcriber
    }

    private func makeProcessor(transcribers: [Transcribing]? = nil) -> MeetingProcessor {
        MeetingProcessor(
            transcribers: transcribers ?? [whisper, apple],
            summarizer: Summarizer(runner: runner, home: URL(fileURLWithPath: "/Users/test"), isExecutable: { _ in true }),
            trash: { [unowned self] url in
                trashed.append(url.lastPathComponent)
                try FileManager.default.removeItem(at: url)
            },
            now: { localDate(2026, 10, 23, 15, 0) })
    }

    private func makeMeeting() throws -> MeetingFolder {
        let meeting = try MeetingFolder.create(in: try makeTemporaryDirectory(), startingAt: localDate(2026, 10, 23, 14, 2))
        for track in MeetingTrack.allCases {
            FileManager.default.createFile(atPath: meeting.audioURL(track).path, contents: Data())
        }
        return meeting
    }

    private func process(_ meeting: MeetingFolder, with processor: MeetingProcessor? = nil) async -> MeetingOutcome {
        await (processor ?? makeProcessor()).process(meeting) { [unowned self] in steps.append($0) }
    }

    private func audioExists(_ meeting: MeetingFolder) -> Bool {
        FileManager.default.fileExists(atPath: meeting.audioURL(.system).path)
    }

    func testFirstRunWritesTranscriptAndSummaryAndTrashesTheAudio() async throws {
        let meeting = try makeMeeting()

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(steps, [.transcribe, .summarize])
        XCTAssertEqual(try meeting.read(.transcript), """
        # Meeting on 2026-10-23 at 14:02

        Duration: 00:01:00

        Transcript by Whisper.

        "Me" is the person who recorded the meeting. "Them" is everyone else on the call.

        **[00:00:01] Them:** Let's ship on Friday

        **[00:00:04] Me:** Sounds good

        """)
        XCTAssertEqual(try meeting.read(.summary), """
        # Meeting on 2026-10-23 at 14:02

        ## Summary
        Ship Friday.

        ---

        Summary by `agy`.

        """)
        XCTAssertEqual(trashed, ["audio"])
        XCTAssertEqual(meeting.stage(), .done)
    }

    func testAMissingSpeechModelIsDownloadedForTheConfiguredLanguageFirst() async throws {
        let meeting = try makeMeeting()
        whisper.modelIsMissing = true
        var downloadsReported = 0
        let processor = MeetingProcessor(
            transcribers: [whisper, apple],
            summarizer: Summarizer(runner: runner, home: URL(fileURLWithPath: "/Users/test"), isExecutable: { _ in true }),
            locale: { Locale(identifier: "de-DE") },
            trash: { try FileManager.default.removeItem(at: $0) })

        let outcome = await processor.process(meeting, onStep: { _ in }, onDownload: { downloadsReported += 1 })

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(downloadsReported, 1)
        XCTAssertEqual(whisper.downloads, ["de-DE"])
        XCTAssertEqual(whisper.loads, ["de-DE"])
    }

    func testWhisperTranscribesBothTracksWithOneLoadWhenItCanStart() async throws {
        let meeting = try makeMeeting()

        _ = await process(meeting)

        XCTAssertTrue(try meeting.read(.transcript).contains("\n\nTranscript by Whisper.\n\n"))
        XCTAssertEqual(whisper.loads, ["en-US"])
        XCTAssertEqual(whisper.transcribed, ["me.caf", "them.caf"])
        XCTAssertEqual(apple.loads, [])
        XCTAssertEqual(apple.downloads, [])
    }

    func testAppleTranscribesWhenWhisperCannotStartAndTheTranscriptSaysWhy() async throws {
        let rows: [(stage: TranscriberFailure.Stage, error: String, bullet: String, whisperDownloads: [String])] = [
            (.unavailable, "Whisper does not support eo.",
             "- Whisper cannot be used: Whisper does not support eo.", []),
            (.download, "The Internet connection appears to be offline.",
             "- Whisper could not download its model: The Internet connection appears to be offline.", ["en-US"]),
            (.load, "The model files are damaged.",
             "- Whisper could not load its model: The model files are damaged.", ["en-US"]),
        ]
        for row in rows {
            let meeting = try makeMeeting()
            whisper = makeTranscriber(named: "Whisper")
            apple = makeTranscriber(named: "Apple")
            whisper.modelIsMissing = true
            whisper.failure = (row.stage, MeetingStepError(row.error))

            let outcome = await process(meeting)

            XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)), "\(row.stage)")
            XCTAssertEqual(try meeting.read(.transcript), """
            # Meeting on 2026-10-23 at 14:02

            Duration: 00:01:00

            Transcript by Apple. Tried first:

            \(row.bullet)

            "Me" is the person who recorded the meeting. "Them" is everyone else on the call.

            **[00:00:01] Them:** Let's ship on Friday

            **[00:00:04] Me:** Sounds good

            """, "\(row.stage)")
            XCTAssertEqual(whisper.downloads, row.whisperDownloads, "\(row.stage)")
            XCTAssertEqual(whisper.transcribed, [], "\(row.stage)")
            XCTAssertEqual(apple.loads, ["en-US"], "\(row.stage)")
        }
    }

    func testTheMenuLeavesTheDownloadStepWhenTheWhisperDownloadFails() async throws {
        let meeting = try makeMeeting()
        whisper.modelIsMissing = true
        whisper.failure = (.download, MeetingStepError("The Internet connection appears to be offline."))
        var events: [String] = []

        _ = await makeProcessor().process(meeting, onStep: { events.append($0.progressVerb) },
                                          onDownload: { events.append("Downloading") })

        XCTAssertEqual(events, ["Transcribing", "Downloading", "Transcribing", "Summarizing"])
    }

    func testFallbackDiagnosticsStayOnDiskButDoNotEnterTheSummaryPrompt() async throws {
        let meeting = try makeMeeting()
        whisper.failure = (.load, MeetingStepError("The model could not load."))

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertTrue(try meeting.read(.transcript).contains("Whisper could not load its model: The model could not load."))
        let prompt = try XCTUnwrap(runner.calls.first?.arguments.last)
        XCTAssertEqual(prompt.components(separatedBy: "Transcript:\n\n").last, """
        **[00:00:01] Them:** Let's ship on Friday

        **[00:00:04] Me:** Sounds good

        """)
    }

    func testWhenNoTranscriberCanStartErrorMdListsEachReason() async throws {
        let meeting = try makeMeeting()
        whisper.failure = (.unavailable, MeetingStepError("Whisper does not support eo."))
        apple.failure = (.load, MeetingStepError("The speech model is missing."))

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .failed(.transcribe, message: """
        Whisper cannot be used: Whisper does not support eo.
        Apple could not load its model: The speech model is missing.
        """))
        XCTAssertEqual(try meeting.read(.failure), """
        # Transcription Failed

        2026-10-23 15:00

        Whisper cannot be used: Whisper does not support eo.
        Apple could not load its model: The speech model is missing.

        Choose Retry Failed Meeting in the Ku-Ka menu to try again.

        """)
        XCTAssertTrue(audioExists(meeting))
    }

    func testTheCLIGetsTheTranscriptFromDisk() async throws {
        let meeting = try makeMeeting()
        try meeting.write("**[00:00:07] Me:** This was saved by an earlier run.", to: .transcript)

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        let prompt = try XCTUnwrap(runner.calls.first?.arguments.last)
        XCTAssertEqual(prompt.components(separatedBy: "Transcript:\n\n").last,
                       "**[00:00:07] Me:** This was saved by an earlier run.")
    }

    func testATranscriptionFailureAfterLoadingWritesTheReasonKeepsTheAudioAndDoesNotFallBack() async throws {
        let meeting = try makeMeeting()
        whisper.byFileName["them.caf"] = .failure(TestError(errorDescription: "Whisper could not transcribe them.caf: Out of memory."))

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .failed(.transcribe, message: "Whisper could not transcribe them.caf: Out of memory."))
        let errorText = """
        # Transcription Failed

        2026-10-23 15:00

        Whisper could not transcribe them.caf: Out of memory.

        Choose Retry Failed Meeting in the Ku-Ka menu to try again.

        """
        XCTAssertEqual(try meeting.read(.failure), errorText)
        XCTAssertEqual(meeting.stage(), .failed(.transcribe))
        XCTAssertTrue(audioExists(meeting))
        XCTAssertEqual(trashed, [])
        XCTAssertEqual(runner.calls.count, 0)
        XCTAssertEqual(whisper.loads, ["en-US"])
        XCTAssertEqual(apple.loads, [])
    }

    func testNoSpeechEndsTheMeetingAndKeepsTheAudio() async throws {
        let meeting = try makeMeeting()
        whisper.byFileName = [:]

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .noSpeech)
        XCTAssertEqual(meeting.stage(), .done)
        XCTAssertEqual(try meeting.read(.transcript), """
        # Meeting on 2026-10-23 at 14:02

        Duration: 00:00:00

        Transcript by Whisper.

        "Me" is the person who recorded the meeting. "Them" is everyone else on the call.

        No speech was detected.

        """)
        XCTAssertEqual(try meeting.read(.summary), """
        # Meeting on 2026-10-23 at 14:02

        No speech was detected, so there is no summary. The audio is in the meeting folder.

        """)
        XCTAssertTrue(audioExists(meeting))
        XCTAssertEqual(trashed, [])
        XCTAssertEqual(runner.calls.count, 0)
    }

    func testAMeetingFolderThatIsGoneEndsWithoutAFailure() async throws {
        let meeting = try makeMeeting()
        try FileManager.default.removeItem(at: meeting.url)

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .gone)
        XCTAssertFalse(FileManager.default.fileExists(atPath: meeting.url.path))
    }

    func testAMeetingThatAnotherWriterHoldsIsLeftAlone() async throws {
        let meeting = try makeMeeting()
        let otherWriter = try XCTUnwrap(meeting.lock())

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .busy)
        XCTAssertEqual(steps, [])
        XCTAssertEqual(meeting.stage(), .pending(.transcribe))
        otherWriter.release()
    }

    func testAMeetingFolderThatCannotBeLockedFailsWithTheReason() async throws {
        let meeting = try makeMeeting()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: meeting.url.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: meeting.url.path) }

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .failed(.transcribe, message: "Ku-Ka could not lock the meeting folder \(meeting.url.path): Permission denied."))
        XCTAssertEqual(steps, [])
    }

    func testASummaryFailureKeepsTheTranscriptAndListsEachCLI() async throws {
        let meeting = try makeMeeting()
        runner.results["agy"] = .success(CommandResult(termination: .exited(1), stdout: "", stderr: "authentication failed"))
        runner.results["claude"] = .success(CommandResult(termination: .timedOut, stdout: "", stderr: ""))

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .failed(.summarize, message: "agy exited with status 1: authentication failed\nclaude took too long and was stopped"))
        XCTAssertEqual(try meeting.read(.failure), """
        # Summary Failed

        2026-10-23 15:00

        agy exited with status 1: authentication failed
        claude took too long and was stopped

        Choose Retry Failed Meeting in the Ku-Ka menu to try again.

        """)
        XCTAssertTrue(FileManager.default.fileExists(atPath: meeting.url(for: .transcript).path))
        XCTAssertEqual(trashed, ["audio"])
    }

    func testAFailedMeetingWaitsForRetry() async throws {
        let meeting = try makeMeeting()
        try meeting.write("Earlier failure", to: .failure)

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .failed(.transcribe, message: "An earlier attempt failed. See error.md in the meeting folder."))
        XCTAssertEqual(steps, [])
    }

    func testRetryResumesAtTheFailedStep() async throws {
        let meeting = try makeMeeting()
        runner.results["agy"] = .success(CommandResult(termination: .exited(1), stdout: "", stderr: ""))
        _ = await process(meeting)
        try meeting.clearFailure()
        runner.results["claude"] = .success(CommandResult(termination: .exited(0), stdout: "## Summary\nShip Friday.", stderr: ""))
        whisper.byFileName["them.caf"] = .failure(TestError(errorDescription: "must not transcribe again"))
        steps = []

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(steps, [.summarize])
        XCTAssertFalse(FileManager.default.fileExists(atPath: meeting.url(for: .failure).path))
    }

    func testRecoveryAfterAStopAtEachPointRunsOnlyTheMissingSteps() async throws {
        let cases: [(name: String, files: [MeetingDocument], keepAudio: Bool, steps: [MeetingStep], trashed: [String])] = [
            ("stopped before the transcript", [], true, [.transcribe, .summarize], ["audio"]),
            ("stopped before the audio went to the Trash", [.transcript], true, [.summarize], ["audio"]),
            ("stopped while summarizing", [.transcript], false, [.summarize], []),
            ("already done", [.transcript, .summary], false, [], []),
        ]
        for row in cases {
            let meeting = try makeMeeting()
            for document in row.files { try meeting.write("# \(document.rawValue)", to: document) }
            if !row.keepAudio { try FileManager.default.removeItem(at: meeting.audioURL(.system).deletingLastPathComponent()) }
            steps = []
            trashed = []

            let outcome = await process(meeting)

            XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)), row.name)
            XCTAssertEqual(steps, row.steps, row.name)
            XCTAssertEqual(trashed, row.trashed, row.name)
        }
    }

    func testCancellingLeavesTheMeetingPendingWithoutAnErrorFile() async throws {
        let meeting = try makeMeeting()
        let processor = makeProcessor(transcribers: [SuspendedTranscriber(name: "Whisper"), apple])
        let run = Task { await process(meeting, with: processor) }
        await waitUntil { !steps.isEmpty }
        XCTAssertEqual(steps, [.transcribe])

        run.cancel()

        let outcome = await run.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(meeting.stage(), .pending(.transcribe))
    }

    func testCancellationDiscardsEvenSuccessfulTrackResultsBeforeWritingDocuments() async throws {
        for empty in [true, false] {
            let meeting = try makeMeeting()
            let transcriber = CancelledReturningTranscriber(empty: empty)
            let processor = makeProcessor(transcribers: [transcriber, apple])
            let run = Task { await process(meeting, with: processor) }

            let outcome = await run.value

            XCTAssertEqual(outcome, .cancelled)
            XCTAssertEqual(meeting.stage(), .pending(.transcribe))
            XCTAssertTrue(audioExists(meeting))
            for document in MeetingDocument.allCases {
                XCTAssertFalse(FileManager.default.fileExists(atPath: meeting.url(for: document).path), document.rawValue)
            }
            XCTAssertEqual(apple.loads, [])
        }
    }

    func testCancellingDuringTheWhisperDownloadNeitherFailsNorFallsBack() async throws {
        let meeting = try makeMeeting()
        let suspended = SuspendedTranscriber(name: "Whisper")
        suspended.modelIsMissing = true
        var downloading = false
        let run = Task {
            await makeProcessor(transcribers: [suspended, apple]).process(meeting, onStep: { _ in },
                                                                          onDownload: { downloading = true })
        }
        await waitUntil { downloading }

        run.cancel()

        let outcome = await run.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(meeting.stage(), .pending(.transcribe))
        XCTAssertEqual(apple.downloads, [])
        XCTAssertEqual(apple.loads, [])
    }
}

private final class CancelledReturningTranscriber: FakeTranscriber {
    let empty: Bool

    init(empty: Bool) {
        self.empty = empty
        super.init(name: "Cancelled Whisper")
    }

    override func transcribe(_ audio: URL) async throws -> TrackTranscript {
        withUnsafeCurrentTask { $0?.cancel() }
        return TrackTranscript(segments: empty ? [] : [TranscriptSegment(start: 0, end: 1, text: "Synthetic speech")],
                               duration: 61)
    }
}

private final class SuspendedTranscriber: FakeTranscriber {
    override func download(for locale: Locale) async throws {
        try await Task.sleep(for: .seconds(60))
    }

    override func transcribe(_ audio: URL) async throws -> TrackTranscript {
        try await Task.sleep(for: .seconds(60))
        return TrackTranscript(segments: [], duration: 0)
    }
}
