import AVFAudio
import XCTest
@testable import KuKa

@MainActor
final class MeetingRecorderTests: XCTestCase {
    func testShutdownDuringCaptureStopsLateHandleAndPreservesANewerSession() async throws {
        let delayed = DelayedCapture()
        let recorder = MeetingRecorder(
            permissions: PermissionsManager(isAccessibilityTrusted: { true }, hasScreenCaptureAccess: { true },
                                            microphoneAccess: { .granted }),
            root: { self.root }, capture: delayed, liveTranscriber: FakeLiveTranscriber(), notifier: FakeNotifier())
        let first = Task { await recorder.startRecording(title: "First") }
        await waitUntil { delayed.release != nil }
        let firstID = recorder.activeSessionID
        XCTAssertNotNil(firstID)
        XCTAssertEqual(recorder.displayTitle, "First")
        XCTAssertEqual(delayed.titles, ["First"])
        recorder.shutDown()
        let secondID = await recorder.startRecording(title: "Second")
        XCTAssertNotNil(secondID)
        XCTAssertNotEqual(firstID, secondID)
        delayed.release?.resume()
        let staleResult = await first.value
        XCTAssertNil(staleResult)
        XCTAssertEqual(recorder.phase, .recording)
        XCTAssertEqual(recorder.activeSessionID, secondID)
        XCTAssertEqual(delayed.recordings[0].stopCount, 1)
        XCTAssertEqual(delayed.recordings[1].stopCount, 0)
        XCTAssertEqual(MeetingFolder.all(in: root).count, 2)
        recorder.shutDown()
    }

    func testShutdownDuringPermissionPromptCannotStartCaptureAfterTheAnswer() async {
        microphone = .notDetermined
        var prompt: CheckedContinuation<Bool, Never>?
        answerMicrophonePrompt = { await withCheckedContinuation { prompt = $0 } }
        let start = Task { await sut.toggleRecording() }
        await waitUntil { prompt != nil }
        sut.shutDown()
        microphone = .granted
        prompt?.resume(returning: true)
        await start.value
        XCTAssertEqual(sut.phase, .idle)
        XCTAssertTrue(capture.recordings.isEmpty)
    }

    func testExplicitStartDoesNotStopABusyOrPausedSessionAndStaleStopDoesNothing() async throws {
        let result = await sut.startRecording(title: "Planning")
        let first = try XCTUnwrap(result)
        XCTAssertEqual(sut.activeSessionID, first)
        XCTAssertEqual(sut.displayTitle, "Planning")
        let busy = await sut.startRecording(title: "Other")
        XCTAssertNil(busy)
        hostTime = hostTime + 10
        sut.pause()
        XCTAssertEqual(sut.activeSessionID, first)
        let paused = await sut.startRecording()
        XCTAssertNil(paused)
        sut.stopRecording(ifSession: UUID())
        XCTAssertEqual(sut.phase, .paused)
        sut.stopRecording(ifSession: first)
        XCTAssertEqual(sut.phase, .idle)
        let next = await sut.startRecording()
        XCTAssertNotNil(next)
        XCTAssertNotEqual(next, first)
        sut.stopRecording(ifSession: first)
        XCTAssertEqual(sut.phase, .recording)
    }

    private var root: URL!
    private var microphone = MicrophoneAccess.granted
    private var answerMicrophonePrompt: () async -> Bool = { false }
    private var capture: FakeMeetingAudioCapture!
    private var meetingLocale = Locale(identifier: "en-US")
    private var liveTranscriber: FakeLiveTranscriber!
    private var hostTime = HostTime(seconds: 1_000)
    private var alerts: [String] = []
    private var permissionWindows = 0
    private var stateChanges = 0
    private var controlsChanges = 0
    /// Each saved notice's delayed close, in order. A test runs one to end its delay.
    private var noticeCloses: [@MainActor () -> Void] = []
    private var sut: MeetingRecorder!

