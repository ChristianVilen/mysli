import XCTest
@testable import KuKa

@MainActor
final class SettingsPermissionsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var settings: Settings!
    private var controller: SettingsWindowController!
    private var visible = false
    private var actions: [String] = []
    private var visibility: [Bool] = []

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "SettingsPermissionsTests")!
        defaults.removePersistentDomain(forName: "SettingsPermissionsTests")
        settings = Settings(defaults: defaults, loginItem: FakeLoginItem())
        visible = false
        actions = []
        visibility = []
        controller = SettingsWindowController(settings: settings,
            permissionActions: .init(accessibility: { self.actions.append("accessibility") },
                                     screenRecording: { self.actions.append("screen") },
                                     microphone: { self.actions.append("microphone") },
                                     keyboardSettings: { self.actions.append("keyboard") }),
            openURL: { self.actions.append($0.absoluteString) },
            present: { _ in self.visible = true }, activation: .fake(),
            isWindowVisible: { _ in self.visible })
        controller.onPermissionsVisibilityChanged = { self.visibility.append($0) }
    }

    override func tearDown() async throws {
        controller.close()
        controller = nil
        defaults.removePersistentDomain(forName: "SettingsPermissionsTests")
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
        XCTAssertEqual(controller.selectedPage, .settings)
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

    func testPermissionRowsRenderAndDispatchOnlyTheirInjectedActions() {
        controller.show(.permissions)
        controller.renderPermissions(.init(accessibility: true, screenRecording: false, microphone: .notDetermined))
        let page = controller.permissionsPage
        XCTAssertEqual(page.accessibilityRow.grantButton.title, "Granted")
        XCTAssertFalse(page.accessibilityRow.grantButton.isEnabled)
        XCTAssertEqual(page.screenRecordingRow.grantButton.title, "Grant")
        XCTAssertEqual(page.microphoneRow.grantButton.title, "Allow")
        page.screenRecordingRow.grantButton.performClick(nil)
        page.microphoneRow.grantButton.performClick(nil)
        page.keyboardSettings.performClick(nil)
        XCTAssertEqual(actions, ["screen", "microphone", "keyboard"])
        controller.renderPermissions(.init(accessibility: false, screenRecording: true, microphone: .denied))
        page.accessibilityRow.grantButton.performClick(nil)
        XCTAssertEqual(page.microphoneRow.grantButton.title, "Grant")
        XCTAssertEqual(actions.last, "accessibility")
    }

    func testShortcutSetupRequiresAVisibleScreenshotConflictAndRunsOnce() {
        XCTAssertFalse(controller.showScreenshotSetupIfNeeded(issues: []))
        XCTAssertFalse(controller.showScreenshotSetupIfNeeded(issues: [
            .init(shortcut: .tileLeft, failure: .systemConflict),
            .init(shortcut: .captureArea, failure: .registrationFailed(-108))
        ]))
        XCTAssertFalse(settings.didShowScreenshotShortcutSetup)
        controller.show(.permissions)
        XCTAssertTrue(controller.showScreenshotSetupIfNeeded(issues: [
            .init(shortcut: .captureFullScreen, failure: .systemConflict)
        ]))
        XCTAssertEqual(controller.selectedPage, .permissions)
        XCTAssertTrue(settings.didShowScreenshotShortcutSetup)
        controller.show(.settings)
        XCTAssertFalse(controller.showScreenshotSetupIfNeeded(issues: [
            .init(shortcut: .captureFullScreen, failure: .systemConflict)
        ]))
        XCTAssertEqual(controller.selectedPage, .settings)
        controller.show(.permissions)
        XCTAssertFalse(controller.permissionsPage.keyboardSettings.isHidden)
    }

    func testFailedPresentationDoesNotConsumeShortcutSetup() {
        let hidden = SettingsWindowController(settings: settings, present: { _ in }, activation: .fake(),
                                              isWindowVisible: { _ in false })
        defer { hidden.close() }
        XCTAssertFalse(hidden.showScreenshotSetupIfNeeded(issues: [
            .init(shortcut: .captureArea, failure: .systemConflict)
        ]))
        XCTAssertFalse(settings.didShowScreenshotShortcutSetup)
    }

    func testHelpActionsOpenTheExistingDestinationsWithoutChangingPreferences() {
        let before = defaults.persistentDomain(forName: "SettingsPermissionsTests")
        controller.show(.help)
        controller.helpPage.reportBug.performClick(nil)
        controller.helpPage.sendFeedback.performClick(nil)
        XCTAssertEqual(actions, ["https://github.com/ChristianVilen/ku-ka/issues/new?labels=bug",
                                 "https://github.com/ChristianVilen/ku-ka/issues/new?labels=enhancement"])
        XCTAssertEqual(defaults.persistentDomain(forName: "SettingsPermissionsTests") as NSDictionary?, before as NSDictionary?)
    }
}
