import XCTest
@testable import Mysli

final class WhisperInferenceQueueTests: XCTestCase {
    func testDictationRunsBeforeTheNextMeetingBatchAndCancelledWorkNeverStarts() async throws {
        let queue = WhisperInferenceQueue()
        let entered = AudioTestSignal()
        let finish = AudioTestSignal()
        let order = InferenceOrder()
        let active = Task {
            try await queue.run(priority: false) {
                await order.append("meeting 1")
                await entered.send()
                await finish.value()
            }
        }
        await entered.value()
        let meeting = Task { try await queue.run(priority: false) { await order.append("meeting 2") } }
        await waitForPending(1, in: queue)
        let cancelled = Task { try await queue.run(priority: true) { await order.append("cancelled") } }
        await waitForPending(2, in: queue)
        let dictation = Task { try await queue.run(priority: true) { await order.append("dictation") } }
        await waitForPending(3, in: queue)
        cancelled.cancel()
        do { try await cancelled.value; XCTFail("Cancelled work ran") } catch is CancellationError {}
        await finish.send()
        try await active.value
        try await dictation.value
        try await meeting.value
        let values = await order.values
        XCTAssertEqual(values, ["meeting 1", "dictation", "meeting 2"])
    }

    private func waitForPending(_ count: Int, in queue: WhisperInferenceQueue) async {
        for _ in 0..<1_000 {
            if await queue.pendingCount == count { return }
            await Task.yield()
        }
        XCTFail("Inference did not reach the expected queue boundary")
    }
}

private actor InferenceOrder {
    var values: [String] = []
    func append(_ value: String) { values.append(value) }
}
