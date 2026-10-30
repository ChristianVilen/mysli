import XCTest
@testable import KuKa

@MainActor
final class SummaryToolJobTests: MeetingNotesTestCase {
    private var tool = SummaryTool.antigravity

    private func installController(transcriber: Transcribing) {
        sut.shutDown()
        sut = MeetingNotesController(
            recorder: recorder,
            root: { [unowned self] in root },
            processor: makeMeetingProcessor(transcribers: [transcriber], runner: runner),
            wordsToCheck: { _ in 0 },
            summaryTool: { [unowned self] in tool },
            notifier: notifier,
            openURL: { _ in })
        menu = NSMenu()
        sut.buildMenuSection(into: menu)
        runner.results["claude"] = .reply(defaultNotes)
    }

    private var toolsRun: [String] { runner.calls.map { $0.executable.lastPathComponent } }

    func testRunningTranscriptionKeepsItsToolAndNextQueuedJobReadsTheNewTool() async throws {
        let held = HeldTranscriber()
        installController(transcriber: held)
        let first = try leftoverMeeting(at: localDate(2026, 10, 22, 9, 0))
        let second = try leftoverMeeting(at: localDate(2026, 10, 22, 10, 0))
        sut.resumeUnfinished()
        await waitUntil { held.waiting }
        XCTAssertTrue(held.waiting)
        tool = .claude
        held.release()
        await sut.waitUntilIdle()
        XCTAssertEqual(toolsRun, ["agy", "claude"])
        XCTAssertEqual(first.stage(), .done)
        XCTAssertEqual(second.stage(), .done)
    }

    func testRetryAndUpdateNotesReadTheLatestChoiceWhenTheyStart() async throws {
        installController(transcriber: transcriber)
        let meeting = try leftoverMeeting(at: clock, failure: "failed", transcript: true)
        tool = .claude
        sut.menuWillOpen()
        let retry = try XCTUnwrap(item(titled: "Retry Failed Meeting"))
        _ = (retry.target as? NSObject)?.perform(retry.action, with: retry)
        await sut.waitUntilIdle()
        XCTAssertEqual(meeting.stage(), .done)
        tool = .antigravity
        sut.updateNotes(meeting)
        await sut.waitUntilIdle()
        XCTAssertEqual(toolsRun, ["claude", "agy"])
    }
}

@MainActor
private final class HeldTranscriber: FakeTranscriber {
    private var continuation: CheckedContinuation<Void, Never>?
    private var held = false
    var waiting: Bool { continuation != nil }

    func release() {
        continuation?.resume()
        continuation = nil
    }

    override func transcribe(_ audio: URL) async throws -> TrackTranscript {
        if !held {
            held = true
            await withCheckedContinuation { continuation = $0 }
        }
        return TrackTranscript(segments: [TranscriptSegment(start: 1, end: 3, text: "Ship Friday")], duration: 60)
    }
}
