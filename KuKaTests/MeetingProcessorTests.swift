import XCTest
@testable import KuKa

@MainActor
final class MeetingProcessorTests: MeetingProcessorTestCase {
    func testFirstRunWritesTranscriptAndSummaryAndTrashesTheAudio() async throws {
        let meeting = try makeMeeting()

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(progress, [.step(.transcribe), .step(.summarize)])
        XCTAssertEqual(try meeting.read(.transcript), """
        # Meeting on 2026-10-23 at 14:02

        Duration: 00:01:00

        Transcript by Whisper.

        "Me" is the microphone of the Mac that recorded the meeting. It hears the person who recorded the meeting and anyone in the same room. "Them" is everyone else on the call.

        **[00:00:01] Them:** Let's ship on Friday

        **[00:00:04] Me:** Sounds good

        """)
        XCTAssertEqual(try meeting.read(.summary), """
        # Meeting on 2026-10-23 at 14:02

        ## Summary
        Ship Friday.

        """)
        XCTAssertEqual(trashed, ["audio"])
        XCTAssertEqual(meeting.stage(), .done)
    }

    func testTheSummaryFromAFallbackCLIHasNoFooter() async throws {
        let meeting = try makeMeeting()
        runner.results["agy"] = .success(CommandResult(termination: .exited(1), stdout: "", stderr: "authentication failed"))
        runner.results["claude"] = .reply(defaultNotes)

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(try meeting.read(.summary), "# Meeting on 2026-10-23 at 14:02\n\n## Summary\nShip Friday.\n")
    }

    func testAMissingSpeechModelIsDownloadedForTheConfiguredLanguageFirst() async throws {
        let meeting = try makeMeeting()
        whisper.modelIsMissing = true
        let processor = makeMeetingProcessor(transcribers: [whisper, apple], roomLabeller: labeller, runner: runner,
                                             locale: Locale(identifier: "de-DE"))

        let outcome = await process(meeting, with: processor)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(progress, [.step(.transcribe), .downloading(.speech), .step(.transcribe), .step(.summarize)])
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

            "Me" is the microphone of the Mac that recorded the meeting. It hears the person who recorded the meeting and anyone in the same room. "Them" is everyone else on the call.

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

        _ = await process(meeting)

        XCTAssertEqual(progress, [.step(.transcribe), .downloading(.speech), .step(.transcribe), .step(.summarize)])
    }

    func testNoSpeechModelDownloadShowsWhileAnotherKuKaHoldsTheDownloadLock() async throws {
        let meeting = try makeMeeting()
        whisper.modelIsMissing = true
        whisper.downloadStarts = false
        whisper.failure = (.download, MeetingStepError("Another Ku-Ka is downloading the Whisper model."))

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(progress, [.step(.transcribe), .step(.summarize)])
        XCTAssertTrue(try meeting.read(.transcript).contains(
            "- Whisper could not download its model: Another Ku-Ka is downloading the Whisper model."))
        XCTAssertEqual(apple.loads, ["en-US"])
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

        "Me" is the microphone of the Mac that recorded the meeting. It hears the person who recorded the meeting and anyone in the same room. "Them" is everyone else on the call.

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
        XCTAssertEqual(progress, [])
        XCTAssertEqual(meeting.stage(), .pending(.transcribe))
        otherWriter.release()
    }

    func testAMeetingFolderThatCannotBeLockedFailsWithTheReason() async throws {
        let meeting = try makeMeeting()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: meeting.url.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: meeting.url.path) }

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .failed(.transcribe, message: "Ku-Ka could not lock the meeting folder \(meeting.url.path): Permission denied."))
        XCTAssertEqual(progress, [])
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
        XCTAssertEqual(progress, [])
    }

    func testRetryResumesAtTheFailedStep() async throws {
        let meeting = try makeMeeting()
        runner.results["agy"] = .success(CommandResult(termination: .exited(1), stdout: "", stderr: ""))
        _ = await process(meeting)
        try meeting.clearFailure()
        runner.results["claude"] = .reply(defaultNotes)
        whisper.byFileName["them.caf"] = .failure(TestError(errorDescription: "must not transcribe again"))
        progress = []

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(progress, [.step(.summarize)])
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
            progress = []
            trashed = []

            let outcome = await process(meeting)

            XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)), row.name)
            XCTAssertEqual(progress, row.steps.map { .step($0) }, row.name)
            XCTAssertEqual(trashed, row.trashed, row.name)
        }
    }

    func testCancellingLeavesTheMeetingPendingWithoutAnErrorFile() async throws {
        let meeting = try makeMeeting()
        let processor = makeProcessor(transcribers: [SuspendedTranscriber(name: "Whisper"), apple])
        let run = Task { await process(meeting, with: processor) }
        await waitUntil { !progress.isEmpty }
        XCTAssertEqual(progress, [.step(.transcribe)])

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
        suspended.downloadWaits = true
        let run = Task { await process(meeting, with: makeProcessor(transcribers: [suspended, apple])) }
        await waitUntil { progress.contains(.downloading(.speech)) }

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