    override func setUp() async throws {
        root = try makeTemporaryDirectory().appendingPathComponent("Meetings", isDirectory: true)
        capture = FakeMeetingAudioCapture()
        liveTranscriber = FakeLiveTranscriber()
        sut = MeetingRecorder(
            permissions: PermissionsManager(
                isAccessibilityTrusted: { true },
                hasScreenCaptureAccess: { true },
                microphoneAccess: { [unowned self] in microphone },
                requestMicrophoneAccess: { [unowned self] in await answerMicrophonePrompt() }),
            root: { [unowned self] in root },
            locale: { [unowned self] in meetingLocale },
            capture: capture,
            liveTranscriber: liveTranscriber,
            notifier: FakeNotifier(),
            alertStartFailure: { [unowned self] reason, offersPermissions in
                alerts.append(reason)
                return offersPermissions
            },
            now: { localDate(2026, 10, 23, 14, 2) },
            hostNow: { [unowned self] in hostTime },
            closeSavedNoticeLater: { [unowned self] in noticeCloses.append($0) })
        sut.onShowPermissions = { [unowned self] in permissionWindows += 1 }
        sut.onChange = { [unowned self] in stateChanges += 1 }
        sut.onControlsChange = { [unowned self] in controlsChanges += 1 }
    }

    override func tearDown() async throws {
        sut.shutDown()
    }

    private func runMenuLoop(for duration: TimeInterval) {
        let until = Date().addingTimeInterval(duration)
        while Date() < until {
            RunLoop.current.run(mode: .eventTracking, before: until)
        }
    }

    func testTheControlsShowStartingThenTheRecordedTimeAndNothingWhileIdle() async {
        XCTAssertNil(sut.controls)
        microphone = .notDetermined
        var prompt: CheckedContinuation<Bool, Never>?
        answerMicrophonePrompt = { await withCheckedContinuation { prompt = $0 } }
        let start = Task { await sut.toggleRecording() }
        await waitUntil { prompt != nil }

        XCTAssertEqual(sut.controls, MeetingControls(status: .starting, recordedTime: nil, preview: nil))
        sut.dismissControls()
        XCTAssertEqual(sut.controls?.status, .starting, "Starting cannot be hidden")

        microphone = .granted
        prompt?.resume(returning: true)
        await start.value
        hostTime = hostTime + 245
        XCTAssertEqual(sut.controls, MeetingControls(status: .recording, recordedTime: 245, preview: nil))

        sut.pause()
        hostTime = hostTime + 30
        XCTAssertEqual(sut.controls, MeetingControls(status: .paused, recordedTime: 245, preview: nil))
    }

    func testEveryMeetingStartsWithTheControlsShownAndTheTranscriptClosed() async {
        await sut.toggleRecording()
        XCTAssertEqual(sut.controls?.isTranscriptOpen, false)
        sut.setTranscriptOpen(true)
        XCTAssertEqual(sut.controls?.isTranscriptOpen, true)
        sut.dismissControls()

        await sut.toggleRecording()
        await sut.toggleRecording()

        XCTAssertEqual(sut.phase, .recording)
        XCTAssertEqual(sut.controls, MeetingControls(status: .recording, recordedTime: 0, preview: nil))
        XCTAssertEqual(sut.controls?.isTranscriptOpen, false)
    }

    func testStopShowsTheSavedNoticeUntilItsDelayEnds() async {
        await sut.toggleRecording()
        sut.setTranscriptOpen(true)

        sut.stopRecording()

        XCTAssertEqual(sut.controls, MeetingControls(status: .saved, recordedTime: nil, preview: nil))
        XCTAssertEqual(noticeCloses.count, 1)
        noticeCloses[0]()
        XCTAssertNil(sut.controls)
    }

    func testADelayFromAnEarlierMeetingDoesNotCloseALaterNotice() async {
        await sut.toggleRecording()
        await sut.toggleRecording()
        await sut.toggleRecording()
        XCTAssertEqual(sut.controls, MeetingControls(status: .recording, recordedTime: 0, preview: nil),
                       "Start replaces the notice")
        await sut.toggleRecording()
        XCTAssertEqual(noticeCloses.count, 2)

        noticeCloses[0]()
        XCTAssertEqual(sut.controls?.status, .saved)

        noticeCloses[1]()
        XCTAssertNil(sut.controls)
    }

