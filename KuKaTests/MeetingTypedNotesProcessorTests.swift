import XCTest
@testable import KuKa

@MainActor
final class MeetingTypedNotesProcessorTests: MeetingProcessorTestCase {
    func testInitialSummaryIncludesTypedNotesSeparatelyFromTranscript() async throws {
        let meeting = try makeMeeting()
        try Data("Decision: ship Monday. Mira owns the checklist.\n".utf8)
            .write(to: meeting.url.appendingPathComponent("notes.md"), options: .atomic)

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        let prompt = try XCTUnwrap(runner.calls.first?.arguments.last)
        XCTAssertTrue(prompt.contains("Decision: ship Monday. Mira owns the checklist."))
        XCTAssertFalse(try meeting.read(.transcript).contains("Mira"))
        XCTAssertFalse(try meeting.read(.heardTranscript).contains("Mira"))
    }

    func testSilentRecordingWithTypedNotesStillUsesSummaryTool() async throws {
        let meeting = try makeMeeting()
        whisper.byFileName = [:]
        try Data("Mira will send the checklist on Monday.".utf8)
            .write(to: meeting.url.appendingPathComponent("notes.md"), options: .atomic)

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(try meeting.read(.summary), "# Meeting on 2026-10-23 at 14:02\n\n## Summary\nShip Friday.\n")
    }

    func testSummaryOnlyUpdatePreservesTranscriptHeardCopyAndReviewFiles() async throws {
        let meeting = try makeMeeting()
        _ = await process(meeting)
        let preserved: [MeetingDocument: String] = [
            .transcript: "Manually edited transcript with Convio.\n",
            .heardTranscript: "Original Convio.\n",
            .questions: "{\"questions\": []}",
            .skipped: "{\"skipped\": [\"Convio\"]}",
        ]
        for (document, text) in preserved { try meeting.write(text, to: document) }
        try meeting.write("Mira owns the Monday checklist.", to: .notes)
        knownWords = KnownWordsList(markdown: "- Convio → **Konvio** ✓\n")
        runner.results["agy"] = .reply("## Summary\nMira owns the checklist.")

        let outcome = await makeProcessor().updateSummary(meeting, tool: .automatic)

        XCTAssertEqual(outcome, .updated(summary: meeting.url(for: .summary)))
        for (document, text) in preserved { XCTAssertEqual(try meeting.read(document), text) }
        let prompt = try XCTUnwrap(runner.calls.last?.arguments.last)
        XCTAssertTrue(prompt.contains("Manually edited transcript with Convio."))
        XCTAssertTrue(prompt.contains("Mira owns the Monday checklist."))
        XCTAssertEqual(meeting.stage(), .done)
    }

    func testFailedSummaryOnlyUpdateKeepsOldSummaryAndDoesNotWriteFailure() async throws {
        let meeting = try makeMeeting()
        _ = await process(meeting)
        let previous = try meeting.read(.summary)
        runner.results["agy"] = .failure(TestError(errorDescription: "Offline"))
        runner.results["claude"] = .failure(TestError(errorDescription: "Offline"))

        let outcome = await makeProcessor().updateSummary(meeting, tool: .automatic)

        guard case .summaryToolFailed = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(try meeting.read(.summary), previous)
        XCTAssertEqual(meeting.stage(), .done)
        XCTAssertFalse(FileManager.default.fileExists(atPath: meeting.url(for: .failure).path))
    }

    func testKnownWordUpdateAlsoReadsFreshTypedNotes() async throws {
        let meeting = try makeMeeting()
        _ = await process(meeting)
        try meeting.write("Changed typed decision for Mira.", to: .notes)

        _ = await makeProcessor().updateNotes(meeting, tool: .automatic)

        XCTAssertTrue(try XCTUnwrap(runner.calls.last?.arguments.last).contains("Changed typed decision for Mira."))
    }

    func testInvalidNotesFailSummaryWithoutLosingCompletedTranscription() async throws {
        for silent in [false, true] {
            let meeting = try makeMeeting()
            if silent { whisper.byFileName = [:] }
            try meeting.write(String(repeating: "x", count: 65_537), to: .notes)

            let outcome = await process(meeting)

            guard case .failed(.summarize, _) = outcome else { return XCTFail("\(outcome)") }
            XCTAssertEqual(meeting.stage(), .failed(.summarize))
            XCTAssertEqual(try meeting.read(.heardTranscript), try meeting.read(.transcript))
            let transcript = try meeting.read(.transcript)
            let transcribedCount = whisper.transcribed.count
            try meeting.write("Repaired notes", to: .notes)
            try meeting.clearFailure()
            let retry = await process(meeting)
            XCTAssertEqual(retry, .done(summary: meeting.url(for: .summary)))
            XCTAssertEqual(try meeting.read(.transcript), transcript)
            XCTAssertEqual(whisper.transcribed.count, transcribedCount)
        }
    }

