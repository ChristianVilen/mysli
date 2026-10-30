import XCTest
@testable import KuKa

@MainActor
final class AppLaunchModeTests: XCTestCase {
    func testXCTestProcessHasPassiveHost() {
        XCTAssertFalse(NSApp.delegate is AppDelegate, "XCTest must not construct the production AppDelegate")
        XCTAssertNil(NSApp.delegate)
    }

    func testLaunchModeChoosesProductionTestsAndPreviewWithTestsTakingPriority() {
        XCTAssertEqual(AppLaunchMode(environment: [:], arguments: ["KuKa"]), .production)
        XCTAssertEqual(AppLaunchMode(environment: [:], arguments: ["KuKa", "--uitesting"]), .settingsPreview)
        XCTAssertEqual(AppLaunchMode(environment: ["XCTestConfigurationFilePath": "tests"], arguments: ["KuKa"]), .xctest)
        XCTAssertEqual(AppLaunchMode(environment: ["XCTestConfigurationFilePath": "tests"],
                                     arguments: ["KuKa", "--uitesting"]), .xctest)
    }

    func testPreviewOpensItsSettingsWindowAndWritesOnlyIsolatedPreferencesWithInertLogin() throws {
        let suite = "AppLaunchModeTests.Preview"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        var presented: [NSWindow] = []
        let host = SettingsPreviewAppDelegate(defaults: defaults, present: { presented.append($0) },
            activation: .fake())
        defer { host.settingsWindow.close() }
        let menuItem = try XCTUnwrap(host.statusMenu.menu.item(withTitle: "Settings…"))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(menuItem.action), to: menuItem.target, from: menuItem))
        XCTAssertEqual(presented.count, 1)
        XCTAssertTrue(presented.first === host.settingsWindow.window)
        XCTAssertTrue(defaults.persistentDomain(forName: suite)?.isEmpty ?? true, "opening Settings writes nothing")
        let popup = host.settingsWindow.summaryTool
        popup.selectItem(withTitle: SummaryTool.claude.title)
        _ = popup.sendAction(popup.action, to: popup.target)
        XCTAssertEqual(defaults.string(forKey: "summaryTool"), "claude")
        host.settingsWindow.launchAtLogin.performClick(nil)
        XCTAssertEqual(host.settingsWindow.launchAtLogin.state, .off)
    }
}
