import XCTest
@testable import KuKa

@MainActor
final class TeamsSpeakerLifecycleTests: XCTestCase {
    private var root: URL!
    private var time = HostTime(seconds: 100)
    private var enabled = true
    private var reads = 0
    private var alerts: [String] = []
    private var source: RecordingSpeakerSource!
    private var capture: FakeMeetingAudioCapture!
    private var recorder: MeetingRecorder!

    override func setUp() async throws {
        root = try makeTemporaryDirectory()
        source = RecordingSpeakerSource()
        capture = FakeMeetingAudioCapture()
        recorder = makeRecorder(capture: capture)
    }

    override func tearDown() async throws { recorder?.shutDown() }

    private func makeRecorder(capture: MeetingAudioCapturing) -> MeetingRecorder {
        MeetingRecorder(permissions: PermissionsManager(isAccessibilityTrusted: { false }, hasScreenCaptureAccess: { true },
                                                        microphoneAccess: { .granted }, requestMicrophoneAccess: { true }),
                        root: { [unowned self] in root }, capture: capture, liveTranscriber: FakeLiveTranscriber(),
                        teamsSpeakerNamesEnabled: { [unowned self] in reads += 1; return enabled },
                        teamsSpeakerObserver: source, notifier: FakeNotifier(), alertStartFailure: { [unowned self] reason, _ in
                            alerts.append(reason)
                            return false
                        },
                        hostNow: { [unowned self] in time }, closeSavedNoticeLater: { _ in })
    }

    private func samples(run: Int = 0, at start: Double = 100, name: String = "Alice") async {
        await waitUntil { source.starts > run }
        XCTAssertGreaterThan(source.starts, run)
        guard source.starts > run else { return }
        for index in 0...6 { source.yield(start + Double(index) * 0.5, sequence: index, name: name, run: run) }
        for _ in 0..<20 { await Task.yield() }
    }

    func testStopFreezesNamesBeforeCallbackAndReadsOptInOnce() async {
        var ended: RecordedMeeting?
        recorder.onEnded = { ended = $0 }
        await recorder.toggleRecording()
        enabled = false
        await samples()
        time = HostTime(seconds: 103)
        recorder.stopRecording()
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(ended?.speakers.name(for: TranscriptSegment(start: 1, end: 3, text: "Hello"))?.value, "Alice")
        XCTAssertEqual(recorder.phase, .idle)
        await waitUntil { source.terminations == 1 }
        XCTAssertEqual(source.terminations, 1)
    }

    func testDisabledRecordingNeverStartsObservationAndKeepsAudioWorkingWithoutAXPermission() async {
        enabled = false
        await recorder.toggleRecording()
        XCTAssertEqual(recorder.phase, .recording)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(source.starts, 0)
    }

    func testInterruptionHandsOffEvidenceAndNextMeetingHasOnlyItsOwnNames() async {
        var ended: [RecordedMeeting] = []
        recorder.onEnded = { ended.append($0) }
        await recorder.toggleRecording()
        await samples()
        time = HostTime(seconds: 103)
        capture.interrupt(reason: "Lost stream")
        time = HostTime(seconds: 200)
        await recorder.toggleRecording()
        await samples(run: 1, at: 200, name: "Bob")
        time = HostTime(seconds: 203)
        recorder.stopRecording()
        XCTAssertEqual(ended.count, 2)
        XCTAssertEqual(ended.first?.speakers.name(for: TranscriptSegment(start: 1, end: 3, text: "Hello"))?.value, "Alice")
        XCTAssertEqual(ended.last?.speakers.name(for: TranscriptSegment(start: 1, end: 3, text: "Hello"))?.value, "Bob")
    }

    func testShutdownCancelsSourceWithoutHandingOffEvidence() async {
        var ended = 0
        var controlsChanges = 0
        recorder.onEnded = { _ in ended += 1 }
        recorder.onControlsChange = { controlsChanges += 1 }
        await recorder.toggleRecording()
        await samples()
        let before = controlsChanges
        recorder.shutDown()
        XCTAssertEqual(controlsChanges, before + 1)
        recorder.resume()
        await waitUntil { source.terminations == 1 }
        XCTAssertEqual(source.terminations, 1)
        XCTAssertEqual(source.starts, 1)
        XCTAssertEqual(ended, 0)
    }

