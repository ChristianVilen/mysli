import XCTest
@testable import KuKa

@MainActor
final class MeetingContextProcessingTests: MeetingProcessorTestCase {
    func testRetryAndUpdateNotesReadTheCurrentContextPathAndBytes() async throws {
        let meeting = try makeMeeting()
        let root = try makeTemporaryDirectory()
        var contextURL = root.appendingPathComponent("first.md")
        try Data("Initial background".utf8).write(to: contextURL)
        let summarizer = Summarizer(runner: runner, isExecutable: { _ in true },
                                    context: MeetingContextFile(url: { contextURL }))
        let processor = MeetingProcessor(transcribers: [whisper, apple], roomLabeller: labeller,
                                         summarizer: summarizer, knownWords: { .empty },
                                         trash: { try FileManager.default.removeItem(at: $0) })
        runner.results["agy"] = .success(CommandResult(termination: .exited(1), stdout: "", stderr: "failed"))
        runner.results["claude"] = .success(CommandResult(termination: .exited(1), stdout: "", stderr: "failed"))
        guard case .failed(.summarize, _) = await processor.process(meeting, tool: .automatic, progress: { _ in }) else {
            return XCTFail("Expected the summary step to fail")
        }
        XCTAssertTrue(try XCTUnwrap(runner.calls.last?.input).contains("Initial background"))
        contextURL = root.appendingPathComponent("second.md")
        try Data("Retry background".utf8).write(to: contextURL)
        runner.results["agy"] = .reply(defaultNotes)
        try meeting.clearFailure()
        let retried = await processor.process(meeting, tool: .automatic, progress: { _ in })
        XCTAssertEqual(retried, .done(summary: meeting.url(for: .summary)))
        XCTAssertTrue(try XCTUnwrap(runner.calls.last?.arguments.last).contains("Retry background"))
        try Data("Updated background".utf8).write(to: contextURL)
        let updated = await processor.updateNotes(meeting, tool: .automatic)
        XCTAssertEqual(updated, .updated(summary: meeting.url(for: .summary)))
        XCTAssertTrue(try XCTUnwrap(runner.calls.last?.arguments.last).contains("Updated background"))
        XCTAssertFalse(try meeting.read(.transcript).contains("background"))
    }
}
