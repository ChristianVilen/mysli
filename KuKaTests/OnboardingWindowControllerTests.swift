import XCTest
@testable import KuKa

@MainActor
final class OnboardingWindowControllerTests: XCTestCase {
    func testOtherShortcutProblemsDoNotConsumeTheOneTimeScreenshotSetup() {
        let defaults = UserDefaults(suiteName: "OnboardingWindowControllerTests")!
        defaults.removePersistentDomain(forName: "OnboardingWindowControllerTests")
        defer { defaults.removePersistentDomain(forName: "OnboardingWindowControllerTests") }
        var opened: [URL] = []
        let permissions = PermissionsManager(
            isAccessibilityTrusted: { true },
            hasScreenCaptureAccess: { true },
            openURL: { opened.append($0); return true }
        )
        permissions.refresh()
        let controller = OnboardingWindowController(permissions: permissions, settings: Settings(defaults: defaults))
        defer { controller.close() }

        XCTAssertFalse(controller.showScreenshotSetupIfNeeded(issues: []))
        XCTAssertFalse(controller.showScreenshotSetupIfNeeded(issues: [
            .init(shortcut: .tileLeft, failure: .systemConflict),
            .init(shortcut: .captureArea, failure: .registrationFailed(-108))
        ]))
        XCTAssertTrue(controller.showScreenshotSetupIfNeeded(issues: [
            .init(shortcut: .captureFullScreen, failure: .systemConflict)
        ]))

        func descendants(of view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap { descendants(of: $0) }
        }
        let views = descendants(of: controller.window!.contentView!)
        let labels = views.compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(labels.contains("⇧⌘3 (full screen)\nSave picture of screen as a file"))
        XCTAssertFalse(labels.contains { $0.contains("Save picture of selected area as a file") })
        let button = views.compactMap { $0 as? NSButton }.first { $0.title == "Open Keyboard Settings…" }!
        _ = (button.target as? NSObject)?.perform(button.action, with: button)
        XCTAssertEqual(opened, [SettingsPane.keyboardShortcuts.urls[0]])
    }

    func testScreenshotSetupCanFollowSkippedAccessibilityPermission() {
        let defaults = UserDefaults(suiteName: "OnboardingWindowControllerTests")!
        defaults.removePersistentDomain(forName: "OnboardingWindowControllerTests")
        defer { defaults.removePersistentDomain(forName: "OnboardingWindowControllerTests") }
        let permissions = PermissionsManager(
            isAccessibilityTrusted: { false },
            hasScreenCaptureAccess: { true }
        )
        permissions.refresh()
        let controller = OnboardingWindowController(permissions: permissions, settings: Settings(defaults: defaults))
        defer { controller.close() }
        controller.show(.checklist)
        controller.close()

        XCTAssertTrue(controller.showScreenshotSetupIfNeeded(issues: [
            .init(shortcut: .captureArea, failure: .systemConflict)
        ]))
        XCTAssertEqual(controller.window?.title, "Ku-Ka Screenshot Setup")
    }

    func testScreenshotSetupWaitsForPermissionSetupToFinish() {
        let defaults = UserDefaults(suiteName: "OnboardingWindowControllerTests")!
        defaults.removePersistentDomain(forName: "OnboardingWindowControllerTests")
        defer { defaults.removePersistentDomain(forName: "OnboardingWindowControllerTests") }
        var screenRecording = false
        let permissions = PermissionsManager(
            isAccessibilityTrusted: { true },
            hasScreenCaptureAccess: { screenRecording }
        )
        permissions.refresh()
        let controller = OnboardingWindowController(permissions: permissions, settings: Settings(defaults: defaults))
        defer { controller.close() }
        let issues = [HotkeyRegistrationIssue(shortcut: .captureArea, failure: .systemConflict)]

        controller.show(.checklist)
        XCTAssertFalse(controller.showScreenshotSetupIfNeeded(issues: issues))
        screenRecording = true
        permissions.refresh()
        XCTAssertFalse(controller.showScreenshotSetupIfNeeded(issues: issues))
        XCTAssertEqual(controller.window?.title, "Ku-Ka Permissions")

        controller.close()
        XCTAssertTrue(controller.showScreenshotSetupIfNeeded(issues: issues))
    }

    func testScreenshotConflictShowsSetupOnlyOnceAcrossLaunches() {
        let defaults = UserDefaults(suiteName: "OnboardingWindowControllerTests")!
        defaults.removePersistentDomain(forName: "OnboardingWindowControllerTests")
        defer { defaults.removePersistentDomain(forName: "OnboardingWindowControllerTests") }
        let permissions = PermissionsManager(
            isAccessibilityTrusted: { true },
            hasScreenCaptureAccess: { true }
        )
        permissions.refresh()
        let controller = OnboardingWindowController(permissions: permissions, settings: Settings(defaults: defaults))
        defer { controller.close() }
        let issues = [HotkeyRegistrationIssue(shortcut: .captureArea, failure: .systemConflict)]

        XCTAssertTrue(controller.showScreenshotSetupIfNeeded(issues: issues))
        XCTAssertEqual(controller.window?.title, "Ku-Ka Screenshot Setup")
        controller.close()

        let nextLaunch = OnboardingWindowController(permissions: permissions, settings: Settings(defaults: defaults))
        defer { nextLaunch.close() }
        XCTAssertFalse(nextLaunch.showScreenshotSetupIfNeeded(issues: issues))
        XCTAssertFalse(nextLaunch.window?.isVisible ?? true)
    }
}
