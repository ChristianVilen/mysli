import XCTest
@testable import Mysli

@MainActor
final class SettingsPermissionsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var settings: Settings!
    private var controller: SettingsWindowController!
    private var visible = false
    private var presentFails = false
    private var actions: [String] = []
    private var visibility: [Bool] = []

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SettingsPermissionsTests")!
        defaults.removePersistentDomain(forName: "SettingsPermissionsTests")
        settings = Settings(defaults: defaults, loginItem: FakeLoginItem())
        visible = false
        presentFails = false
        actions = []
        visibility = []
        controller = SettingsWindowController(settings: settings,
            permissionActions: .init(accessibility: { self.actions.append("accessibility") },
                                     screenRecording: { self.actions.append("screen") },
                                     microphone: { self.actions.append("microphone") },
                                     calendar: { self.actions.append("calendar") },
                                     notifications: { self.actions.append("notifications") },
                                     keyboardSettings: { self.actions.append("keyboard") }),
            openURL: { self.actions.append($0.absoluteString) },
            present: { _ in if !self.presentFails { self.visible = true } }, activation: .fake(),
            isWindowVisible: { _ in self.visible })
        controller.onPermissionsVisibilityChanged = { self.visibility.append($0) }
    }

    override func tearDown() {
        controller.close()
        controller = nil
        defaults.removePersistentDomain(forName: "SettingsPermissionsTests")
        super.tearDown()
    }

    func testDirectRoutesReuseTheWindowAndPollOnlyOnPermissions() {
        let window = controller.window
        controller.show(.permissions)
        controller.show(.permissions)
        XCTAssertEqual(visibility, [true])
        controller.show(.help)
        XCTAssertEqual(visibility, [true, false])
        controller.show(.permissions)
        controller.close()
        XCTAssertEqual(visibility, [true, false, true, false])
        XCTAssertTrue(controller.window === window)
        controller.show()
        XCTAssertEqual(controller.selectedPage, .general)
    }

    func testMinimizeHideAndRestoreUpdatePermissionVisibilityWithoutDuplicatingStarts() {
        controller.show(.permissions)
        let notification = Notification(name: NSWindow.didMiniaturizeNotification, object: controller.window)
        visible = false
        controller.windowDidMiniaturize(notification)
        controller.windowDidMiniaturize(notification)
        visible = true
        controller.windowDidDeminiaturize(notification)
        visible = false
        NotificationCenter.default.post(name: NSApplication.didHideNotification, object: NSApp)
        visible = true
        NotificationCenter.default.post(name: NSApplication.didUnhideNotification, object: NSApp)
        XCTAssertEqual(visibility, [true, false, true, false, true])
    }

    func testSettingsSuppliesChoicesActionsAndGrantsWithoutWritingPreferences() throws {
        settings.clipboardHistoryEnabled = false
        settings.windowTilingEnabled = false
        settings.calendarRecordingRemindersEnabled = true
        let before = defaults.persistentDomain(forName: "SettingsPermissionsTests")! as NSDictionary
        controller.show(.permissions)
        controller.renderPermissions(.init(accessibility: false, screenRecording: true, microphone: .notDetermined,
                                           calendar: .notDetermined, notifications: .notDetermined))
        let page = controller.permissionsPage
        let rows = page.permissionList.rows
        XCTAssertEqual(rows.filter { !$0.view.isHidden }.map(\.permission), [.screenRecording, .microphone, .calendar, .notifications])
        XCTAssertFalse(try XCTUnwrap(rows.first { $0.permission == .screenRecording }).view.grantButton.isEnabled)
        try XCTUnwrap(rows.first { $0.permission == .microphone }).view.grantButton.performClick(nil)
        page.keyboardSettings.performClick(nil)
        XCTAssertEqual(actions, ["microphone", "keyboard"])
        XCTAssertEqual(defaults.persistentDomain(forName: "SettingsPermissionsTests")! as NSDictionary, before)
    }

    func testPermissionRefreshRemovesHiddenRowsFromTheKeyboardOrder() throws {
        controller.show(.permissions)
        settings.meetingsEnabled = false
        controller.renderPermissions(.init(accessibility: true, screenRecording: false, microphone: .notDetermined,
                                           calendar: .notDetermined, notifications: .notDetermined))
        let screen = try XCTUnwrap(controller.permissionsPage.permissionList.rows.first { $0.permission == .screenRecording })
        XCTAssertTrue(screen.view.grantButton.nextKeyView === controller.permissionsPage.keyboardSettings)
    }

    func testShortcutSetupRequiresAVisibleScreenshotConflictAndRunsOnce() {
        XCTAssertFalse(controller.showScreenshotSetupIfNeeded(issues: []))
        XCTAssertFalse(controller.showScreenshotSetupIfNeeded(issues: [
            .init(shortcut: .tileLeft, failure: .systemConflict),
            .init(shortcut: .captureArea, failure: .registrationFailed(-108))
        ]))
        XCTAssertFalse(settings.didShowScreenshotShortcutSetup)
        XCTAssertTrue(controller.showScreenshotSetupIfNeeded(issues: [
            .init(shortcut: .captureFullScreen, failure: .systemConflict)
        ]))
        XCTAssertEqual(controller.selectedPage, .permissions)
        XCTAssertTrue(settings.didShowScreenshotShortcutSetup)
        controller.show(.general)
        XCTAssertFalse(controller.showScreenshotSetupIfNeeded(issues: [
            .init(shortcut: .captureFullScreen, failure: .systemConflict)
        ]))
        XCTAssertEqual(controller.selectedPage, .general)
    }

    func testFailedPresentationDoesNotConsumeShortcutSetup() {
        presentFails = true
        XCTAssertFalse(controller.showScreenshotSetupIfNeeded(issues: [
            .init(shortcut: .captureArea, failure: .systemConflict)
        ]))
        XCTAssertFalse(settings.didShowScreenshotShortcutSetup)
    }
}
