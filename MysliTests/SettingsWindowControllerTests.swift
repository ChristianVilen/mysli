import XCTest
@testable import Mysli

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var settings: Settings!
    private var login: FakeLoginItem!
    private var sut: SettingsWindowController!
    private var picked: URL?
    private var policies: [NSApplication.ActivationPolicy] = []
    private var activations = 0

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SettingsWindowControllerTests")!
        defaults.removePersistentDomain(forName: "SettingsWindowControllerTests")
        login = FakeLoginItem()
        settings = Settings(defaults: defaults, loginItem: login)
        settings.meetingsFolder = URL(fileURLWithPath: "/Users/example/Meetings")
        policies = []
        activations = 0
        sut = SettingsWindowController(settings: settings,
            chooseFolder: { [unowned self] _, _, completion in completion(picked) },
            chooseContext: { [unowned self] _, _, completion in completion(picked) },
            present: { _ in },
            activation: .fake(setPolicy: { [unowned self] in policies.append($0) },
                              activateApp: { [unowned self] in activations += 1 }))
    }

    override func tearDown() {
        sut.close()
        sut = nil
        defaults.removePersistentDomain(forName: "SettingsWindowControllerTests")
        super.tearDown()
    }

    func testFourPagesUseOneMysliWindowWithoutChangingPreferences() {
        let before = defaults.persistentDomain(forName: "SettingsWindowControllerTests")! as NSDictionary
        let window = sut.window
        sut.show()
        for button in sut.pageButtons {
            button.performClick(nil)
            XCTAssertTrue(sut.window === window)
        }
        XCTAssertEqual(defaults.persistentDomain(forName: "SettingsWindowControllerTests")! as NSDictionary, before)
    }

    func testSwitchesSavePreferencesAndApplyTypedEffects() {
        var effects: [Bool] = []
        var calendar: [Bool] = []
        sut.onTilingChanged = { effects.append($0) }
        sut.onClipboardChanged = { effects.append($0) }
        sut.onCalendarRemindersChanged = { calendar.append($0) }
        sut.show()
        for control in [sut.launchAtLogin, sut.windowTiling, sut.clipboardHistory,
                        sut.calendarReminders, sut.teamsSpeakerNames] {
            control.performClick(nil)
        }
        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertFalse(settings.windowTilingEnabled)
        XCTAssertFalse(settings.clipboardHistoryEnabled)
        XCTAssertTrue(settings.keepDisplayAwake)
        XCTAssertTrue(settings.teamsSpeakerNamesEnabled)
        XCTAssertEqual(effects, [false, false])
        XCTAssertEqual(calendar, [true])
        XCTAssertNil(defaults.object(forKey: "calendarRecordingRemindersEnabled"),
                     "only CalendarReminderController.setEnabled saves the calendar choice")
    }

    func testCalendarStatusSaysWhatTheUserMustDoAndShowsTheSavedChoice() {
        sut.show()
        let shown: [(CalendarReminderController.Status, Bool)] = [
            (.off, false), (.ready, false), (.requestingAccess, true),
            (.calendarAccessRequired, true), (.notificationsRequired, true), (.readFailed, true)
        ]
        var texts: Set<String> = []
        for (status, isShown) in shown {
            sut.showCalendarStatus(status)
            XCTAssertEqual(sut.calendarStatus.isHidden, !isShown, "\(status)")
            XCTAssertEqual(sut.calendarStatus.stringValue.isEmpty, !isShown, "\(status)")
            if isShown { texts.insert(sut.calendarStatus.stringValue) }
        }
        XCTAssertEqual(texts.count, 4, "each status that needs the user says its own thing")
        XCTAssertEqual(sut.calendarReminders.state, .off)
        settings.calendarRecordingRemindersEnabled = true
        sut.showCalendarStatus(.ready)
        XCTAssertEqual(sut.calendarReminders.state, .on)
    }

    func testChooseCancelClearAndFolderCallback() {
        var folders: [URL] = []
        sut.onMeetingsFolderChanged = { folders.append($0) }
        sut.show()
        picked = URL(fileURLWithPath: "/Users/example/Notes")
        sut.chooseMeetingsFolder.performClick(nil)
        XCTAssertEqual(settings.meetingsFolder.path, "/Users/example/Notes")
        XCTAssertEqual(folders.map(\.path), ["/Users/example/Notes"])
        picked = URL(fileURLWithPath: "/Users/example/background.md")
        sut.chooseBackground.performClick(nil)
        XCTAssertEqual(settings.meetingContextFile?.path, "/Users/example/background.md")
        picked = nil
        sut.chooseBackground.performClick(nil)
        sut.chooseMeetingsFolder.performClick(nil)
        XCTAssertEqual(settings.meetingContextFile?.path, "/Users/example/background.md")
        XCTAssertEqual(folders.count, 1)
        sut.clearBackground.performClick(nil)
        XCTAssertNil(defaults.object(forKey: "meetingContextFile"))
    }

    func testReopeningRefreshesWithoutWritingAndKeepsCustomDuration() {
        defaults.set(7.5, forKey: "thumbnailDuration")
        let before = defaults.persistentDomain(forName: "SettingsWindowControllerTests")! as NSDictionary
        let window = sut.window
        sut.show()
        sut.close()
        settings.windowTilingEnabled = false
        settings.teamsSpeakerNamesEnabled = true
        sut.show()
        XCTAssertTrue(sut.window === window)
        XCTAssertEqual(sut.windowTiling.state, .off)
        XCTAssertEqual(sut.teamsSpeakerNames.state, .on)
        XCTAssertEqual(settings.thumbnailDuration, 7.5)
        XCTAssertEqual(sut.thumbnailDuration.selectedItem?.representedObject as? Double, 7.5)
        fire(sut.thumbnailDuration)
        XCTAssertEqual(settings.thumbnailDuration, 7.5)
        defaults.removeObject(forKey: "windowTilingEnabled")
        defaults.removeObject(forKey: "teamsSpeakerNamesEnabled")
        XCTAssertEqual(defaults.persistentDomain(forName: "SettingsWindowControllerTests")! as NSDictionary, before)
        XCTAssertEqual(login.setCalls, [])
    }

    func testReopeningAfterExternalLoginApprovalClearsPreviousError() {
        login.errorToThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Registration refused"])
        sut.show()
        sut.launchAtLogin.performClick(nil)
        XCTAssertEqual(sut.launchAtLogin.state, .off)
        XCTAssertFalse(sut.loginError.isHidden)
        XCTAssertTrue(sut.loginError.stringValue.contains("Registration refused"))
        sut.close()
        login.isEnabled = true
        sut.show()
        XCTAssertEqual(sut.launchAtLogin.state, .on)
        XCTAssertTrue(sut.loginError.isHidden)
        XCTAssertEqual(sut.loginError.stringValue, "")
    }

    func testEveryPermanentThumbnailAndSummaryChoiceSavesThroughNativeActions() {
        sut.show()
        XCTAssertEqual(sut.thumbnailDuration.itemTitles, ["3 seconds", "5 seconds", "15 seconds", "Forever"])
        for (title, duration) in [("3 seconds", 3.0), ("5 seconds", 5), ("15 seconds", 15), ("Forever", 0)] {
            sut.thumbnailDuration.selectItem(withTitle: title)
            fire(sut.thumbnailDuration)
            XCTAssertEqual(settings.thumbnailDuration, Double(duration))
        }
        for tool in SummaryTool.allCases {
            sut.summaryTool.selectItem(withTitle: tool.title)
            fire(sut.summaryTool)
            XCTAssertEqual(settings.summaryTool, tool)
        }
    }

    func testLongPathsStayWithinTheFormAndExposeFullAccessibleValues() throws {
        let path = "/Users/example/" + String(repeating: "a long folder name/", count: 12) + "background.md"
        settings.meetingsFolder = URL(fileURLWithPath: path).deletingLastPathComponent()
        settings.meetingContextFile = URL(fileURLWithPath: path)
        sut.show()
        let scroll = try XCTUnwrap(descendants(try XCTUnwrap(sut.window?.contentView)).compactMap { $0 as? NSScrollView }.first { !$0.isHidden })
        scroll.layoutSubtreeIfNeeded()
        XCTAssertEqual(sut.window?.contentView?.bounds.width, 760)
        XCTAssertTrue(try XCTUnwrap(scroll.documentView).isFlipped)
        let labels = descendants(try XCTUnwrap(scroll.documentView)).compactMap { $0 as? NSTextField }
        let background = try XCTUnwrap(labels.first { $0.accessibilityLabel() == "Background file" })
        XCTAssertEqual(background.accessibilityValue(), path)
        XCTAssertEqual(background.toolTip, path)
        XCTAssertLessThan(background.frame.width, scroll.contentView.bounds.width)
        sut.window?.setContentSize(NSSize(width: 640, height: 420))
        scroll.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(try XCTUnwrap(scroll.documentView).bounds.height, scroll.contentView.bounds.height)
    }

    func testShowOpensAndCloseClosesTheOrdinaryWindow() {
        sut.show()
        sut.show()
        XCTAssertEqual(policies, [.regular])
        XCTAssertEqual(activations, 2, "every show brings Mysli to the front")
        sut.close()
        XCTAssertEqual(policies, [.regular, .accessory])
    }

    func testPageButtonsSwitchPagesAndShowReturnsToSettings() {
        sut.show()
        sut.pageButtons[SettingsPage.instructions.rawValue].performClick(nil)
        XCTAssertEqual(sut.selectedPage, .instructions)
        XCTAssertEqual(sut.instructions.enclosingScrollView?.isHidden, false)
        XCTAssertEqual(sut.pageButtons.map(\.state), [.off, .on, .off, .off])
        sut.close()
        sut.show()
        XCTAssertEqual(sut.selectedPage, .settings)
        XCTAssertEqual(sut.instructions.enclosingScrollView?.isHidden, true)
        XCTAssertEqual(sut.pageButtons.map(\.state), [.on, .off, .off, .off])
    }

    func testEachPageCyclesTheKeyboardThroughNavigationAndItsLabelledControls() {
        sut.show()
        let settingsControls: [NSView] = [sut.launchAtLogin, sut.windowTiling, sut.clipboardHistory,
            sut.thumbnailDuration, sut.chooseMeetingsFolder, sut.summaryTool, sut.chooseBackground, sut.clearBackground,
            sut.calendarReminders, sut.teamsSpeakerNames]
        assertKeyViewCycle(sut.pageButtons + settingsControls)
        for control in settingsControls {
            XCTAssertFalse(control.accessibilityLabel()?.isEmpty ?? true, "\(control) has no VoiceOver label")
        }
        sut.pageButtons[SettingsPage.instructions.rawValue].performClick(nil)
        assertKeyViewCycle(sut.pageButtons + sut.instructions.guideButtons)
        sut.show(.permissions)
        assertKeyViewCycle(sut.pageButtons + sut.permissionsPage.controls)
        sut.show(.help)
        assertKeyViewCycle(sut.pageButtons + sut.helpPage.controls)
    }

    func testEveryPageKeepsItsControlsInsideTheCompactViewport() throws {
        let window = try XCTUnwrap(sut.window)
        window.setContentSize(NSSize(width: 640, height: 420))
        for page in SettingsPage.allCases {
            sut.show(page)
            let root = try XCTUnwrap(window.contentView)
            root.layoutSubtreeIfNeeded()
            let scroll = try XCTUnwrap(descendants(root).compactMap { $0 as? NSScrollView }.first { !$0.isHidden })
            let document = try XCTUnwrap(scroll.documentView)
            for control in descendants(document).compactMap({ $0 as? NSControl }) {
                let rect = control.convert(control.bounds, to: document)
                XCTAssertGreaterThanOrEqual(rect.minX, -1, "\(page): \(control)")
                XCTAssertLessThanOrEqual(rect.maxX, document.bounds.width + 1, "\(page): \(control)")
            }
        }
    }

    func testGuidesExpandAndCollapseWithTheirVoiceOverState() {
        XCTAssertEqual(sut.instructions.guides.count, 7)
        for (button, body) in sut.instructions.guides {
            XCTAssertTrue(body.isHidden)
            button.performClick(nil)
            XCTAssertFalse(body.isHidden, button.title)
            XCTAssertTrue(button.isAccessibilityExpanded(), button.title)
            button.performClick(nil)
            XCTAssertTrue(body.isHidden, button.title)
            XCTAssertFalse(button.isAccessibilityExpanded(), button.title)
        }
    }

    func testInstructionsShowEveryRegisteredShortcutWithSpokenKeyNames() {
        XCTAssertEqual(Set(SettingsInstructionsView.shortcuts.flatMap(\.shortcuts)), Set(HotkeyShortcut.allCases))
        let keys = descendants(sut.instructions).filter { $0.isAccessibilityElement() && $0.accessibilityRole() == .group }
        XCTAssertEqual(keys.count, SettingsInstructionsView.shortcuts.count)
        XCTAssertTrue(keys.allSatisfy { !($0.accessibilityLabel() ?? "").isEmpty }, "every keycap row has a spoken name")
    }

    func testReduceTransparencyUsesSolidBackgroundsAndIncreaseContrastStrengthensBorders() throws {
        let root = try XCTUnwrap(sut.window?.contentView as? SettingsBackground)
        let groups = descendants(root).compactMap { $0 as? SettingsGlass }
        XCTAssertGreaterThan(groups.count, 1)
        sut.applyDisplayOptions(SettingsDisplayOptions(reduceTransparency: true, increaseContrast: true))
        XCTAssertNotNil(root.layer?.backgroundColor)
        for group in groups {
            XCTAssertNotNil(group.layer?.backgroundColor)
            XCTAssertEqual(group.layer?.borderWidth, 1.5)
            XCTAssertTrue(group.content.superview === group, "the content leaves the hidden glass")
        }
        XCTAssertEqual(sut.pageButtons.map(\.bezelStyle), [.push, .push, .push, .push])
        sut.applyDisplayOptions(SettingsDisplayOptions(reduceTransparency: false, increaseContrast: false))
        XCTAssertNil(root.layer?.backgroundColor)
        for group in groups {
            XCTAssertNil(group.layer?.backgroundColor)
            XCTAssertEqual(group.layer?.borderWidth, 0.5)
            XCTAssertFalse(group.content.superview === group)
        }
        XCTAssertEqual(sut.pageButtons.map(\.bezelStyle), [.glass, .glass, .glass, .glass])
    }

    private func assertKeyViewCycle(_ views: [NSView], file: StaticString = #filePath, line: UInt = #line) {
        for (view, next) in zip(views, views.dropFirst() + [views[0]]) {
            XCTAssertTrue(view.nextKeyView === next, "\(view) → \(next)", file: file, line: line)
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func fire(_ control: NSControl) {
        _ = control.sendAction(control.action, to: control.target)
    }
}