    func testFailedAndInterruptedStartupNeverStartObservation() async {
        capture.startError = TestError(errorDescription: "Unavailable")
        await recorder.toggleRecording()
        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertEqual(source.starts, 0)
        capture.startError = nil
        capture.endsWhileStarting = "Interrupted"
        await recorder.toggleRecording()
        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertEqual(source.starts, 0)
    }

    func testUnavailableObservationsKeepThemWithoutChangingPanelState() async {
        var changes = 0
        var ended: RecordedMeeting?
        recorder.onControlsChange = { changes += 1 }
        recorder.onEnded = { ended = $0 }
        await recorder.toggleRecording()
        let before = changes
        for index in 0...6 { source.yield(100 + Double(index) * 0.5, sequence: index, name: nil) }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(changes, before)
        XCTAssertEqual(recorder.phase, .recording)
        time = HostTime(seconds: 103)
        recorder.stopRecording()
        XCTAssertNil(ended?.speakers.name(for: TranscriptSegment(start: 1, end: 3, text: "Hello")))
    }

    func testPauseCancelsTheRunAndResumeCannotBridgeTheFileGap() async {
        var ended: RecordedMeeting?
        recorder.onEnded = { ended = $0 }
        await recorder.toggleRecording()
        await samples()
        time = HostTime(seconds: 104)
        recorder.pause()
        await waitUntil { source.terminations == 1 }
        XCTAssertEqual(source.terminations, 1)
        time = HostTime(seconds: 110)
        recorder.resume()
        await samples(run: 1, at: 110, name: "Bob")
        time = HostTime(seconds: 113)
        recorder.stopRecording()
        let segment = { (start: Double, end: Double) in TranscriptSegment(start: start, end: end, text: "Hello") }
        XCTAssertEqual(ended?.speakers.name(for: segment(1, 3))?.value, "Alice")
        XCTAssertNil(ended?.speakers.name(for: segment(4, 7)))
        XCTAssertEqual(ended?.speakers.name(for: segment(8, 10))?.value, "Bob")
        recorder.resume()
        XCTAssertEqual(source.starts, 2)
    }

    func testRecorderDeinitCancelsItsObservationTask() async {
        await recorder.toggleRecording()
        await samples()
        recorder = nil
        await waitUntil { source.terminations == 1 }
        XCTAssertEqual(source.terminations, 1)
    }

    func testCancelledCaptureStartupStopsItsHandleAndNeverStartsObservation() async {
        let suspended = SuspendedSpeakerCapture()
        recorder = makeRecorder(capture: suspended)
        let start = Task { await recorder.toggleRecording() }
        await waitUntil { suspended.continuation != nil }
        start.cancel()
        suspended.completeFirst()
        await start.value
        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertEqual(source.starts, 0)
        XCTAssertEqual(suspended.first.stopCount, 1)
    }

    func testShutdownWhilePermissionWaitsDoesNotStartCaptureOrObservation() async {
        var answer: CheckedContinuation<Bool, Never>?
        recorder = MeetingRecorder(permissions: PermissionsManager(isAccessibilityTrusted: { false }, hasScreenCaptureAccess: { true },
                                                                   microphoneAccess: { .notDetermined }, requestMicrophoneAccess: {
            await withCheckedContinuation { answer = $0 }
        }), root: { [unowned self] in root }, capture: capture, liveTranscriber: FakeLiveTranscriber(),
                                   teamsSpeakerNamesEnabled: { true }, teamsSpeakerObserver: source,
                                   notifier: FakeNotifier(), alertStartFailure: { _, _ in false })
        let start = Task { await recorder.toggleRecording() }
        await waitUntil { answer != nil }
        recorder.shutDown()
        answer?.resume(returning: true)
        await start.value
        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertEqual(capture.recordings.count, 0)
        XCTAssertEqual(source.starts, 0)
    }

