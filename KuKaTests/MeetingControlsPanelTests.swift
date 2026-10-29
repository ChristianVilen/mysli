import Carbon.HIToolbox
import XCTest
@testable import KuKa

/// A screen layout a test can change, for display changes.
private final class TestScreens: Screens {
    var all: [ScreenGeometry]
    var mainIndex: Int? = 0

    init(_ all: [ScreenGeometry]) { self.all = all }
}

@MainActor
final class MeetingControlsPanelTests: XCTestCase {
    private static let suite = "MeetingControlsPanelTests"
    private let primary = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                         visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
    private let right = ScreenGeometry(frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                                       visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055))
    /// The pill's height in every state without a note.
    private let pillHeight: CGFloat = 42

    private var root: URL!
    private var capture: FakeMeetingAudioCapture!
    private var liveTranscriber: FakeLiveTranscriber!
    private var microphone = MicrophoneAccess.granted
    private var answerMicrophonePrompt: () async -> Bool = { true }
    private var hostTime = HostTime(seconds: 1_000)
    private var defaults: UserDefaults!
    private var settings: Settings!
    private var screens: TestScreens!
    private var announcements: [(text: String, priority: NSAccessibilityPriorityLevel)] = []
    private var reduceMotion = true
    private var reduceTransparency = false
    /// The pointer the panel's drags read, in screen coordinates.
    private var mouseLocation = CGPoint.zero
    private var recorder: MeetingRecorder!
    private var sut: MeetingControlsPanel!

    override func setUp() async throws {
        root = try makeTemporaryDirectory().appendingPathComponent("Meetings", isDirectory: true)
        capture = FakeMeetingAudioCapture()
        liveTranscriber = FakeLiveTranscriber()
        defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        settings = Settings(defaults: defaults, loginItem: FakeLoginItem())
        screens = TestScreens([primary])
        recorder = MeetingRecorder(
            permissions: PermissionsManager(
                isAccessibilityTrusted: { true },
                hasScreenCaptureAccess: { true },
                microphoneAccess: { [unowned self] in microphone },
                requestMicrophoneAccess: { [unowned self] in await answerMicrophonePrompt() }),
            root: { [unowned self] in root },
            capture: capture,
            liveTranscriber: liveTranscriber,
            notifier: FakeNotifier(),
            alertStartFailure: { _, _ in false },
            hostNow: { [unowned self] in hostTime },
            closeSavedNoticeLater: { _ in })
        sut = MeetingControlsPanel(
            recorder: recorder, settings: settings, screens: screens,
            announce: { [unowned self] in announcements.append(($0, $1)) },
            displayOptions: { [unowned self] in (reduceMotion, reduceTransparency) },
            mouseLocation: { [unowned self] in mouseLocation })
        sut.bindRecorder()
    }

    override func tearDown() async throws {
        sut.close()
        recorder.shutDown()
        defaults.removePersistentDomain(forName: Self.suite)
    }

    private func startMeeting() async {
        await recorder.toggleRecording()
    }

    /// Sends one live result and waits until the recorder applied it. The host time is set
    /// half a second after the result, so it is never behind.
    private func deliver(_ track: MeetingTrack, _ text: String, from start: TimeInterval, to end: TimeInterval,
                         isFinal: Bool = true, at host: HostTime? = nil) async {
        hostTime = host ?? HostTime(seconds: 1_000 + end + 0.5)
        let before = recorder.controls?.preview
        liveTranscriber.send(.result(LiveResult(track: track, start: start, end: end, text: text, isFinal: isFinal,
                                                finalizedThrough: isFinal ? end : start)))
        await waitUntil { recorder.controls?.preview != before }
    }

    private func views(in view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { views(in: $0) }
    }

    private var allViews: [NSView] { views(in: sut.contentView!) }

    private func button(_ label: String) -> NSButton? {
        allViews.compactMap { $0 as? NSButton }
            .first { $0.accessibilityLabel() == label && !$0.isHiddenOrHasHiddenAncestor }
    }

    private var transcript: NSTableView {
        let table = allViews.compactMap { $0 as? NSTableView }.first { $0.accessibilityLabel() == "Live transcript draft" }
        XCTAssertNotNil(table, "the panel has a transcript")
        return table ?? NSTableView()
    }

    private var transcriptIsShown: Bool { !transcript.isHiddenOrHasHiddenAncestor }

    private var returnToLiveTitle: String? {
        allViews.compactMap { $0 as? NSButton }
            .first { $0.title.hasPrefix("Return to live") && !$0.isHiddenOrHasHiddenAncestor }?.title
    }

    private func rowTexts() -> [String] {
        (0..<transcript.numberOfRows).flatMap { row in
            views(in: transcript.view(atColumn: 0, row: row, makeIfNecessary: true)!)
                .compactMap { ($0 as? NSTextField)?.stringValue }
        }
    }

    private var lastRowIsVisible: Bool {
        transcript.rect(ofRow: transcript.numberOfRows - 1).intersects(transcript.visibleRect)
    }

    /// The pill's top-right corner while the drawer is closed.
    private var pillTopRight: CGPoint { CGPoint(x: sut.frame.maxX, y: sut.frame.maxY) }

    /// The event's window location only picks the view under the pointer.
    private func mouse(_ type: NSEvent.EventType, at screenPoint: CGPoint) {
        mouseLocation = screenPoint
        let event = NSEvent.mouseEvent(with: type, location: sut.convertPoint(fromScreen: screenPoint),
                                       modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: sut.windowNumber, context: nil, eventNumber: 0,
                                       clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
        sut.sendEvent(event)
    }

    private func key(_ keyCode: Int, _ characters: String) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                         windowNumber: sut.windowNumber, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(keyCode))!
    }

    func testThePanelIsOnScreenWhileRecordingAndOffScreenWhenIdleOrDismissed() async {
        XCTAssertFalse(sut.isVisible)

        await startMeeting()
        XCTAssertTrue(sut.isVisible)

        recorder.dismissControls()
        XCTAssertFalse(sut.isVisible)

        recorder.showControls()
        XCTAssertTrue(sut.isVisible)

        recorder.stopRecording()
        XCTAssertTrue(sut.isVisible, "the saved notice")

        recorder.dismissControls()
        XCTAssertFalse(sut.isVisible)
    }

    func testShowingItDoesNotMakeItTheKeyWindow() async {
        await startMeeting()

        XCTAssertTrue(sut.isVisible)
        XCTAssertFalse(sut.isKeyWindow)
    }

    func testItFloatsOnEverySpaceWithoutTakingTheKeyboardOrHidingWhenKuKaIsInactive() {
        XCTAssertEqual(sut.level, .floating)
        XCTAssertTrue(sut.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(sut.hidesOnDeactivate)
        XCTAssertTrue(sut.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(sut.canBecomeKey)
        XCTAssertEqual(sut.collectionBehavior, [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle])
    }

    func testItDoesNotCloseWhenItStopsBeingKey() async {
        await startMeeting()

        sut.resignKey()

        XCTAssertTrue(sut.isVisible)
    }

    func testThePauseButtonReadsResumeWithATextLabelWhilePaused() async throws {
        await startMeeting()
        let pause = try XCTUnwrap(button("Pause recording"))
        XCTAssertEqual(pause.title, "")

        hostTime = hostTime + 10
        recorder.pause()

        XCTAssertNil(button("Pause recording"))
        XCTAssertEqual(button("Resume recording")?.title, "Resume")
    }

    func testThePauseButtonAsksTheRecorderToToggleAndDecidesNothingFromWhatItShows() async throws {
        await startMeeting()
        let pause = try XCTUnwrap(button("Pause recording"))

        hostTime = hostTime + 10
        pause.performClick(nil)
        XCTAssertEqual(recorder.phase, .paused)

        // The menu resumes while the panel does not redraw, so the button still shows Resume.
        recorder.onControlsChange = nil
        hostTime = hostTime + 10
        recorder.resume()
        hostTime = hostTime + 10
        pause.performClick(nil)

        XCTAssertEqual(recorder.phase, .paused)
    }

    func testTheStopButtonStopsTheRecording() async throws {
        await startMeeting()

        try XCTUnwrap(button("Stop recording")).performClick(nil)

        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertEqual(capture.recordings.first?.stopCount, 1)
        XCTAssertEqual(recorder.controls?.status, .saved)
    }

    func testPauseAndStopAreOffWhileStarting() async throws {
        microphone = .notDetermined
        var prompt: CheckedContinuation<Bool, Never>?
        answerMicrophonePrompt = { await withCheckedContinuation { prompt = $0 } }
        let start = Task { await recorder.toggleRecording() }
        await waitUntil { prompt != nil }

        XCTAssertTrue(sut.isVisible)
        XCTAssertEqual(button("Pause recording")?.isEnabled, false)
        XCTAssertEqual(button("Stop recording")?.isEnabled, false)

        microphone = .granted
        prompt?.resume(returning: true)
        await start.value
        XCTAssertEqual(button("Pause recording")?.isEnabled, true)
    }

    func testTheNoticesHaveACloseButtonThatClosesThePanel() async throws {
        await startMeeting()
        XCTAssertNil(button("Close"))

        recorder.stopRecording()
        XCTAssertNil(button("Pause recording"))
        XCTAssertNil(button("Stop recording"))
        try XCTUnwrap(button("Close")).performClick(nil)

        XCTAssertFalse(sut.isVisible)
        XCTAssertNil(recorder.controls)
    }

    func testAnInterruptionStaysUntilClosed() async throws {
        await startMeeting()

        capture.interrupt(reason: "The microphone was disconnected.")

        XCTAssertTrue(sut.isVisible)
        XCTAssertNotNil(button("Close"))
    }

    func testTheTimeHasAVoiceOverLabel() async {
        await startMeeting()
        hostTime = hostTime + 245

        recorder.onControlsChange?()

        XCTAssertTrue(allViews.contains { $0.accessibilityLabel() == "Recorded time 4:05" })
    }

    func testNoTextInThePanelIsSelectable() async {
        await startMeeting()
        recorder.setTranscriptOpen(true)
        await deliver(.system, "Let's ship on Friday.", from: 0, to: 2)
        await deliver(.microphone, "Sounds good to me", from: 4, to: 6, isFinal: false)

        XCTAssertTrue(rowTexts().contains("Let's ship on Friday."))
        XCTAssertTrue(rowTexts().contains("Sounds good to me…"))
        let fields = allViews.compactMap { $0 as? NSTextField }
        XCTAssertFalse(fields.isEmpty)
        XCTAssertTrue(fields.allSatisfy { !$0.isSelectable && !$0.isEditable })
        XCTAssertEqual(transcript.selectionHighlightStyle, .none)
    }

    func testTheDrawerIsClosedAtTheStartOfAMeeting() async {
        await startMeeting()
        XCTAssertFalse(transcriptIsShown)
        XCTAssertEqual(sut.frame.height, pillHeight)

        recorder.setTranscriptOpen(true)
        XCTAssertTrue(transcriptIsShown)
        XCTAssertEqual(sut.frame.height, pillHeight + 280)

        recorder.stopRecording()
        recorder.dismissControls()
        await startMeeting()

        XCTAssertFalse(transcriptIsShown)
        XCTAssertEqual(sut.frame.height, pillHeight)
    }

    func testTheTranscriptButtonOpensAndClosesTheDrawer() async throws {
        await startMeeting()

        try XCTUnwrap(button("Show live transcript")).performClick(nil)
        XCTAssertEqual(recorder.controls?.isTranscriptOpen, true)

        try XCTUnwrap(button("Hide live transcript")).performClick(nil)
        XCTAssertEqual(recorder.controls?.isTranscriptOpen, false)
    }

    func testEscClosesTheDrawer() async {
        await startMeeting()
        recorder.setTranscriptOpen(true)

        sut.cancelOperation(nil)

        XCTAssertEqual(recorder.controls?.isTranscriptOpen, false)
        XCTAssertEqual(sut.frame.height, pillHeight)
    }

    func testHidePanelHidesItAndRecordingGoesOn() async throws {
        await startMeeting()
        recorder.setTranscriptOpen(true)

        try XCTUnwrap(button("Hide panel")).performClick(nil)

        XCTAssertFalse(sut.isVisible)
        XCTAssertEqual(recorder.phase, .recording)
    }

    func testTheDrawerSaysWhyThereIsNoTextAndShowsTheLag() async {
        await startMeeting()
        recorder.setTranscriptOpen(true)
        XCTAssertTrue(allViews.contains { ($0 as? NSTextField)?.stringValue == "Preparing live transcript" && !$0.isHiddenOrHasHiddenAncestor })

        await deliver(.system, "Late words", from: 0, to: 2, at: HostTime(seconds: 1_008))

        XCTAssertFalse(allViews.contains { ($0 as? NSTextField)?.stringValue == "Preparing live transcript" && !$0.isHiddenOrHasHiddenAncestor })
        XCTAssertTrue(allViews.contains { ($0 as? NSTextField)?.stringValue == "6 s behind" && !$0.isHiddenOrHasHiddenAncestor })
    }

    func testTheDrawerOpensAboveThePillNearTheBottomOfTheScreen() async {
        settings.meetingControlsTopRight = CGPoint(x: 1000, y: 200)
        await startMeeting()

        recorder.setTranscriptOpen(true)

        XCTAssertEqual(sut.frame.minY, 200 - pillHeight)
        XCTAssertEqual(sut.frame.height, pillHeight + 280)
    }

    func testScrollingBackStopsFollowingAndEndReturnsToLive() async throws {
        await startMeeting()
        recorder.setTranscriptOpen(true)
        for row in 0..<16 {
            let start = TimeInterval(row * 4)
            await deliver(row.isMultiple(of: 2) ? .system : .microphone,
                          "Row \(row) has enough words to wrap onto a second line in the drawer.",
                          from: start, to: start + 2)
        }
        XCTAssertTrue(lastRowIsVisible)
        XCTAssertNil(returnToLiveTitle)

        let clip = try XCTUnwrap(transcript.enclosingScrollView?.contentView)
        clip.scroll(to: .zero)
        transcript.enclosingScrollView?.reflectScrolledClipView(clip)
        XCTAssertEqual(returnToLiveTitle, "Return to live")

        await deliver(.system, "One more.", from: 64, to: 66)
        await deliver(.microphone, "And another.", from: 68, to: 70)
        XCTAssertEqual(returnToLiveTitle, "Return to live · 2 new")
        XCTAssertFalse(lastRowIsVisible)

        sut.keyDown(with: key(kVK_End, "\u{F72B}"))

        XCTAssertNil(returnToLiveTitle)
        XCTAssertTrue(lastRowIsVisible)
    }

    func testNewRowsScrollIntoViewWhileFollowing() async throws {
        await startMeeting()
        recorder.setTranscriptOpen(true)

        for row in 0..<16 {
            let start = TimeInterval(row * 4)
            await deliver(row.isMultiple(of: 2) ? .system : .microphone,
                          "Row \(row) has enough words to wrap onto a second line in the drawer.",
                          from: start, to: start + 2)
        }

        XCTAssertTrue(lastRowIsVisible)
        XCTAssertGreaterThan(try XCTUnwrap(transcript.enclosingScrollView).contentView.bounds.minY, 0)
    }

    func testStateChangesAreAnnouncedAndTranscriptRowsAreNot() async {
        await startMeeting()
        XCTAssertEqual(announcements.map(\.text), ["Recording started."])
        announcements = []

        hostTime = hostTime + 10
        recorder.pause()
        XCTAssertEqual(announcements.map(\.text), ["Recording paused. Nothing is recorded until you resume."])
        XCTAssertEqual(announcements.map(\.priority), [.medium])

        hostTime = hostTime + 10
        recorder.resume()
        XCTAssertEqual(announcements.map(\.text).last, "Recording resumed.")
        announcements = []
        recorder.setTranscriptOpen(true)
        await deliver(.system, "Let's ship on Friday.", from: 0, to: 2)
        hostTime = hostTime + 1
        recorder.onControlsChange?()
        XCTAssertTrue(announcements.isEmpty)

        capture.interrupt(reason: "The microphone was disconnected.")
        XCTAssertEqual(announcements.map(\.text), ["Recording stopped. The microphone was disconnected."])
        XCTAssertEqual(announcements.map(\.priority), [.high])
    }

    func testWithReduceMotionTheDrawerOpensWithoutAFrameAnimation() async {
        reduceMotion = true
        await startMeeting()
        let closed = sut.frame

        let start = Date()
        recorder.setTranscriptOpen(true)

        XCTAssertLessThan(Date().timeIntervalSince(start), 0.1)
        XCTAssertEqual(sut.animationResizeTime(sut.frame), 0)
        XCTAssertEqual(sut.frame.height, closed.height + 280)
        XCTAssertEqual(sut.frame.maxY, closed.maxY)
    }

    func testWithoutReduceMotionTheDrawerGrowsIntoPlace() async {
        reduceMotion = false
        await startMeeting()
        let closed = sut.frame

        let start = Date()
        recorder.setTranscriptOpen(true)

        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.15, "the frame grows over time")
        XCTAssertEqual(sut.frame.height, closed.height + 280)
        XCTAssertEqual(sut.frame.maxY, closed.maxY)
    }

    func testWithReduceTransparencyThePillHasNoGlass() async {
        await startMeeting()
        XCTAssertTrue(allViews.contains { $0 is NSGlassEffectView })

        reduceTransparency = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                   object: NSWorkspace.shared)

        XCTAssertFalse(allViews.contains { $0 is NSGlassEffectView })
        XCTAssertNotNil(button("Pause recording"))
    }

    func testShowingAndOpeningTheDrawerWriteNothingToSettings() async {
        await startMeeting()
        recorder.setTranscriptOpen(true)
        recorder.setTranscriptOpen(false)

        XCTAssertEqual(pillTopRight, CGPoint(x: 1424, y: 859))
        XCTAssertNil(defaults.object(forKey: "meetingControlsTopRight"))
        XCTAssertNil(defaults.object(forKey: "meetingTranscriptHeight"))
    }

    func testAScreenChangeMovesThePillOnScreenAndKeepsTheSavedPosition() async {
        settings.meetingControlsTopRight = CGPoint(x: 2000, y: 600)
        screens.all = [primary, right]
        await startMeeting()
        XCTAssertEqual(pillTopRight, CGPoint(x: 2000, y: 600))

        screens.all = [primary]
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)

        XCTAssertEqual(pillTopRight, CGPoint(x: 1424, y: 859))
        XCTAssertEqual(settings.meetingControlsTopRight, CGPoint(x: 2000, y: 600))
        XCTAssertNil(defaults.object(forKey: "meetingTranscriptHeight"))
    }

    func testTheEndOfADragWritesThePositionOnce() async {
        await startMeeting()
        let grab = CGPoint(x: sut.frame.minX + 4, y: sut.frame.maxY - 4)

        mouse(.leftMouseDown, at: grab)
        mouse(.leftMouseDragged, at: CGPoint(x: grab.x - 100, y: grab.y - 50))
        XCTAssertEqual(pillTopRight, CGPoint(x: 1324, y: 809))
        XCTAssertNil(settings.meetingControlsTopRight, "nothing is written while dragging")
        mouse(.leftMouseDragged, at: CGPoint(x: grab.x - 200, y: grab.y - 100))
        mouse(.leftMouseUp, at: CGPoint(x: grab.x - 200, y: grab.y - 100))

        XCTAssertEqual(pillTopRight, CGPoint(x: 1224, y: 759))
        XCTAssertEqual(settings.meetingControlsTopRight, CGPoint(x: 1224, y: 759))
    }

    func testADragOffTheScreenSavesThePositionClampedOnScreen() async {
        await startMeeting()
        let grab = CGPoint(x: sut.frame.minX + 4, y: sut.frame.maxY - 4)

        mouse(.leftMouseDown, at: grab)
        mouse(.leftMouseDragged, at: CGPoint(x: grab.x + 100, y: grab.y))
        mouse(.leftMouseUp, at: CGPoint(x: grab.x + 100, y: grab.y))

        XCTAssertEqual(settings.meetingControlsTopRight, CGPoint(x: 1440, y: 859))
        XCTAssertEqual(pillTopRight, CGPoint(x: 1440, y: 859))
    }

    func testAClickOnThePillWritesNothing() async {
        await startMeeting()
        let grab = CGPoint(x: sut.frame.minX + 4, y: sut.frame.maxY - 4)

        mouse(.leftMouseDown, at: grab)
        mouse(.leftMouseUp, at: grab)

        XCTAssertNil(defaults.object(forKey: "meetingControlsTopRight"))
    }

    func testTheEndOfAResizeWritesTheHeightOnce() async {
        await startMeeting()
        recorder.setTranscriptOpen(true)
        let grip = CGPoint(x: sut.frame.midX, y: sut.frame.minY + 4)

        mouse(.leftMouseDown, at: grip)
        mouse(.leftMouseDragged, at: CGPoint(x: grip.x, y: grip.y - 40))
        XCTAssertEqual(sut.frame.height, pillHeight + 320)
        XCTAssertNil(defaults.object(forKey: "meetingTranscriptHeight"), "nothing is written while resizing")
        mouse(.leftMouseDragged, at: CGPoint(x: grip.x, y: grip.y - 60))
        mouse(.leftMouseUp, at: CGPoint(x: grip.x, y: grip.y - 60))

        XCTAssertEqual(sut.frame.height, pillHeight + 340)
        XCTAssertEqual(settings.meetingTranscriptHeight, 340)
    }

    func testTheSavedHeightIsUsedAndClamped() async {
        settings.meetingTranscriptHeight = 900
        await startMeeting()

        recorder.setTranscriptOpen(true)

        XCTAssertEqual(sut.frame.height, pillHeight + 460)
    }

    func testRestoreDefaultPositionMovesThePillBackAndForgetsTheSavedOne() async {
        settings.meetingControlsTopRight = CGPoint(x: 1000, y: 500)
        await startMeeting()
        XCTAssertEqual(pillTopRight, CGPoint(x: 1000, y: 500))

        recorder.onControlsRequest?(.restoreDefaultPosition)

        XCTAssertEqual(pillTopRight, CGPoint(x: 1424, y: 859))
        XCTAssertNil(settings.meetingControlsTopRight)
    }

    /// Writes one PNG per state, in light and dark, when KUKA_PANEL_SNAPSHOTS names a folder.
    func testWritesAPictureOfEachState() async throws {
        guard let path = ProcessInfo.processInfo.environment["KUKA_PANEL_SNAPSHOTS"] else {
            throw XCTSkip("Set KUKA_PANEL_SNAPSHOTS to a folder to write pictures of the panel.")
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func snap(_ name: String) throws {
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                try writePicture(of: sut, appearance: NSAppearance(named: appearance)!,
                                 to: folder.appendingPathComponent("\(name)-\(suffix).png"))
            }
        }

        microphone = .notDetermined
        var prompt: CheckedContinuation<Bool, Never>?
        answerMicrophonePrompt = { await withCheckedContinuation { prompt = $0 } }
        let start = Task { await recorder.toggleRecording() }
        await waitUntil { prompt != nil }
        try snap("01-starting")
        microphone = .granted
        prompt?.resume(returning: true)
        await start.value

        hostTime = HostTime(seconds: 1_000 + 636)
        recorder.onControlsChange?()
        try snap("02-recording")

        recorder.setTranscriptOpen(true)
        try snap("03-preview-loading")

        liveTranscriber.send(.unavailable("Live text is not available for Finnish (Finland)."))
        await waitUntil { recorder.controls?.preview?.status != .preparing }
        try snap("04-unavailable")

        recorder.stopRecording()
        try snap("05-saved")
        recorder.dismissControls()

        hostTime = HostTime(seconds: 1_000)
        await startMeeting()
        recorder.setTranscriptOpen(true)
        await deliver(.system, "Okay, I think everyone's here. Let's start with the release date for 2.4.", from: 1, to: 5)
        await deliver(.microphone, "Sure. The plan is still to cut the release branch on Thursday.", from: 6, to: 10)
        await deliver(.system, "Is QA comfortable with Thursday, or do they need the extra week?", from: 11, to: 15)
        await deliver(.microphone, "They asked for two more days for the sync tests.", from: 16, to: 19)
        hostTime = HostTime(seconds: 1_020)
        recorder.pause()
        hostTime = HostTime(seconds: 1_050)
        recorder.resume()
        // File positions after the resume are 3 s later than the recorded time.
        await deliver(.system, "Two days is fine. What about the onboarding changes?", from: 24, to: 27,
                      at: HostTime(seconds: 1_054.5))
        await deliver(.system, "Can we ship onboarding behind a flag if legal is late?", from: 28, to: 31,
                      at: HostTime(seconds: 1_058.5))
        await deliver(.microphone, "We can. The flag already exists, it just defaults to", from: 33, to: 36,
                      isFinal: false, at: HostTime(seconds: 1_063.5))
        try snap("06-recording-open")

        await deliver(.system, "Good, then let's keep the date.", from: 37, to: 39, at: HostTime(seconds: 1_072))
        try snap("07-behind")

        recorder.pause()
        try snap("08-paused-open")
        recorder.setTranscriptOpen(false)
        try snap("09-paused")
        hostTime = HostTime(seconds: 1_073)
        recorder.resume()
        recorder.setTranscriptOpen(true)

        let clip = try XCTUnwrap(transcript.enclosingScrollView?.contentView)
        clip.scroll(to: .zero)
        transcript.enclosingScrollView?.reflectScrolledClipView(clip)
        // After the second resume, file positions are 6 s later than the recorded time.
        await deliver(.system, "Agreed, Thursday it is.", from: 48, to: 48.4, at: HostTime(seconds: 1_073.5))
        try snap("10-scrolled-back")

        capture.interrupt(reason: "The microphone was disconnected.")
        try snap("11-interrupted")
    }

    private func writePicture(of panel: NSPanel, appearance: NSAppearance, to url: URL) throws {
        panel.appearance = appearance
        let view = try XCTUnwrap(panel.contentView)
        view.layoutSubtreeIfNeeded()
        view.needsDisplay = true
        view.displayIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)

        // A desktop-like backdrop, so text on a transparent background stays readable.
        let margin: CGFloat = 24
        let size = NSSize(width: view.bounds.width + 2 * margin, height: view.bounds.height + 2 * margin)
        let image = NSImage(size: size, flipped: false) { rect in
            (appearance.name == .darkAqua ? NSColor(red: 0.11, green: 0.16, blue: 0.16, alpha: 1)
                : NSColor(red: 0.79, green: 0.83, blue: 0.77, alpha: 1)).setFill()
            rect.fill()
            rep.draw(in: NSRect(x: margin, y: margin, width: view.bounds.width, height: view.bounds.height))
            return true
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }
}
