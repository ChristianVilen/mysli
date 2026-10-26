import XCTest
@testable import KuKa

@MainActor
final class MeetingProcessorTests: XCTestCase {
    private struct TestError: LocalizedError {
        let errorDescription: String?
    }

    private var transcriber: FakeTranscriber!
    private var runner: FakeCommandRunner!
    private var trashed: [String] = []
    private var steps: [MeetingStep] = []

    override func setUp() async throws {
        transcriber = FakeTranscriber()
        transcriber.byFileName["them.caf"] = .success(TrackTranscript(
            segments: [TranscriptSegment(start: 1, end: 3, text: "Let's ship on Friday")], duration: 60))
        transcriber.byFileName["me.caf"] = .success(TrackTranscript(
            segments: [TranscriptSegment(start: 4, end: 5, text: "Sounds good")], duration: 59))
        runner = FakeCommandRunner()
        runner.results["agy"] = .success(CommandResult(termination: .exited(0), stdout: "## Summary\nShip Friday.", stderr: ""))
        trashed = []
        steps = []
    }

    private func makeProcessor(transcriber: Transcribing? = nil) -> MeetingProcessor {
        MeetingProcessor(
            transcriber: transcriber ?? self.transcriber,
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
        transcriber.modelIsMissing = true
        var downloadsReported = 0
        let processor = MeetingProcessor(
            transcriber: transcriber,
            summarizer: Summarizer(runner: runner, home: URL(fileURLWithPath: "/Users/test"), isExecutable: { _ in true }),
            locale: { Locale(identifier: "de-DE") },
            trash: { try FileManager.default.removeItem(at: $0) })

        let outcome = await processor.process(meeting, onStep: { _ in }, onDownload: { downloadsReported += 1 })

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(downloadsReported, 1)
        XCTAssertEqual(transcriber.downloads, ["de-DE"])
        XCTAssertEqual(transcriber.transcribedLocales, ["de-DE", "de-DE"])
    }

    func testTheCLIGetsTheTranscriptFromDisk() async throws {
        let meeting = try makeMeeting()

        _ = await process(meeting)

        XCTAssertEqual(runner.calls.first?.arguments.last, SummaryPrompt.make(transcript: try meeting.read(.transcript)))
    }

    func testATranscriptionFailureWritesTheReasonAndKeepsTheAudio() async throws {
        let meeting = try makeMeeting()
        transcriber.byFileName["them.caf"] = .failure(TestError(errorDescription: "The audio file could not be read."))

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .failed(.transcribe, message: "The audio file could not be read."))
        let errorText = """
        # Transcription Failed

        2026-10-23 15:00

        The audio file could not be read.

        Choose Retry Failed Meeting in the Ku-Ka menu to try again.

        """
        XCTAssertEqual(try meeting.read(.failure), errorText)
        XCTAssertEqual(meeting.stage(), .failed(.transcribe))
        XCTAssertTrue(audioExists(meeting))
        XCTAssertEqual(trashed, [])
        XCTAssertEqual(runner.calls.count, 0)
    }

    func testNoSpeechEndsTheMeetingAndKeepsTheAudio() async throws {
        let meeting = try makeMeeting()
        transcriber.byFileName = [:]

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .noSpeech)
        XCTAssertEqual(meeting.stage(), .done)
        XCTAssertEqual(try meeting.read(.transcript), """
        # Meeting on 2026-10-23 at 14:02

        Duration: 00:00:00

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
        transcriber.byFileName["them.caf"] = .failure(TestError(errorDescription: "must not transcribe again"))
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
        let processor = makeProcessor(transcriber: SuspendedTranscriber())
        let run = Task { await process(meeting, with: processor) }
        await waitUntil { !steps.isEmpty }
        XCTAssertEqual(steps, [.transcribe])

        run.cancel()

        let outcome = await run.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(meeting.stage(), .pending(.transcribe))
    }
}

private struct SuspendedTranscriber: Transcribing {
    func needsDownload(for locale: Locale) async throws -> Bool { false }
    func download(for locale: Locale) async throws {}

    func transcribe(_ audio: URL, locale: Locale) async throws -> TrackTranscript {
        try await Task.sleep(for: .seconds(60))
        return TrackTranscript(segments: [], duration: 0)
    }
}