    func testAnInterruptionLeavesItsReasonOnScreenUntilTheUserClosesIt() async {
        await sut.toggleRecording()
        await sut.toggleRecording()
        await sut.toggleRecording()

        capture.interrupt(reason: "The display was disconnected.")

        let stopped = MeetingControls(status: .interrupted(reason: "The display was disconnected."),
                                      recordedTime: nil, preview: nil)
        XCTAssertEqual(sut.controls, stopped)
        XCTAssertEqual(noticeCloses.count, 1, "only the first meeting's saved notice has a delay")
        noticeCloses[0]()
        XCTAssertEqual(sut.controls, stopped)

        sut.dismissControls()
        XCTAssertNil(sut.controls)
    }

    func testThePanelHearsOfStartPauseResumeADrawerChangeStopAndTheNoticeClosing() async {
        await sut.toggleRecording()
        XCTAssertEqual(controlsChanges, 2, "starting, then recording")

        hostTime = HostTime(seconds: 1_010)
        sut.pause()
        XCTAssertEqual(controlsChanges, 3)
        hostTime = HostTime(seconds: 1_020)
        sut.resume()
        XCTAssertEqual(controlsChanges, 4)
        sut.setTranscriptOpen(true)
        XCTAssertEqual(controlsChanges, 5)
        sut.stopRecording()
        XCTAssertEqual(controlsChanges, 6)
        noticeCloses[0]()
        XCTAssertEqual(controlsChanges, 7)
    }

    func testThePanelTicksEverySecondOnlyWhileRecordingAlsoWhileAMenuIsOpen() async {
        await sut.toggleRecording()
        var before = controlsChanges
        runMenuLoop(for: 1.15)
        XCTAssertEqual(controlsChanges, before + 1)

        hostTime = HostTime(seconds: 1_010)
        sut.pause()
        before = controlsChanges
        runMenuLoop(for: 1.15)
        XCTAssertEqual(controlsChanges, before, "the time stands still while paused")

        hostTime = HostTime(seconds: 1_020)
        sut.resume()
        sut.stopRecording()
        before = controlsChanges
        runMenuLoop(for: 1.15)
        XCTAssertEqual(controlsChanges, before, "no tick after the meeting")
    }