    func testShutdownWhileCaptureStartsCannotReplaceANewerRecording() async {
        let suspended = SuspendedSpeakerCapture()
        recorder = makeRecorder(capture: suspended)
        let first = Task { await recorder.toggleRecording() }
        await waitUntil { suspended.continuation != nil }
        recorder.shutDown()
        let second = Task { await recorder.toggleRecording() }
        await waitUntil { suspended.starts == 2 }
        suspended.completeLatest()
        await second.value
        suspended.completeFirst()
        await first.value
        XCTAssertEqual(recorder.phase, .recording)
        XCTAssertEqual(source.starts, 1)
        XCTAssertEqual(suspended.first.stopCount, 1)
    }

    func testObsoleteStartupFailureCannotResetANewerRecordingOrShowAnAlert() async {
        let suspended = SuspendedSpeakerCapture()
        recorder = makeRecorder(capture: suspended)
        let first = Task { await recorder.toggleRecording() }
        await waitUntil { suspended.continuation != nil }
        recorder.shutDown()
        let second = Task { await recorder.toggleRecording() }
        await waitUntil { suspended.starts == 2 }
        suspended.completeLatest()
        await second.value
        await samples()

        suspended.failFirst()
        await first.value

        XCTAssertEqual(recorder.phase, .recording)
        XCTAssertEqual(recorder.controls?.status, .recording)
        XCTAssertEqual(alerts, [])
        XCTAssertEqual(source.starts, 1)
        XCTAssertEqual(source.terminations, 0)
        recorder.stopRecording()
        await waitUntil { source.terminations == 1 }
        XCTAssertEqual(source.terminations, 1)
    }

    func testObsoleteCaptureThatReturnsWhileANewerStartWaitsCannotBecomeTheRecording() async {
        let suspended = SuspendedSpeakerCapture()
        recorder = makeRecorder(capture: suspended)
        let first = Task { await recorder.toggleRecording() }
        await waitUntil { suspended.continuation != nil }
        recorder.shutDown()
        let second = Task { await recorder.toggleRecording() }
        await waitUntil { suspended.starts == 2 }

        suspended.completeFirst()
        await first.value

        XCTAssertEqual(recorder.phase, .starting)
        XCTAssertEqual(suspended.first.stopCount, 1)
        XCTAssertEqual(source.starts, 0)
        suspended.completeLatest()
        await second.value
        await samples()
        XCTAssertEqual(recorder.phase, .recording)
        XCTAssertEqual(source.starts, 1)
        XCTAssertEqual(suspended.first.stopCount, 1)
    }

    func testObsoleteStartupFailureWhileANewerStartWaitsCannotResetItOrShowAnAlert() async {
        let suspended = SuspendedSpeakerCapture()
        recorder = makeRecorder(capture: suspended)
        let first = Task { await recorder.toggleRecording() }
        await waitUntil { suspended.continuation != nil }
        recorder.shutDown()
        let second = Task { await recorder.toggleRecording() }
        await waitUntil { suspended.starts == 2 }

        suspended.failFirst()
        await first.value

        XCTAssertEqual(recorder.phase, .starting)
        XCTAssertEqual(alerts, [])
        suspended.completeLatest()
        await second.value
        await samples()
        XCTAssertEqual(recorder.phase, .recording)
        XCTAssertEqual(recorder.controls?.status, .recording)
        XCTAssertEqual(alerts, [])
        XCTAssertEqual(source.starts, 1)
        recorder.stopRecording()
        await waitUntil { source.terminations == 1 }
        XCTAssertEqual(source.terminations, 1)
    }

