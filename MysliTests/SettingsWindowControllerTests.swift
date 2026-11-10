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
    private var tools: ToolController!
    private var toolEffects: [Bool] = []

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
        toolEffects = []
        tools = ToolController(settings: settings, applyEffect: { [unowned self] _, enabled in toolEffects.append(enabled) },
                               setCalendarReminders: { _ in })
        tools.onChange = { [unowned self] in sut.refresh() }
        sut.onToolChanged = { [unowned self] in tools.setEnabled($0, enabled: $1) }
    }

    override func tearDown() {
        sut.close()
        sut = nil
        tools = nil
        defaults.removePersistentDomain(forName: "SettingsWindowControllerTests")
        super.tearDown()
    }

    func testEveryPageUsesOneMysliWindowWithoutChangingPreferences() {
        let before = defaults.persistentDomain(forName: "SettingsWindowControllerTests")! as NSDictionary
        let window = sut.window
        sut.show()
        for page in SettingsPage.allCases {
            sut.sidebar.tableView.selectRowIndexes(IndexSet(integer: page.rawValue), byExtendingSelection: false)
            XCTAssertTrue(sut.window === window)
        }
        XCTAssertEqual(defaults.persistentDomain(forName: "SettingsWindowControllerTests")! as NSDictionary, before)
    }

    func testSwitchesSavePreferencesAndApplyTypedEffects() {
        var effects: [Bool] = []
        var calendar: [Bool] = []
        sut.onKeepScreenOnChanged = { effects.append($0) }
        sut.onCalendarRemindersChanged = { calendar.append($0) }
        sut.show()
        for control in [sut.launchAtLogin, sut.screenshotShortcuts, sut.windowTiling, sut.clipboardHistory,
                        sut.keepScreenOn, sut.calendarReminders, sut.teamsSpeakerNames] {
            control.performClick(nil)
        }
        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertFalse(settings.screenshotShortcutsEnabled)
        XCTAssertFalse(settings.windowTilingEnabled)
        XCTAssertFalse(settings.clipboardHistoryEnabled)
        XCTAssertFalse(settings.keepDisplayAwake)
        XCTAssertTrue(settings.teamsSpeakerNamesEnabled)
        XCTAssertEqual(toolEffects, [false, false, false])
        XCTAssertEqual(effects, [false])
        XCTAssertEqual(calendar, [true])
        XCTAssertNil(defaults.object(forKey: "calendarRecordingRemindersEnabled"),
                     "only CalendarReminderController.setEnabled saves the calendar choice")
    }

    func testToolSwitchesSaveAndReportChoicesAndMeetingsControlsReminders() {
        sut.show()
        sut.keepAwakeEnabled.performClick(nil)
        sut.meetingsEnabled.performClick(nil)
        XCTAssertFalse(settings.keepAwakeEnabled)
        XCTAssertFalse(settings.meetingsEnabled)
        XCTAssertEqual(toolEffects, [false, false])
        XCTAssertFalse(sut.calendarReminders.isEnabled)
        sut.meetingsEnabled.performClick(nil)
        XCTAssertTrue(sut.calendarReminders.isEnabled)
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

    func testReminderRulesSaveUnderTheirDefaultsKeysAndAskForARefresh() {
        var refreshes = 0
        sut.onCalendarReminderRulesChanged = { refreshes += 1 }
        settings.calendarRecordingRemindersEnabled = true
        sut.show()
        XCTAssertEqual(sut.calendarReminderTime.selectedItem?.representedObject as? Int, 0)
        XCTAssertEqual(sut.calendarReminderEvents.selectedItem?.representedObject as? Bool, false)
        let fiveMinutes = sut.calendarReminderTime.itemArray.firstIndex { $0.representedObject as? Int == 5 } ?? -1
        sut.calendarReminderTime.selectItem(at: fiveMinutes)
        sut.calendarReminderTime.sendAction(sut.calendarReminderTime.action, to: sut.calendarReminderTime.target)
        sut.calendarReminderEvents.selectItem(at: 1)
        sut.calendarReminderEvents.sendAction(sut.calendarReminderEvents.action, to: sut.calendarReminderEvents.target)
        XCTAssertEqual(defaults.integer(forKey: "calendarReminderLeadMinutes"), 5)
        XCTAssertTrue(defaults.bool(forKey: "calendarRemindersNeedVideoLink"))
        XCTAssertEqual(refreshes, 2)
        settings.calendarRecordingRemindersEnabled = false
        sut.refresh()
        XCTAssertFalse(sut.calendarReminderTime.isEnabled)
        XCTAssertFalse(sut.calendarReminderEvents.isEnabled)
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
        sut.show(.meetings)
        sut.window?.contentView?.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(sut.pages[.meetings])
        scroll.layoutSubtreeIfNeeded()
        XCTAssertEqual(sut.window?.contentView?.bounds.width, 760)
        XCTAssertTrue(try XCTUnwrap(scroll.documentView).isFlipped)
        let labels = descendants(try XCTUnwrap(scroll.documentView)).compactMap { $0 as? NSTextField }
        let background = try XCTUnwrap(labels.first { $0.accessibilityLabel() == "Background file" })
        XCTAssertEqual(background.accessibilityValue(), path)
        XCTAssertEqual(background.toolTip, path)
        XCTAssertLessThan(background.frame.width, scroll.contentView.bounds.width)
        sut.window?.setContentSize(NSSize(width: 640, height: 420))
        sut.window?.contentView?.layoutSubtreeIfNeeded()
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

    func testNativeSidebarSelectionSwitchesPagesAndShowReturnsToGeneral() {
        sut.show()
        sut.sidebar.tableView.selectRowIndexes(IndexSet(integer: SettingsPage.meetings.rawValue), byExtendingSelection: false)
        XCTAssertEqual(sut.selectedPage, .meetings)
        XCTAssertEqual(sut.pages[.meetings]?.isHidden, false)
        XCTAssertEqual(sut.pages[.general]?.isHidden, true)
        sut.close()
        sut.show()
        XCTAssertEqual(sut.selectedPage, .general)
        XCTAssertEqual(sut.pages[.meetings]?.isHidden, true)
        XCTAssertEqual(sut.sidebar.tableView.selectedRow, SettingsPage.general.rawValue)
    }

    func testEachPageCyclesTheKeyboardThroughNavigationAndItsLabelledControls() throws {
        let guides = { [unowned self] (page: SettingsPage) in sut.guides[page]?.buttons ?? [] }
        let expected: [SettingsPage: [NSView]] = [
            .general: [sut.launchAtLogin],
            .screenshots: [sut.screenshotShortcuts, sut.thumbnailDuration] + guides(.screenshots),
            .clipboard: [sut.clipboardHistory] + guides(.clipboard),
            .windows: [sut.windowTiling] + guides(.windows),
            .keepAwake: [sut.keepAwakeEnabled, sut.keepScreenOn] + guides(.keepAwake),
            .meetings: [sut.meetingsEnabled, sut.chooseMeetingsFolder, sut.summaryTool, sut.chooseBackground, sut.clearBackground,
                        sut.calendarReminders, sut.calendarReminderTime, sut.calendarReminderEvents,
                        sut.teamsSpeakerNames] + guides(.meetings),
            .permissions: sut.permissionsPage.controls + guides(.permissions),
            .help: sut.helpPage.controls
        ]
        for page in SettingsPage.allCases {
            sut.show(page)
            let controls = try XCTUnwrap(expected[page])
            assertKeyViewCycle([sut.sidebar.tableView] + controls)
            for control in controls {
                XCTAssertFalse(control.accessibilityLabel()?.isEmpty ?? true, "\(page): \(control) has no VoiceOver label")
            }
        }
    }

    func testEveryPageKeepsItsControlsInsideTheCompactViewport() throws {
        let window = try XCTUnwrap(sut.window)
        window.setContentSize(NSSize(width: 640, height: 420))
        for page in SettingsPage.allCases {
            sut.show(page)
            let root = try XCTUnwrap(window.contentView)
            root.layoutSubtreeIfNeeded()
            let scroll = try XCTUnwrap(sut.pages[page])
            let document = try XCTUnwrap(scroll.documentView)
            for control in descendants(document).compactMap({ $0 as? NSControl }) {
                let rect = control.convert(control.bounds, to: document)
                XCTAssertGreaterThanOrEqual(rect.minX, -1, "\(page): \(control)")
                XCTAssertLessThanOrEqual(rect.maxX, document.bounds.width + 1, "\(page): \(control)")
            }
        }
    }

    func testGuidesExpandAndCollapseWithTheirVoiceOverState() {
        let all = SettingsPage.allCases.flatMap { sut.guides[$0]?.guides ?? [] }
        XCTAssertEqual(all.count, 7)
        for (button, body) in all {
            XCTAssertTrue(body.isHidden)
            button.performClick(nil)
            XCTAssertFalse(body.isHidden, button.title)
            XCTAssertTrue(button.isAccessibilityExpanded(), button.title)
            button.performClick(nil)
            XCTAssertTrue(body.isHidden, button.title)
            XCTAssertFalse(button.isAccessibilityExpanded(), button.title)
        }
    }

    func testToolPagesShowEveryRegisteredShortcutWithSpokenKeyNames() {
        let rows = SettingsPage.allCases.flatMap(\.shortcuts)
        XCTAssertEqual(Set(rows.flatMap(\.shortcuts)), Set(HotkeyShortcut.allCases))
        let keys = SettingsPage.allCases.flatMap { page in
            descendants(sut.pages[page]!).filter { $0.isAccessibilityElement() && $0.accessibilityRole() == .group }
        }
        XCTAssertEqual(keys.count, rows.count)
        XCTAssertTrue(keys.allSatisfy { !($0.accessibilityLabel() ?? "").isEmpty }, "every keycap row has a spoken name")
    }

    func testReduceTransparencyUsesSolidBackgroundsAndIncreaseContrastStrengthensBorders() throws {
        let root = try XCTUnwrap(sut.pages[.general]?.superview as? SettingsBackground)
        let groups = descendants(root).compactMap { $0 as? SettingsGlass }
        XCTAssertFalse(groups.isEmpty)
        sut.applyDisplayOptions(SettingsDisplayOptions(reduceTransparency: true, increaseContrast: true))
        XCTAssertNotNil(root.layer?.backgroundColor)
        for group in groups {
            XCTAssertNotNil(group.layer?.backgroundColor)
            XCTAssertEqual(group.layer?.borderWidth, 1.5)
            XCTAssertTrue(group.content.superview === group, "the content leaves the hidden glass")
        }
        sut.applyDisplayOptions(SettingsDisplayOptions(reduceTransparency: false, increaseContrast: false))
        XCTAssertNil(root.layer?.backgroundColor)
        for group in groups {
            XCTAssertNil(group.layer?.backgroundColor)
            XCTAssertEqual(group.layer?.borderWidth, 0.5)
            XCTAssertFalse(group.content.superview === group)
        }
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
