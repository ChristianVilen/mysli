import XCTest
@testable import KuKa

@MainActor
final class MeetingProcessorNotesTests: MeetingProcessorTestCase {

    private func hearConvio() {
        whisper.byFileName["them.caf"] = .success(TrackTranscript(
            segments: [TranscriptSegment(start: 1, end: 3, text: "Let's ask Convio and Yuri about Friday")], duration: 60))
    }

    private func promptTranscript() throws -> String {
        try XCTUnwrap(runner.calls.last?.arguments.last?.components(separatedBy: "Transcript:\n\n").last)
    }

    private func exists(_ document: MeetingDocument, in meeting: MeetingFolder) -> Bool {
        FileManager.default.fileExists(atPath: meeting.url(for: document).path)
    }

    private func removeAudio(of meeting: MeetingFolder) throws {
        try FileManager.default.removeItem(at: meeting.audioURL(.system).deletingLastPathComponent())
    }

    private let correctedLines = """
    **[00:00:01] Them:** Let's ask Konvio and Yuri about Friday

    **[00:00:04] Me:** Sounds good

    """

    func testTheTranscribeStepWritesTheHeardCopyWithTheTextOfTheTranscript() async throws {
        let meeting = try makeMeeting()
        var heardCopyBeforeSummarizing: String?

        _ = await makeProcessor().process(meeting, tool: .automatic) { event in
            if event == .step(.summarize) { heardCopyBeforeSummarizing = try? meeting.read(.heardTranscript) }
        }

        XCTAssertEqual(heardCopyBeforeSummarizing, try meeting.read(.transcript))

        let silent = try makeMeeting()
        whisper.byFileName = [:]
        let outcome = await process(silent)
        XCTAssertEqual(outcome, .noSpeech)
        XCTAssertEqual(try silent.read(.heardTranscript), try silent.read(.transcript))
    }

    func testAConfirmedFormIsFixedInTheTranscriptAndInTheTextTheCLIGets() async throws {
        let meeting = try makeMeeting()
        hearConvio()
        knownWords = KnownWordsList(markdown: "- Convio → **Konvio** ✓\n")

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(try meeting.read(.transcript), """
        # Meeting on 2026-10-23 at 14:02

        Duration: 00:01:00

        Transcript by Whisper.

        "Me" is the microphone of the Mac that recorded the meeting. It hears the person who recorded the meeting and anyone in the same room. "Them" is everyone else on the call.

        \(correctedLines)
        ---

        Known words applied: Convio → Konvio (1).

        """)
        XCTAssertEqual(try promptTranscript(), correctedLines, "no note for the CLI")
        XCTAssertTrue(try meeting.read(.heardTranscript).contains("**[00:00:01] Them:** Let's ask Convio and Yuri about Friday"))
    }

    func testOnlyTheKnownWordsThatOccurInTheTranscriptReachThePrompt() async throws {
        let meeting = try makeMeeting()
        hearConvio()
        knownWords = KnownWordsList(markdown: "- Convio → **Konvio** ✓\n- Brightlane → **Brytlane**\n")

        _ = await process(meeting)

        let prompt = try XCTUnwrap(runner.calls.first?.arguments.last)
        XCTAssertTrue(prompt.contains("\n- Convio -> Konvio\n"), prompt)
        XCTAssertFalse(prompt.contains("Brytlane"), prompt)
    }

    func testSummarizingAgainAfterAStopStartsFromTheHeardCopyWithTheListAsItIsNow() async throws {
        let meeting = try makeMeeting()
        try removeAudio(of: meeting)
        try meeting.write("**[00:00:01] Them:** Ask Convio and Yuri.\n", to: .heardTranscript)
        try meeting.write("**[00:00:01] Them:** Ask Konvio and Yuri.\n\n---\n\nKnown words applied: Convio → Konvio (1).\n",
                          to: .transcript)
        knownWords = KnownWordsList(markdown: "- Convio → **Konvio** ✓\n- Yuri → **Jyri** ✓\n")

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(try meeting.read(.transcript),
                       "**[00:00:01] Them:** Ask Konvio and Jyri.\n\n---\n\nKnown words applied: Convio → Konvio (1), Yuri → Jyri (1).\n")
        XCTAssertEqual(try meeting.read(.heardTranscript), "**[00:00:01] Them:** Ask Convio and Yuri.\n")
    }

    func testAFormConfirmedAfterAFailedSummaryIsFixedOnRetry() async throws {
        let meeting = try makeMeeting()
        hearConvio()
        runner.results["agy"] = .success(CommandResult(termination: .exited(1), stdout: "", stderr: "authentication failed"))
        _ = await process(meeting)
        XCTAssertTrue(try meeting.read(.transcript).contains("Let's ask Convio"))
        knownWords = KnownWordsList(markdown: "- Convio → **Konvio** ✓\n")
        try meeting.clearFailure()
        runner.results["agy"] = .reply("## Summary\nAsk Konvio.")

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertTrue(try meeting.read(.transcript).hasSuffix(correctedLines + "\n---\n\nKnown words applied: Convio → Konvio (1).\n"))
    }

