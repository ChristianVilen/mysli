import XCTest
@testable import KuKa

final class RecordingSpeakerSource: TeamsSpeakerObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var streams: [AsyncStream<TeamsSpeakerObservation>.Continuation] = []
    private var ended = 0
    var starts: Int { lock.withLock { streams.count } }
    var terminations: Int { lock.withLock { ended } }

    func observations() -> AsyncStream<TeamsSpeakerObservation> {
        AsyncStream { continuation in
            lock.withLock { streams.append(continuation) }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.ended += 1 }
            }
        }
    }

    func yield(_ time: Double, sequence: Int, name: String? = "Alice", run: Int = 0) {
        let continuation = lock.withLock { streams[run] }
        continuation.yield(TeamsSpeakerObservation(began: HostTime(seconds: time), ended: HostTime(seconds: time),
                                                   sequence: sequence, sourceID: "call", speaker: name.flatMap(TeamsSpeakerName.init)))
    }
}

@MainActor
final class TeamsSpeakerRecordingTests: XCTestCase {
    private var logged: [String] = []

    private func makeRecording(_ source: RecordingSpeakerSource) -> TeamsSpeakerRecording {
        TeamsSpeakerRecording(observer: source, log: { [unowned self] in logged.append($0.text) })
    }

    func testLogsTheFirstAcceptedScanAndAChangeOfResultAcrossAPause() async {
        let source = RecordingSpeakerSource()
        let recording = makeRecording(source)
        recording.resume(at: HostTime(seconds: 100))
        source.yield(99.5, sequence: 1, name: nil)
        source.yield(100, sequence: 2)
        await waitUntil { self.logged.count == 1 }
        recording.pause()
        recording.resume(at: HostTime(seconds: 110))
        source.yield(110, sequence: 1, name: nil, run: 1)
        await waitUntil { self.logged.count == 2 }

        XCTAssertEqual(logged, ["Teams scan result: named (first scan).",
                                "Teams scan result: named → noHighlightedTile."])
    }

    func testFinishLogsTheStopLineOnceAndPauseLogsNone() async {
        let source = RecordingSpeakerSource()
        let recording = makeRecording(source)
        recording.resume(at: HostTime(seconds: 100))
        source.yield(100, sequence: 1)
        await waitUntil { self.logged.count == 1 }
        recording.pause()
        XCTAssertEqual(logged.count, 1)

        _ = recording.finish(clock: RecordingClock(origin: HostTime(seconds: 100)), endingAt: HostTime(seconds: 101))

        XCTAssertEqual(logged.dropFirst(), ["Teams speaker names at Stop. Scans: 1, named: 1. Reasons: none. "
                                            + "Scan time: median 0.000 s, longest 0.000 s. Largest node count: 5."])
    }

    func testStartLineSaysWhetherTheFeatureIsOnAndAccessibilityIsGranted() {
        XCTAssertEqual(TeamsSpeakerRecording.startLine(enabled: false, accessibilityGranted: true).text,
                       "Teams speaker names: off.")
        XCTAssertEqual(TeamsSpeakerRecording.startLine(enabled: true, accessibilityGranted: true).text,
                       "Teams speaker names: on. Accessibility: granted.")
        XCTAssertEqual(TeamsSpeakerRecording.startLine(enabled: true, accessibilityGranted: false).text,
                       "Teams speaker names: on. Accessibility: not granted.")
    }

    func testFinishFreezesTheRecordingAndCancelsTheSource() async {
        let source = RecordingSpeakerSource()
        let recording = TeamsSpeakerRecording(observer: source)
        recording.resume(at: HostTime(seconds: 100))
        await waitUntil { source.starts == 1 }
        XCTAssertEqual(source.starts, 1)
        guard source.starts == 1 else { return }
        source.yield(100, sequence: 1)
        source.yield(100.5, sequence: 2)
        source.yield(101, sequence: 3)
        for _ in 0..<20 { await Task.yield() }

        let evidence = recording.finish(clock: RecordingClock(origin: HostTime(seconds: 100)), endingAt: HostTime(seconds: 101))

        XCTAssertEqual(evidence.name(for: TranscriptSegment(start: 0, end: 1, text: "Hello"))?.value, "Alice")
        await waitUntil { source.terminations == 1 }
        XCTAssertEqual(source.terminations, 1)
    }

    func testResumeRejectsBufferedSamplesBeforeItsLowerBoundAndLeavesThePauseGapEmpty() async {
        let source = RecordingSpeakerSource()
        let recording = TeamsSpeakerRecording(observer: source)
        recording.resume(at: HostTime(seconds: 100))
        await waitUntil { source.starts == 1 }
        XCTAssertEqual(source.starts, 1)
        guard source.starts == 1 else { return }
        source.yield(100, sequence: 1)
        source.yield(100.5, sequence: 2)
        for _ in 0..<20 { await Task.yield() }
        source.yield(110.2, sequence: 3, name: "Alice")
        recording.pause()
        recording.resume(at: HostTime(seconds: 110))
        await waitUntil { source.starts == 2 }
        guard source.starts == 2 else { return }
        source.yield(109.8, sequence: 1, name: "Bob", run: 1)
        source.yield(110.2, sequence: 2, name: "Bob", run: 1)
        source.yield(110.7, sequence: 3, name: "Bob", run: 1)
        for _ in 0..<20 { await Task.yield() }
        var clock = RecordingClock(origin: HostTime(seconds: 100))
        clock.pause(at: HostTime(seconds: 101))
        clock.resume(at: HostTime(seconds: 110))
        let evidence = recording.finish(clock: clock, endingAt: HostTime(seconds: 111))
        XCTAssertNil(evidence.name(for: TranscriptSegment(start: 3.9, end: 4.2, text: "Late")))
        XCTAssertEqual(evidence.name(for: TranscriptSegment(start: 4.2, end: 4.7, text: "Hello"))?.value, "Bob")
    }

    func testDeinitCancelsAnUnfinishedSource() async {
        let source = RecordingSpeakerSource()
        var recording: TeamsSpeakerRecording? = TeamsSpeakerRecording(observer: source)
        recording?.resume(at: HostTime(seconds: 100))
        await waitUntil { source.starts == 1 }
        recording = nil
        await waitUntil { source.terminations == 1 }
        XCTAssertEqual(source.terminations, 1)
    }

    func testReachingTheHistoryCapCancelsCollectionAndNeverStartsAnotherRun() async {
        let source = RecordingSpeakerSource()
        let recording = makeRecording(source)
        recording.resume(at: HostTime(seconds: 100))
        for index in 0..<36_001 { source.yield(100 + Double(index) * 0.3, sequence: index) }
        await waitUntil { source.terminations == 1 }
        XCTAssertEqual(source.terminations, 1)
        recording.resume(at: HostTime(seconds: 11_000))
        XCTAssertEqual(source.starts, 1)
        let evidence = recording.finish(clock: RecordingClock(origin: HostTime(seconds: 100)), endingAt: HostTime(seconds: 11_000))
        XCTAssertEqual(evidence.name(for: TranscriptSegment(start: 0, end: 0.6, text: "Hello"))?.value, "Alice")
        recording.resume(at: HostTime(seconds: 12_000))
        XCTAssertEqual(source.starts, 1)
        XCTAssertEqual(logged.filter { $0 == "Teams speaker names: collection stopped at the cap of 36000 scans." }.count, 1)
    }
}