    func testNotesOnlyFailedSummaryRemainsRetryable() async throws {
        let meeting = try makeMeeting()
        whisper.byFileName = [:]
        try meeting.write("Mira owns the checklist.", to: .notes)
        runner.results["agy"] = .failure(TestError(errorDescription: "Offline"))
        runner.results["claude"] = .failure(TestError(errorDescription: "Offline"))
        let outcome = await process(meeting)
        guard case .failed(.summarize, _) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(meeting.stage(), .failed(.summarize))
        XCTAssertFalse(FileManager.default.fileExists(atPath: meeting.url(for: .summary).path))
        let transcribedCount = whisper.transcribed.count
        runner.results["agy"] = .reply(defaultNotes)
        try meeting.clearFailure()
        let retry = await process(meeting)
        XCTAssertEqual(retry, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(whisper.transcribed.count, transcribedCount)
        XCTAssertTrue(try XCTUnwrap(runner.calls.last?.arguments.last).contains("Mira owns the checklist."))
    }
}

@MainActor
final class MeetingTypedNotesLifecycleTests: MeetingNotesTestCase {
    func testNotesStayWithTheirMeetingAcrossPauseStopRootChangeAndNextRecording() async throws {
        await recorder.toggleRecording()
        let first = try XCTUnwrap(recorder.activeMeeting)
        let notes = try sut.typedNotes(for: first)
        notes.edit("First meeting notes")
        XCTAssertEqual(try first.read(.notes), "First meeting notes")
        recorder.togglePause()
        notes.edit("Notes written while paused")
        XCTAssertEqual(recorder.activeMeeting, first)
        recorder.togglePause()
        recorder.stopRecording()
        await sut.waitUntilIdle()
        root = try makeTemporaryDirectory().appendingPathComponent("New root")
        await recorder.toggleRecording()
        let second = try XCTUnwrap(recorder.activeMeeting)
        XCTAssertNotEqual(first, second)
        notes.edit("First meeting, after Stop")
        XCTAssertEqual(try first.read(.notes), "First meeting, after Stop")
        XCTAssertEqual(try MeetingTypedNotesFile.read(in: second), "")
        XCTAssertTrue(try sut.typedNotes(for: first) === notes)
        XCTAssertTrue(sut.recentNotesMeetings.contains(first))
    }

    func testFailedSaveRetainsDraftAndStopWaitsUntilRetrySavesIt() async throws {
        await recorder.toggleRecording()
        let meeting = try XCTUnwrap(recorder.activeMeeting)
        let notes = try sut.typedNotes(for: meeting)
        try FileManager.default.createDirectory(at: meeting.url(for: .notes), withIntermediateDirectories: false)
        notes.edit("Do not lose this decision")
        XCTAssertTrue(notes.hasUnsavedChanges)
        XCTAssertEqual(notes.text, "Do not lose this decision")
        XCTAssertNotNil(notes.saveError)

        recorder.stopRecording()
        await sut.waitUntilIdle()
        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertEqual(runner.calls.count, 0)
        XCTAssertTrue(sut.hasUnsavedTypedNotes)
        XCTAssertEqual(notes.summaryMessage, "Save your notes to start the summary.")

        try FileManager.default.removeItem(at: meeting.url(for: .notes))
        notes.save()
        await sut.waitUntilIdle()
        XCTAssertFalse(notes.hasUnsavedChanges)
        XCTAssertEqual(meeting.stage(), .done)
        XCTAssertTrue(try XCTUnwrap(runner.calls.last?.arguments.last).contains("Do not lose this decision"))
    }

    func testEditingDuringSummaryKeepsTheNewerNotesMarkedForAnExplicitUpdate() async throws {
        let held = TypedNotesGate()
        gate = held
        sut = makeController()
        await recorder.toggleRecording()
        let meeting = try XCTUnwrap(recorder.activeMeeting)
        let notes = try sut.typedNotes(for: meeting)
        notes.edit("First snapshot")
        recorder.stopRecording()
        await waitUntil { held.runs == 1 }
        notes.edit("Newer decision")
        XCTAssertFalse(notes.canUpdateSummary)
        XCTAssertFalse(sut.updateSummary(meeting))
        held.release()
        await sut.waitUntilIdle()
        XCTAssertEqual(notes.summaryMessage, "Saved notes have changed. Update the summary to include them.")
        XCTAssertEqual(held.prompts.count, 1)
        XCTAssertTrue(held.prompts[0].contains("First snapshot"))
        XCTAssertFalse(held.prompts[0].contains("Newer decision"))

        XCTAssertTrue(sut.updateSummary(meeting))
        XCTAssertFalse(sut.updateSummary(meeting))
        await waitUntil { held.runs == 2 }
        held.release()
        await sut.waitUntilIdle()
        XCTAssertEqual(notes.summaryMessage, "Summary includes these saved notes.")
        XCTAssertTrue(held.prompts[1].contains("Newer decision"))
    }

    func testCaptureFailureNeverExposesANotesDestination() async {
        capture.startError = TestError(errorDescription: "Cannot start")
        await recorder.toggleRecording()
        XCTAssertNil(recorder.activeMeeting)
        XCTAssertTrue(sut.recentNotesMeetings.isEmpty)
    }
}

private final class TypedNotesGate: CommandRunning {
    private let lock = NSLock()
    private var captured: [String] = []
    private var passes = 0
    var prompts: [String] { lock.withLock { captured } }
    var runs: Int { prompts.count }
    func release() { lock.withLock { passes += 1 } }

    func run(executable: URL, arguments: [String], input: String?, searchPath: [String],
             timeout: Duration) async throws -> CommandResult {
        lock.withLock { captured.append(input ?? arguments.last ?? "") }
        while !lock.withLock({
            guard passes > 0 else { return false }
            passes -= 1
            return true
        }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        return CommandResult(termination: .exited(0), stdout: defaultNotes, stderr: "")
    }
}