    func testAMeetingTranscribedBeforeKnownWordsGetsAHeardCopyAndACorrectedTranscript() async throws {
        let meeting = try makeMeeting()
        try removeAudio(of: meeting)
        try meeting.write("**[00:00:01] Them:** Ask Convio.\n", to: .transcript)
        knownWords = KnownWordsList(markdown: "- Convio → **Konvio** ✓\n")

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(try meeting.read(.heardTranscript), "**[00:00:01] Them:** Ask Convio.\n")
        XCTAssertEqual(try meeting.read(.transcript),
                       "**[00:00:01] Them:** Ask Konvio.\n\n---\n\nKnown words applied: Convio → Konvio (1).\n")
    }

    func testAReplyWithAReviewBlockSavesItsQuestionsAndTheSummaryLeavesTheBlockOut() async throws {
        let meeting = try makeMeeting()
        hearConvio()
        runner.results["agy"] = .reply("""
        ## Summary
        Ask Convio.

        ```ku-ka-review
        [{"heard": "Convio", "suggestion": "Konvio", "kind": "company", "quote": "Let's ask Convio and Yuri about Friday", "reason": "unknown company"},
         {"heard": "Quorix", "kind": "term", "quote": "Quorix is late.", "reason": "not in the transcript"}]
        ```
        """)

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(try meeting.read(.summary), "# Meeting on 2026-10-23 at 14:02\n\n## Summary\nAsk Convio.\n")
        let review = try XCTUnwrap(meeting.wordReview(knownWords: .empty))
        XCTAssertEqual(review.questions.map(\.heard), ["Convio"])
        XCTAssertEqual(review.questions.first?.suggestion, "Konvio")
        XCTAssertEqual(review.questions.first?.place, "Them at 00:00:01")
    }

    func testTheQuestionsAreSavedBeforeTheSummary() async throws {
        let meeting = try makeMeeting()
        hearConvio()
        runner.results["agy"] = .reply("""
        ## Summary
        Ask Convio.

        ```ku-ka-review
        [{"heard": "Convio", "kind": "company", "quote": "Let's ask Convio and Yuri about Friday"}]
        ```
        """)
        let blocked = meeting.url(for: .questions).appendingPathComponent("a folder in the way")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)

        let outcome = await process(meeting)