    func testStartBeginsOneLiveTranscriptInTheMeetingLocaleOfTheAudioTheRecordingWrites() async throws {
        meetingLocale = Locale(identifier: "fi-FI")

        await sut.toggleRecording()
        hostTime = HostTime(seconds: 1_010)
        sut.pause()
        hostTime = HostTime(seconds: 1_020)
        sut.resume()

        XCTAssertEqual(liveTranscriber.starts.map(\.locale), ["fi-FI"])
        let audio = try XCTUnwrap(liveTranscriber.starts.first?.audio)
        XCTAssertEqual(Set(audio.keys), Set(MeetingTrack.allCases))
        let handle = try XCTUnwrap(capture.recordings.last)
        for (track, position) in [(MeetingTrack.microphone, 4.0), (.system, 7.0)] {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: AudioTrackWriter.fileFormat, frameCapacity: 160))
            handle.feeds[track]?.offer(WrittenAudio(buffer: buffer, filePosition: position, rms: 0.5))
            var written = try XCTUnwrap(audio[track]).makeAsyncIterator()
            let first = await written.next()
            XCTAssertEqual(first?.filePosition, position)
        }
    }

    func testLiveTextReachesThePreview() async {
        await sut.toggleRecording()
        sut.setTranscriptOpen(true)
        XCTAssertEqual(sut.controls?.preview, LivePreview(status: .preparing, rows: [], behind: nil))

        liveTranscriber.send(.started)
        liveTranscriber.send(.result(LiveResult(track: .system, start: 1, end: 2, text: "Let's ship on Friday",
                                                isFinal: true, finalizedThrough: 2)))
        await waitUntil { sut.controls?.preview?.rows.isEmpty == false }

        XCTAssertEqual(sut.controls?.preview, LivePreview(
            status: .live, rows: [LiveRow(at: 1, content: .speech(.them, text: "Let's ship on Friday", isFinal: true))],
            behind: nil))
    }

    func testThePreviewIsBuiltOnlyWhileTheTranscriptIsOpen() async {
        await sut.toggleRecording()
        let changes = controlsChanges
        liveTranscriber.send(.started)
        liveTranscriber.send(.result(LiveResult(track: .system, start: 1, end: 2, text: "Let's ship on Friday",
                                                isFinal: true, finalizedThrough: 2)))
        await waitUntil { controlsChanges == changes + 2 }

        XCTAssertNil(sut.controls?.preview)

        sut.setTranscriptOpen(true)
        XCTAssertEqual(sut.controls?.preview?.rows,
                       [LiveRow(at: 1, content: .speech(.them, text: "Let's ship on Friday", isFinal: true))])
    }

    func testALiveTranscriptThatIsUnavailableOrFailsLeavesTheRecordingAlone() async throws {
        await sut.toggleRecording()
        sut.setTranscriptOpen(true)
        liveTranscriber.send(.unavailable("Live transcript is not available for Finnish on this Mac."))
        await waitUntil { sut.controls?.preview?.status != .preparing }

        XCTAssertEqual(sut.controls?.preview?.status, .unavailable("Live transcript is not available for Finnish on this Mac."))
        XCTAssertEqual(sut.phase, .recording)
        XCTAssertEqual(capture.recordings.last?.stopCount, 0)

        await sut.toggleRecording()
        await sut.toggleRecording()
        sut.setTranscriptOpen(true)
        liveTranscriber.send(.started)
        liveTranscriber.send(.failed("The speech model stopped."))
        await waitUntil { sut.controls?.preview?.status == .failed("The speech model stopped.") }

        XCTAssertEqual(sut.controls?.preview?.status, .failed("The speech model stopped."))
        XCTAssertEqual(sut.phase, .recording)
        XCTAssertEqual(capture.recordings.last?.stopCount, 0)
    }

    func testStopAnInterruptionAndQuitEachEndTheLiveTranscript() async {
        await sut.toggleRecording()
        sut.stopRecording()
        await waitUntil { liveTranscriber.terminations == 1 }
        XCTAssertEqual(liveTranscriber.terminations, 1)

        let changesAfterStop = controlsChanges
        liveTranscriber.send(.result(LiveResult(track: .system, start: 1, end: 2, text: "Too late",
                                                isFinal: true, finalizedThrough: 2)))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(controlsChanges, changesAfterStop)
        XCTAssertEqual(sut.controls, MeetingControls(status: .saved, recordedTime: nil, preview: nil))

        await sut.toggleRecording()
        capture.interrupt(reason: "The display was disconnected.")
        await waitUntil { liveTranscriber.terminations == 2 }
        XCTAssertEqual(liveTranscriber.terminations, 2)

        await sut.toggleRecording()
        sut.shutDown()
        await waitUntil { liveTranscriber.terminations == 3 }
        XCTAssertEqual(liveTranscriber.terminations, 3)
    }

    func testALiveUpdateFromTheFirstMeetingDoesNotShowInTheSecond() async {
        await sut.toggleRecording()
        sut.setTranscriptOpen(true)
        liveTranscriber.send(.started)
        await waitUntil { sut.controls?.preview?.status == .live }
        liveTranscriber.send(.result(LiveResult(track: .system, start: 1, end: 2, text: "From the first meeting",
                                                isFinal: true, finalizedThrough: 2)))

        sut.stopRecording()
        await sut.toggleRecording()
        sut.setTranscriptOpen(true)
        liveTranscriber.send(.started)
        await waitUntil { sut.controls?.preview?.status == .live }

        XCTAssertEqual(sut.controls?.preview?.rows, [])
    }

    func testPauseShowsTheUnfinishedLiveTextAsFinal() async {
        await sut.toggleRecording()
        sut.setTranscriptOpen(true)
        liveTranscriber.send(.result(LiveResult(track: .system, start: 1, end: 2, text: "So the plan",
                                                isFinal: false, finalizedThrough: 0)))
        await waitUntil { sut.controls?.preview?.rows.isEmpty == false }
        XCTAssertEqual(sut.controls?.preview?.rows, [LiveRow(at: 1, content: .speech(.them, text: "So the plan", isFinal: false))])

        hostTime = HostTime(seconds: 1_010)
        sut.pause()

        XCTAssertEqual(sut.controls?.preview?.rows, [LiveRow(at: 1, content: .speech(.them, text: "So the plan", isFinal: true)),
                                                     LiveRow(at: 10, content: .pause(duration: nil))])
    }

    func testOnlyRecordingAndPausedAreCapturingAndEachSaysWhatTheStatusItemShows() {
        let phases: [RecorderPhase] = [.idle, .starting, .recording, .paused]

        XCTAssertEqual(phases.map(\.isCapturing), [false, false, true, true])
        XCTAssertEqual(phases.map(\.statusDescription), [nil, nil, "recording meeting", "recording paused"])
        XCTAssertEqual(phases.map(\.recordingMark), [nil, nil, .recording, .paused])
    }

    func testTheCaptureStartsWithAClockFromTheHostTimeJustBeforeIt() async {
        microphone = .notDetermined
        answerMicrophonePrompt = { [unowned self] in
            hostTime = HostTime(seconds: 1_007)
            microphone = .granted
            return true
        }

        await sut.toggleRecording()

        XCTAssertEqual(capture.clocks, [RecordingClock(origin: HostTime(seconds: 1_007))])
    }

    /// The clock the recorder makes at host time 1 000, with these boundaries applied.
    private func clock(pausedAt pause: TimeInterval, resumedAt resume: TimeInterval? = nil) -> RecordingClock {
        var clock = RecordingClock(origin: HostTime(seconds: 1_000))
        clock.pause(at: HostTime(seconds: pause))
        if let resume { clock.resume(at: HostTime(seconds: resume)) }
        return clock
    }

    func testPauseHandsTheRecordingAClockPausedAtTheHostTimeOfTheClick() async throws {
        await sut.toggleRecording()
        let handle = try XCTUnwrap(capture.recordings.last)
        let changesBeforePause = stateChanges
        hostTime = HostTime(seconds: 1_010)

        sut.pause()

        XCTAssertEqual(handle.appliedClocks, [clock(pausedAt: 1_010)])
        XCTAssertEqual(sut.phase, .paused)
        XCTAssertEqual(stateChanges, changesBeforePause + 1)
    }

    func testPauseKeepsTheCaptureAndTheFolderLock() async throws {
        await sut.toggleRecording()
        hostTime = HostTime(seconds: 1_010)

        sut.pause()

        XCTAssertEqual(sut.phase, .paused)
        XCTAssertEqual(capture.recordings.count, 1)
        XCTAssertEqual(capture.recordings.first?.stopCount, 0)
        let meeting = try XCTUnwrap(MeetingFolder.all(in: root).first?.0)
        XCTAssertThrowsError(try meeting.lock()) { error in
            XCTAssertEqual(error as? MeetingLockError, .held(meeting))
        }
    }

    func testResumeHandsTheRecordingTheResumedClock() async throws {
        await sut.toggleRecording()
        let handle = try XCTUnwrap(capture.recordings.last)
        hostTime = HostTime(seconds: 1_010)
        sut.pause()
        let changesBeforeResume = stateChanges
        hostTime = HostTime(seconds: 1_040)

        sut.resume()

        XCTAssertEqual(handle.appliedClocks, [clock(pausedAt: 1_010), clock(pausedAt: 1_010, resumedAt: 1_040)])
        XCTAssertEqual(sut.phase, .recording)
        XCTAssertEqual(stateChanges, changesBeforeResume + 1)
    }

    func testTogglePausePausesWhileRecordingAndResumesWhilePaused() async throws {
        await sut.toggleRecording()
        let handle = try XCTUnwrap(capture.recordings.last)
        hostTime = HostTime(seconds: 1_010)

        sut.togglePause()
        XCTAssertEqual(sut.phase, .paused)

        hostTime = HostTime(seconds: 1_040)
        sut.togglePause()
        XCTAssertEqual(sut.phase, .recording)
        XCTAssertEqual(handle.appliedClocks, [clock(pausedAt: 1_010), clock(pausedAt: 1_010, resumedAt: 1_040)])
    }

    func testPauseWhilePausedAndResumeWhileRecordingChangeNothingAndTellNoOne() async throws {
        await sut.toggleRecording()
        let handle = try XCTUnwrap(capture.recordings.last)
        let controlsChangesWhileRecording = controlsChanges
        hostTime = HostTime(seconds: 1_010)
        sut.resume()
        XCTAssertEqual(handle.appliedClocks, [])
        XCTAssertEqual(sut.phase, .recording)
        XCTAssertEqual(controlsChanges, controlsChangesWhileRecording)

        sut.pause()
        let changesAfterPause = stateChanges
        let controlsChangesAfterPause = controlsChanges
        hostTime = HostTime(seconds: 1_020)
        sut.pause()

        XCTAssertEqual(handle.appliedClocks, [clock(pausedAt: 1_010)])
        XCTAssertEqual(sut.phase, .paused)
        XCTAssertEqual(stateChanges, changesAfterPause)
        XCTAssertEqual(controlsChanges, controlsChangesAfterPause)
    }

    func testRecordingCommandsWhileStartingDoNothing() async throws {
        microphone = .notDetermined
        var prompt: CheckedContinuation<Bool, Never>?
        answerMicrophonePrompt = { await withCheckedContinuation { prompt = $0 } }
        let firstClick = Task { await sut.toggleRecording() }
        await waitUntil { prompt != nil }

        sut.pause()
        sut.resume()
        sut.togglePause()
        sut.stopRecording()
        XCTAssertEqual(sut.phase, .starting)

        microphone = .granted
        prompt?.resume(returning: true)
        await firstClick.value

        let handle = try XCTUnwrap(capture.recordings.first)
        XCTAssertEqual(capture.recordings.count, 1)
        XCTAssertEqual(sut.phase, .recording)
        XCTAssertEqual(handle.appliedClocks, [])
        XCTAssertEqual(handle.stopCount, 0)
    }

    func testADeniedMicrophoneSaysWhyAndOffersThePermissionsWindow() async {
        microphone = .denied

        await sut.toggleRecording()

        XCTAssertEqual(alerts, ["Ku-Ka needs Microphone permission to record your side of the call."])
        XCTAssertEqual(permissionWindows, 1)
        XCTAssertEqual(sut.phase, .idle)
    }

    func testAllowingTheMicrophonePromptStartsTheRecording() async {
        microphone = .notDetermined
        answerMicrophonePrompt = { [unowned self] in microphone = .granted; return true }

        await sut.toggleRecording()

        XCTAssertEqual(sut.phase, .recording)
        XCTAssertEqual(alerts, [])
        XCTAssertEqual(permissionWindows, 0)
    }

    func testRefusingTheMicrophonePromptRecordsNothingAndSaysWhy() async {
        microphone = .notDetermined
        var prompts = 0
        answerMicrophonePrompt = { [unowned self] in prompts += 1; microphone = .denied; return false }

        await sut.toggleRecording()

        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(sut.phase, .idle)
        XCTAssertEqual(capture.recordings.count, 0)
        XCTAssertEqual(alerts, ["Ku-Ka needs Microphone permission to record your side of the call."])
    }
}

private final class DelayedCapture: FakeMeetingAudioCapture {
    var release: CheckedContinuation<Void, Never>?
    var titles: [String] = []

    @MainActor
    override func start(into meeting: MeetingFolder, clock: RecordingClock,
                        onInterrupted: @escaping @MainActor (String) -> Void) async throws -> ActiveRecording {
        titles.append(MeetingFolder(url: meeting.url).title)
        let handle = try await super.start(into: meeting, clock: clock, onInterrupted: onInterrupted)
        if recordings.count == 1 { await withCheckedContinuation { release = $0 } }
        return handle
    }
}
