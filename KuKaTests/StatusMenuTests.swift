import XCTest
@testable import KuKa

@MainActor
final class StatusMenuTests: XCTestCase {
    private var meetingsRoot: URL!
    private var sut: StatusMenu!

    override func setUp() async throws {
        meetingsRoot = try makeTemporaryDirectory()
        let recorder = MeetingRecorder(
            permissions: PermissionsManager(isAccessibilityTrusted: { true }, hasScreenCaptureAccess: { true },
                                            microphoneAccess: { .granted }),
            root: { [unowned self] in meetingsRoot },
            capture: FakeMeetingAudioCapture(),
            notifier: FakeNotifier())
        let meetingNotes = MeetingNotesController(
            recorder: recorder,
            root: { [unowned self] in meetingsRoot },
            processor: makeMeetingProcessor(),
            wordsToCheck: { [unowned self] in WordReview.openQuestionCount(of: $0, in: meetingsRoot, knownWords: .empty) },
            summaryTool: { .automatic },
            notifier: FakeNotifier())
        let keepAwake = KeepAwakeController(wakeManager: WakeManager(preventer: FakeSleepPreventer()),
                                             keepDisplayAwake: true, notifier: FakeNotifier())
        sut = StatusMenu(sections: [keepAwake, meetingNotes])
    }

    private func item(titled title: String) -> NSMenuItem? {
        menuItems.first { $0.title == title }
    }

    private var menuItems: [NSMenuItem] { sut.menu.items }

    private func click(_ item: NSMenuItem) {
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
    }

    func testDropdownOpensKuKaAndKeepsHelpInsideTheWindow() {
        XCTAssertEqual(menuItems.filter { $0.title == "Ku-Ka…" }.count, 1)
        for title in ["Features", "Report a Bug…", "Suggest a Feature…", "Settings…"] {
            XCTAssertNil(item(titled: title), title)
        }
        XCTAssertNotNil(item(titled: "Permissions…"))
        XCTAssertNotNil(item(titled: "Keep screen on"))
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

    func testMenuContainsKuKaAndOperationalItemsOnly() throws {
        let preferenceTitles = ["Settings…", "Settings", "Launch at Login", "Window Tiling", "Clipboard History",
                                "Thumbnail Duration", "3 Seconds", "5 Seconds", "15 Seconds", "Forever",
                                "Choose Meetings Folder…"]
        XCTAssertEqual(menuItems.filter { preferenceTitles.contains($0.title) }.map(\.title), [])
        for title in ["Start Recording Meeting", "Open Meetings Folder", "Permissions…", "Quit Ku-Ka"] {
            XCTAssertNotNil(item(titled: title))
        }
        let settingsItem = try XCTUnwrap(item(titled: "Ku-Ka…"))
        var shown = 0
        sut.onShowKuKa = { shown += 1 }
        click(settingsItem)
        XCTAssertEqual(shown, 1)
    }

    func testFeaturesStayOutOfTheOperationalMenu() {
        XCTAssertNil(item(titled: "⌘⇧C to open clipboard history"))
    }

    func testApplicationMenuGivesOrdinaryWindowsTheStandardCommands() throws {
        let commands = sut.applicationMenu().items.flatMap { $0.submenu?.items ?? [] }
        let expected: [(title: String, key: String, modifiers: NSEvent.ModifierFlags, action: Selector)] = [
            ("Quit Ku-Ka", "q", .command, #selector(NSApplication.terminate(_:))),
            ("Close", "w", .command, #selector(NSWindow.performClose(_:))),
            ("Undo", "z", .command, Selector(("undo:"))),
            ("Redo", "z", [.command, .shift], Selector(("redo:"))),
            ("Cut", "x", .command, #selector(NSText.cut(_:))),
            ("Copy", "c", .command, #selector(NSText.copy(_:))),
            ("Paste", "v", .command, #selector(NSText.paste(_:))),
            ("Select All", "a", .command, #selector(NSText.selectAll(_:)))
        ]
        for command in expected {
            let item = try XCTUnwrap(commands.first { $0.title == command.title }, command.title)
            XCTAssertEqual(item.keyEquivalent, command.key, command.title)
            XCTAssertEqual(item.keyEquivalentModifierMask, command.modifiers, command.title)
            XCTAssertEqual(item.action, command.action, command.title)
            XCTAssertNil(item.target, "\(command.title) must reach the key window through the responder chain")
        }
    }

    func testCommandCommaInApplicationMenuOpensSettings() throws {
        var opened = 0
        sut.onShowSettings = { opened += 1 }
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil, characters: ",", charactersIgnoringModifiers: ",",
            isARepeat: false, keyCode: 43))
        XCTAssertTrue(sut.applicationMenu().performKeyEquivalent(with: event))
        XCTAssertEqual(opened, 1)
    }

    func testMeetingNotesSectionFollowsKeepAwake() throws {
        let titles = menuItems.filter { !$0.isHidden }.map(\.title)
        let lidHint = try XCTUnwrap(titles.firstIndex(of: "Closing the lid still sleeps your Mac"))

        XCTAssertEqual(Array(titles[(lidHint + 1)...(lidHint + 6)]),
                       ["", "Meeting Notes", "Start Recording Meeting", "Open Meetings Folder", "", "Permissions…"])
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
        XCTAssertEqual(Array(titles[header...(header + 5)]),
                       ["Meeting Notes", "Start Recording Meeting", "Check Words (1)…", "Retry Failed Meeting", "Recent Meeting Notes", "Open Meetings Folder"])
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