        guard case .failed(.summarize, _) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertFalse(exists(.summary, in: meeting))
    }

    func testABrokenReviewBlockNeverFailsTheSummaryAndSavesNoQuestions() async throws {
        let meeting = try makeMeeting()
        runner.results["agy"] = .reply("## Summary\nShip Friday.\n\n```ku-ka-review\n[{\"heard\": \n```\n")

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(try meeting.read(.summary), "# Meeting on 2026-10-23 at 14:02\n\n## Summary\nShip Friday.\n")
        XCTAssertFalse(exists(.questions, in: meeting))
    }

    func testARunWithoutQuestionsRemovesTheQuestionsOfAnEarlierStoppedRun() async throws {
        let meeting = try makeMeeting()
        try removeAudio(of: meeting)
        try meeting.write("**[00:00:01] Them:** Let's ship on Friday\n", to: .transcript)
        try meeting.write(#"{"questions": [{"heard": "Friday", "kind": "term", "quote": "Let's ship on Friday"}]}"#, to: .questions)

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertFalse(exists(.questions, in: meeting))
    }

    private func makeDoneMeeting() async throws -> MeetingFolder {
        let meeting = try makeMeeting()
        hearConvio()
        let outcome = await process(meeting)
        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        return meeting
    }

    func testUpdateNotesMakesTheNotesAgainWithTheListAsItIsNowAndKeepsTheReviewFiles() async throws {
        let meeting = try await makeDoneMeeting()
        let questions = #"{"questions": [{"heard": "Convio", "kind": "company", "quote": "Let's ask Convio and Yuri about Friday"}]}"#
        let skips = #"{"skipped": ["Convio"]}"#
        try meeting.write(questions, to: .questions)
        try meeting.write(skips, to: .skipped)
        knownWords = KnownWordsList(markdown: "- Convio → **Konvio** ✓\n")
        runner.results["agy"] = .reply("""
        ## Summary
        Ask Konvio.

        ```ku-ka-review
        [{"heard": "Yuri", "kind": "person", "quote": "Let's ask Konvio and Yuri about Friday"}]
        ```
        """)

        let outcome = await makeProcessor().updateNotes(meeting, tool: .automatic)

        XCTAssertEqual(outcome, .updated(summary: meeting.url(for: .summary)))
        XCTAssertTrue(try meeting.read(.transcript).hasSuffix(correctedLines + "\n---\n\nKnown words applied: Convio → Konvio (1).\n"))
        XCTAssertEqual(try promptTranscript(), correctedLines)
        XCTAssertEqual(try meeting.read(.summary), "# Meeting on 2026-10-23 at 14:02\n\n## Summary\nAsk Konvio.\n")
        XCTAssertEqual(try meeting.read(.questions), questions)
        XCTAssertEqual(try meeting.read(.skipped), skips)
        XCTAssertEqual(meeting.stage(), .done)
        XCTAssertFalse(exists(.failure, in: meeting))
    }

    func testUpdateNotesAsksNoNewQuestions() async throws {
        let meeting = try await makeDoneMeeting()
        runner.results["agy"] = .reply("""
        ## Summary
        Ask Convio.

        ```ku-ka-review
        [{"heard": "Convio", "kind": "company", "quote": "Let's ask Convio and Yuri about Friday"}]
        ```
        """)

        let outcome = await makeProcessor().updateNotes(meeting, tool: .automatic)

        XCTAssertEqual(outcome, .updated(summary: meeting.url(for: .summary)))
        XCTAssertEqual(try meeting.read(.summary), "# Meeting on 2026-10-23 at 14:02\n\n## Summary\nAsk Convio.\n")
        XCTAssertFalse(exists(.questions, in: meeting))
    }

    func testWhenEveryCLIFailsUpdateNotesKeepsTheOldSummaryAndWritesNoErrorFile() async throws {
        let meeting = try await makeDoneMeeting()
        let summary = try meeting.read(.summary)
        runner.results["agy"] = .success(CommandResult(termination: .exited(1), stdout: "", stderr: "authentication failed"))
        runner.results["claude"] = .success(CommandResult(termination: .timedOut, stdout: "", stderr: ""))

        let outcome = await makeProcessor().updateNotes(meeting, tool: .automatic)

        XCTAssertEqual(outcome, .summaryToolFailed(message: "agy exited with status 1: authentication failed\nclaude took too long and was stopped"))
        XCTAssertEqual(try meeting.read(.summary), summary)
        XCTAssertFalse(exists(.failure, in: meeting))
        XCTAssertEqual(meeting.stage(), .done)
    }

    func testAnUpdateThatCannotReadTheTranscriptFailsBeforeTheCLIAndWritesNoErrorFile() async throws {
        let meeting = try await makeDoneMeeting()
        let summary = try meeting.read(.summary)
        let callsBefore = runner.calls.count
        try FileManager.default.removeItem(at: meeting.url(for: .heardTranscript))
        try FileManager.default.removeItem(at: meeting.url(for: .transcript))

        let outcome = await makeProcessor().updateNotes(meeting, tool: .automatic)

        guard case .failed(let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(message.contains("transcript.md"), message)
        XCTAssertEqual(runner.calls.count, callsBefore, "no CLI ran")
        XCTAssertEqual(try meeting.read(.summary), summary)
        XCTAssertFalse(exists(.failure, in: meeting))
    }

    func testUpdateNotesLeavesALockedUnfinishedOrMissingMeetingAlone() async throws {
        let done = try await makeDoneMeeting()
        let callsBefore = runner.calls.count
        let otherWriter = try done.lock()
        let busy = await makeProcessor().updateNotes(done, tool: .automatic)
        otherWriter.release()

        let unfinished = try makeMeeting()
        try removeAudio(of: unfinished)
        try unfinished.write("**[00:00:01] Them:** Ask Convio.\n", to: .transcript)
        let notReady = await makeProcessor().updateNotes(unfinished, tool: .automatic)

        let gone = try makeMeeting()
        try FileManager.default.removeItem(at: gone.url)
        let missing = await makeProcessor().updateNotes(gone, tool: .automatic)

        XCTAssertEqual(busy, .busy)
        XCTAssertEqual(notReady, .notReady)
        XCTAssertEqual(missing, .notReady)
        XCTAssertEqual(runner.calls.count, callsBefore, "no CLI ran")
        XCTAssertEqual(unfinished.stage(), .pending(.summarize))
        XCTAssertFalse(exists(.heardTranscript, in: unfinished))
    }

    func testCancellingUpdateNotesReturnsCancelledAndKeepsTheSummary() async throws {
        let meeting = try await makeDoneMeeting()
        let summary = try meeting.read(.summary)
        let waiting = WaitingCommandRunner()
        let processor = makeProcessor(runner: waiting)
        let run = Task { await processor.updateNotes(meeting, tool: .automatic) }
        await waitUntil { waiting.started }

        run.cancel()

        let outcome = await run.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(try meeting.read(.summary), summary)
        XCTAssertEqual(meeting.stage(), .done)
        XCTAssertFalse(exists(.failure, in: meeting))
    }
}

private final class WaitingCommandRunner: CommandRunning {
    private(set) var started = false

    func run(executable: URL, arguments: [String], input: String?, searchPath: [String],
             timeout: Duration) async throws -> CommandResult {
        started = true
        try await Task.sleep(for: .seconds(60))
        return CommandResult(termination: .exited(0), stdout: "## Summary\nToo late.", stderr: "")
    }
}
