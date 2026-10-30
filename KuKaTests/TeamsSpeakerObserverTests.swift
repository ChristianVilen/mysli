import XCTest
@testable import KuKa

final class TeamsSpeakerObserverTests: XCTestCase {
    func testSubscriptionStartsSerialOffMainScansWithBracketedTimesAndUncertainty() async {
        let state = PollState()
        let observer = TeamsSpeakerObserver(makeSource: { state.make() }, now: { state.time() }, wait: { interval in
            state.interval(interval)
            try await Task.sleep(for: .milliseconds(1))
        })
        XCTAssertEqual(state.factories, 0)
        var samples: [TeamsSpeakerObservation] = []
        let consumer = Task {
            for await sample in observer.observations() {
                samples.append(sample)
                if samples.count == 3 { break }
            }
        }
        await consumer.value
        XCTAssertEqual(samples.map(\.sequence), [1, 2, 3])
        XCTAssertEqual(samples.map(\.result), [.named(TeamsSpeakerName("Ada")!), .unnamed(.noHighlightedTile),
                                               .named(TeamsSpeakerName("Ada")!)])
        XCTAssertEqual(samples.map(\.nodes), [5, 3, 5])
        XCTAssertEqual(samples.map(\.began.seconds), [1, 3, 5])
        XCTAssertEqual(samples.map(\.ended.seconds), [2, 4, 6])
        XCTAssertEqual(samples.map(\.sourceID), ["window", nil, "window"])
        XCTAssertEqual(state.factories, 1)
        XCTAssertFalse(state.mainThread)
        XCTAssertEqual(state.maximumConcurrent, 1)
        XCTAssertTrue(state.intervals.allSatisfy { $0 == 0.3 })
    }

    func testCancellationReleasesSourceAndStopsPendingPolls() async {
        let scanned = expectation(description: "first scan")
        let released = expectation(description: "source released")
        let observer = TeamsSpeakerObserver(makeSource: {
            ReleasingSource(scanned: scanned, released: released)
        })
        let consumer = Task {
            for await _ in observer.observations() {}
        }
        await fulfillment(of: [scanned], timeout: 2)
        consumer.cancel()
        await consumer.value
        await fulfillment(of: [released], timeout: 2)
    }

    func testCancelledScanCannotYieldItsLateResult() async {
        let began = expectation(description: "scan began")
        let released = expectation(description: "source released")
        let gate = DispatchSemaphore(value: 0)
        let observer = TeamsSpeakerObserver(makeSource: {
            ReleasingSource(scanned: began, released: released, gate: gate)
        })
        let consumer = Task { () -> [TeamsSpeakerObservation] in
            var result: [TeamsSpeakerObservation] = []
            for await sample in observer.observations() { result.append(sample) }
            return result
        }
        await fulfillment(of: [began], timeout: 2)
        consumer.cancel()
        gate.signal()
        let result = await consumer.value
        XCTAssertTrue(result.isEmpty)
        await fulfillment(of: [released], timeout: 2)
    }

    func testBoundedBufferKeepsNewestEightSamplesAndExposesSequenceLoss() async {
        let filled = expectation(description: "twelve scans")
        let state = BufferedPollState(filled: filled)
        let observer = TeamsSpeakerObserver(makeSource: { state }, wait: { _ in try await state.wait() })
        let samples = await Task { () -> [Int] in
            var iterator = observer.observations().makeAsyncIterator()
            let first = await iterator.next()!
            state.resume()
            await fulfillment(of: [filled], timeout: 2)
            var result = [first.sequence]
            for _ in 0..<8 { result.append(await iterator.next()!.sequence) }
            return result
        }.value
        XCTAssertEqual(samples, [1, 5, 6, 7, 8, 9, 10, 11, 12])
    }
}

private final class ReleasingSource: TeamsSnapshotReading {
    let scanned: XCTestExpectation
    let released: XCTestExpectation
    let gate: DispatchSemaphore?
    init(scanned: XCTestExpectation, released: XCTestExpectation, gate: DispatchSemaphore? = nil) {
        self.scanned = scanned
        self.released = released
        self.gate = gate
    }
    func snapshot() -> TeamsAXSnapshot {
        scanned.fulfill()
        gate?.wait()
        return TeamsAXSnapshot(sourceID: "window", result: .named(TeamsSpeakerName("Ada")!))
    }
    deinit { released.fulfill() }
}

private final class BufferedPollState: TeamsSnapshotReading, @unchecked Sendable {
    private let lock = NSLock()
    private let filled: XCTestExpectation
    private var scans = 0
    private var resumed = false
    init(filled: XCTestExpectation) { self.filled = filled }
    func snapshot() -> TeamsAXSnapshot {
        lock.lock(); defer { lock.unlock() }
        scans += 1
        return TeamsAXSnapshot(sourceID: "window", result: .named(TeamsSpeakerName("Ada")!))
    }
    func resume() { lock.lock(); resumed = true; lock.unlock() }
    private func state() -> (Int, Bool) {
        lock.lock(); defer { lock.unlock() }
        return (scans, resumed)
    }
    func wait() async throws {
        if state().0 == 12 {
            filled.fulfill()
            try await Task.sleep(for: .seconds(60))
        }
        while !state().1 { try await Task.sleep(for: .milliseconds(1)) }
        await Task.yield()
    }
}

private final class PollState: TeamsSnapshotReading, @unchecked Sendable {
    private let lock = NSLock()
    private var tick = 0.0
    private var scans = 0
    private var active = 0
    private(set) var factories = 0
    private(set) var mainThread = false
    private(set) var maximumConcurrent = 0
    private(set) var intervals: [TimeInterval] = []
    func make() -> PollState {
        lock.lock(); defer { lock.unlock() }
        factories += 1
        mainThread = mainThread || Thread.isMainThread
        return self
    }
    func time() -> HostTime {
        lock.lock(); defer { lock.unlock() }
        tick += 1
        return HostTime(seconds: tick)
    }
    func interval(_ interval: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        intervals.append(interval)
    }
    func snapshot() -> TeamsAXSnapshot {
        lock.lock()
        active += 1
        maximumConcurrent = max(maximumConcurrent, active)
        mainThread = mainThread || Thread.isMainThread
        scans += 1
        let scan = scans
        lock.unlock()
        Thread.sleep(forTimeInterval: 0.001)
        lock.lock()
        active -= 1
        lock.unlock()
        return scan == 2
            ? TeamsAXSnapshot(result: .unnamed(.noHighlightedTile), nodes: 3)
            : TeamsAXSnapshot(sourceID: "window", result: .named(TeamsSpeakerName("Ada")!), nodes: 5)
    }
}