    func testQueueDelayKeepsEachMeetingsEvidenceAndDeduplicatesByFolder() async throws {
        let runner = SpeakerQueueRunner()
        let controller = makeController(runner: runner)
        let menu = NSMenu()
        controller.buildMenuSection(into: menu)
        let blocker = try MeetingFolder.create(in: root, startingAt: localDate(2026, 10, 20, 9, 0))
        try blocker.write("**[00:00:01] Them:** Earlier meeting", to: .transcript)
        controller.resumeUnfinished()
        await waitUntil { runner.waiting }

        await recorder.toggleRecording()
        await samples()
        time = HostTime(seconds: 103)
        recorder.stopRecording()
        let first = try XCTUnwrap(MeetingFolder.all(in: root).map(\.0).first { $0 != blocker })
        recorder.onEnded?(RecordedMeeting(folder: first, speakers: .empty))
        XCTAssertTrue(menu.items.contains { !$0.isHidden && $0.title == "1 more meeting waiting" })

        time = HostTime(seconds: 200)
        await recorder.toggleRecording()
        await samples(run: 1, at: 200, name: "Bob")
        time = HostTime(seconds: 203)
        capture.interrupt(reason: "Disconnected")
        let second = try XCTUnwrap(MeetingFolder.all(in: root).map(\.0).first { $0 != blocker && $0 != first })
        XCTAssertTrue(menu.items.contains { !$0.isHidden && $0.title == "2 more meetings waiting" })
        runner.release()
        await controller.waitUntilIdle()

        XCTAssertTrue(try first.read(.transcript).contains("Alice (Teams):** Hello"))
        XCTAssertTrue(try second.read(.transcript).contains("Bob (Teams):** Hello"))
        XCTAssertEqual(runner.inputs.count, 3)
        controller.shutDown()
    }

    func testQuitDropsQueuedEvidenceAndRecoveryUsesThem() async throws {
        let runner = SpeakerQueueRunner()
        let controller = makeController(runner: runner)
        let blocker = try MeetingFolder.create(in: root, startingAt: localDate(2026, 10, 20, 9, 0))
        try blocker.write("**[00:00:01] Them:** Earlier meeting", to: .transcript)
        controller.resumeUnfinished()
        await waitUntil { runner.waiting }
        await recorder.toggleRecording()
        await samples()
        time = HostTime(seconds: 103)
        recorder.stopRecording()
        let queued = try XCTUnwrap(MeetingFolder.all(in: root).map(\.0).first { $0 != blocker })
        controller.shutDown()
        await controller.waitUntilIdle()
        runner.release()
        controller.resumeUnfinished()
        await controller.waitUntilIdle()

        XCTAssertTrue(try queued.read(.transcript).contains("Them:** Hello"))
        XCTAssertFalse(try queued.read(.transcript).contains("Alice (Teams)"))
        controller.shutDown()
    }

    private func makeController(runner: CommandRunning) -> MeetingNotesController {
        let transcriber = FakeTranscriber()
        transcriber.byFileName["them.caf"] = .success(TrackTranscript(
            segments: [TranscriptSegment(start: 1, end: 3, text: "Hello")], duration: 3))
        return MeetingNotesController(recorder: recorder, root: { [unowned self] in root },
                                      processor: makeMeetingProcessor(transcribers: [transcriber], runner: runner),
                                      wordsToCheck: { _ in 0 }, setRoot: { _ in }, notifier: FakeNotifier())
    }
}

private final class SpeakerQueueRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var blocked = true
    private var running = false
    private var prompts: [String] = []
    var waiting: Bool { lock.withLock { running } }
    var inputs: [String] { lock.withLock { prompts } }
    func release() { lock.withLock { blocked = false } }
    func run(executable: URL, arguments: [String], input: String?, searchPath: [String], timeout: Duration) async throws -> CommandResult {
        lock.withLock { running = true; prompts.append(input ?? "") }
        defer { lock.withLock { running = false } }
        while lock.withLock({ blocked }) { try await Task.sleep(for: .milliseconds(10)) }
        return CommandResult(termination: .exited(0), stdout: defaultNotes, stderr: "")
    }
}

@MainActor
private final class SuspendedSpeakerCapture: MeetingAudioCapturing {
    var continuation: CheckedContinuation<ActiveRecording, any Error>?
    private var latest: CheckedContinuation<ActiveRecording, any Error>?
    var starts = 0
    let first = FakeActiveRecording()
    func start(into meeting: MeetingFolder, clock: RecordingClock,
               onInterrupted: @escaping @MainActor (String) -> Void) async throws -> ActiveRecording {
        starts += 1
        return try await withCheckedThrowingContinuation {
            if starts == 1 { continuation = $0 } else { latest = $0 }
        }
    }
    func completeLatest() { latest?.resume(returning: FakeActiveRecording()); latest = nil }
    func completeFirst() { continuation?.resume(returning: first); continuation = nil }
    func failFirst() {
        continuation?.resume(throwing: TestError(errorDescription: "Obsolete startup failed"))
        continuation = nil
    }
}
