import XCTest
@testable import KuKa

@MainActor
final class StatusMenuTests: XCTestCase {
    private var defaults: UserDefaults!
    private var loginItem: FakeLoginItem!
    private var settings: Settings!
    private var meetingsRoot: URL!
    private var sut: StatusMenu!
    private var recorder: MeetingRecorder!
    private var meetingNotes: MeetingNotesController!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "StatusMenuTests")!
        defaults.removePersistentDomain(forName: "StatusMenuTests")
        loginItem = FakeLoginItem()
        settings = Settings(defaults: defaults, loginItem: loginItem)
        meetingsRoot = try makeTemporaryDirectory()
        recorder = MeetingRecorder(
            permissions: PermissionsManager(isAccessibilityTrusted: { true }, hasScreenCaptureAccess: { true },
                                            microphoneAccess: { .granted }),
            root: { [unowned self] in meetingsRoot },
            capture: FakeMeetingAudioCapture(),
            liveTranscriber: FakeLiveTranscriber(),
            notifier: FakeNotifier())
        meetingNotes = MeetingNotesController(
            recorder: recorder,
            root: { [unowned self] in meetingsRoot },
            processor: makeMeetingProcessor(),
            wordsToCheck: { [unowned self] in WordReview.openQuestionCount(of: $0, in: meetingsRoot, knownWords: .empty) },
            chooseFolder: { _ in nil },
            setRoot: { [unowned self] in meetingsRoot = $0 },
            notifier: FakeNotifier())
        sut = StatusMenu(settings: settings, sections: [KeepAwakeController(defaults: defaults), meetingNotes])
    }

    override func tearDown() async throws {
        meetingNotes.shutDown()
        await meetingNotes.waitUntilIdle()
        defaults.removePersistentDomain(forName: "StatusMenuTests")
        try await super.tearDown()
    }

    private func item(titled title: String) -> NSMenuItem? {
        menuItems.first { $0.title == title }
    }

    private var menuItems: [NSMenuItem] { sut.menu.items }

    private func click(_ item: NSMenuItem) {
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
    }

    func testCarbonStartsAndTheMenuKeyEquivalentStopsRecordingOnce() async throws {
        let record = try XCTUnwrap(item(titled: "Start Recording Meeting"))
        XCTAssertEqual(record.title, "Start Recording Meeting")
        XCTAssertEqual(record.keyEquivalent, "m")
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.control, .option],
            timestamp: 0, windowNumber: 0, context: nil, characters: "m",
            charactersIgnoringModifiers: "m", isARepeat: false, keyCode: 46))
        XCTAssertEqual(record.keyEquivalentModifierMask, [.control, .option])
        let system = FakeHotkeySystem()
        let manager = HotkeyManager(registrar: CarbonHotkeyRegistrar(api: system.api))
        let app = AppDelegate(hotkeyManager: manager, meetingRecorder: recorder)
        defer { manager.stop(); withExtendedLifetime(app) {} }
        manager.start()
        system.press(.meetingRecording)
        await waitUntil { self.recorder.phase == .recording }
        XCTAssertEqual(recorder.phase, .recording)
        XCTAssertTrue(sut.menu.performKeyEquivalent(with: event))
        await waitUntil { self.recorder.phase == .idle }
        XCTAssertEqual(recorder.phase, .idle)
    }

    func testRepeatedHealthDoesNotReplaceMenuItems() {
        let health = HotkeyHealth(issues: [.init(shortcut: .tileLeft, failure: .releaseFailed(-50))])
        sut.updateHotkeyHealth(health)
        let warning = sut.menu.items.first
        XCTAssertNotNil(item(titled: "⚠️ ⌃⌥← (tile left) could not be released"))
        XCTAssertNotNil(item(titled: "Ku-Ka will retry automatically"))
        sut.updateHotkeyHealth(health)
        XCTAssertTrue(sut.menu.items.first === warning)
    }

    func testPermissionRecoveryKeepsTheShortcutWarningUntilRegistrationRecovers() {
        let issues = [HotkeyRegistrationIssue(shortcut: .captureArea, failure: .systemConflict)]
        sut.updateHotkeyHealth(.init(accessibilityMissing: true, issues: issues))
        sut.updateHotkeyHealth(.init(issues: issues))
        XCTAssertNil(item(titled: "⚠️ Window tiling and paste need Accessibility permission"))
        XCTAssertNotNil(item(titled: "⚠️ ⇧⌘4 (selected area) is used by macOS"))
        sut.updateHotkeyHealth(.healthy)
        XCTAssertFalse(menuItems.contains { $0.title.hasPrefix("⚠️") })
    }

    func testShortcutWarningsShowConflictsAndPermissionWithoutBlamingAnApp() {
        let health = HotkeyHealth(accessibilityMissing: true, issues: [
            .init(shortcut: .captureArea, failure: .systemConflict),
            .init(shortcut: .tileLeft, failure: .registrationFailed(-9878))
        ])
        sut.updateHotkeyHealth(health)
        sut.updateHotkeyHealth(health)
        XCTAssertEqual(menuItems.filter { $0.title == "⚠️ ⇧⌘4 (selected area) is used by macOS" }.count, 1)
        XCTAssertNotNil(item(titled: "⚠️ Window tiling and paste need Accessibility permission"))
        XCTAssertNotNil(item(titled: "⚠️ ⌃⌥← (tile left) could not be registered"))
        XCTAssertNotNil(item(titled: "In Screenshots, turn off the matching macOS shortcut"))
        var opened = false
        sut.onOpenKeyboardSettings = { opened = true }
        click(item(titled: "Open Keyboard Settings…")!)
        XCTAssertTrue(opened)
        XCTAssertFalse(menuItems.contains { $0.title.contains("blocked by") || $0.title.contains("unlock") })

        sut.updateHotkeyHealth(.healthy)
        XCTAssertFalse(menuItems.contains { $0.title.hasPrefix("⚠️") })
        XCTAssertNil(item(titled: "Open Keyboard Settings…"))
    }

    func testMenuContainsCoreItems() {
        for title in ["Launch at Login", "Window Tiling", "Clipboard History", "3 Seconds", "5 Seconds", "15 Seconds", "Forever", "Quit Ku-Ka"] {
            XCTAssertNotNil(item(titled: title), "missing menu item: \(title)")
        }
    }

    func testFeaturesSectionListsClipboardHistoryShortcut() {
        XCTAssertNotNil(item(titled: "⌘⇧C to open clipboard history"), "missing clipboard history feature line")
    }

    func testMeetingNotesSectionFollowsKeepAwake() throws {
        let titles = menuItems.filter { !$0.isHidden }.map(\.title)
        let lidHint = try XCTUnwrap(titles.firstIndex(of: "Closing the lid still sleeps your Mac"))

        XCTAssertEqual(Array(titles[(lidHint + 1)...(lidHint + 7)]),
                       ["", "Meeting Notes", "Start Recording Meeting", "Open Meetings Folder", "Choose Meetings Folder…", "", "Features"])
    }

    func testOpeningTheMenuShowsFailedMeetingsFromDisk() throws {
        let meeting = try MeetingFolder.create(in: meetingsRoot, startingAt: localDate(2026, 10, 23, 14, 2))
        try meeting.write("# Transcript", to: .transcript)
        try meeting.write("agy exited with status 1", to: .failure)

        sut.menuWillOpen(sut.menu)
        sut.menuDidClose(sut.menu)

        XCTAssertEqual(item(titled: "Retry Failed Meeting")?.isHidden, false)
    }

    func testOpeningTheMenuShowsWordsToCheckFromDiskBeforeRetry() throws {
        let failed = try MeetingFolder.create(in: meetingsRoot, startingAt: localDate(2026, 10, 22, 10, 0))
        try failed.write("# Transcript", to: .transcript)
        try failed.write("agy exited with status 1", to: .failure)
        let reviewed = try MeetingFolder.create(in: meetingsRoot, startingAt: localDate(2026, 10, 23, 14, 2))
        try reviewed.write("**[00:00:01] Them:** Ask Convio.\n", to: .transcript)
        try reviewed.write("# Summary\n", to: .summary)
        try reviewed.write(#"{"questions": [{"heard": "Convio", "kind": "company", "quote": "Ask Convio."}]}"#, to: .questions)

        sut.menuWillOpen(sut.menu)
        sut.menuDidClose(sut.menu)

        let titles = menuItems.filter { !$0.isHidden }.map(\.title)
        let header = try XCTUnwrap(titles.firstIndex(of: "Meeting Notes"))
        XCTAssertEqual(Array(titles[header...(header + 4)]),
                       ["Meeting Notes", "Start Recording Meeting", "Check Words (1)…", "Retry Failed Meeting", "Open Meetings Folder"])
    }

    func testTilingToggleWritesSettingsFiresCallbackAndFlipsCheckmark() {
        let tiling = item(titled: "Window Tiling")!
        XCTAssertEqual(tiling.state, .on, "tiling defaults to enabled")
        var callbackValue: Bool?
        sut.onTilingToggled = { callbackValue = $0 }

        click(tiling)

        XCTAssertFalse(settings.windowTilingEnabled)
        XCTAssertEqual(callbackValue, false)
        XCTAssertEqual(tiling.state, .off)
    }

    func testClipboardHistoryToggleWritesSettingsFiresCallbackAndFlipsCheckmark() {
        let clipboardHistory = item(titled: "Clipboard History")!
        XCTAssertEqual(clipboardHistory.state, .on, "clipboard history defaults to enabled")
        var callbackValue: Bool?
        sut.onClipboardHistoryToggled = { callbackValue = $0 }

        click(clipboardHistory)

        XCTAssertFalse(settings.clipboardHistoryEnabled)
        XCTAssertEqual(callbackValue, false)
        XCTAssertEqual(clipboardHistory.state, .off)
    }

    func testDurationPickIsExclusiveAndPersisted() {
        let fifteen = item(titled: "15 Seconds")!
        XCTAssertEqual(item(titled: "5 Seconds")!.state, .on, "default duration is checked")

        click(fifteen)

        XCTAssertEqual(settings.thumbnailDuration, 15)
        XCTAssertEqual(fifteen.state, .on)
        for title in ["3 Seconds", "5 Seconds", "Forever"] {
            XCTAssertEqual(item(titled: title)!.state, .off, "\(title) should be unchecked")
        }
    }

    func testLaunchAtLoginToggleDrivesTheLoginSeam() {
        let login = item(titled: "Launch at Login")!
        XCTAssertEqual(login.state, .off)

        click(login)

        XCTAssertEqual(loginItem.setCalls, [true])
        XCTAssertEqual(login.state, .on)
    }

    func testIconDiffersWhenKeepAwakeIsActive() {
        let plain = sut.icon(keepAwakeActive: false, recording: nil, warning: nil)
        let badged = sut.icon(keepAwakeActive: true, recording: nil, warning: nil)
        XCTAssertNotEqual(plain.tiffRepresentation, badged.tiffRepresentation)
    }

    func testRecordingAddsItsOwnDotNextToTheOthers() {
        let plain = sut.icon(keepAwakeActive: false, recording: nil, warning: nil)
        let recording = sut.icon(keepAwakeActive: false, recording: .recording, warning: nil)
        let others = sut.icon(keepAwakeActive: true, recording: nil, warning: .shortcutsUnavailable)
        let all = sut.icon(keepAwakeActive: true, recording: .recording, warning: .shortcutsUnavailable)

        XCTAssertNotEqual(plain.tiffRepresentation, recording.tiffRepresentation)
        XCTAssertNotEqual(others.tiffRepresentation, all.tiffRepresentation)
    }

    func testThePausedMarkDiffersFromTheRecordingMarkAndFromNoMark() {
        let plain = sut.icon(keepAwakeActive: false, recording: nil, warning: nil)
        let recording = sut.icon(keepAwakeActive: false, recording: .recording, warning: nil)
        let paused = sut.icon(keepAwakeActive: false, recording: .paused, warning: nil)

        XCTAssertNotEqual(paused.tiffRepresentation, recording.tiffRepresentation)
        XCTAssertNotEqual(paused.tiffRepresentation, plain.tiffRepresentation)
    }
}
