import XCTest
@testable import KuKa

@MainActor
final class StatusMenuTests: XCTestCase {
    private var defaults: UserDefaults!
    private var loginItem: FakeLoginItem!
    private var settings: Settings!
    private var sut: StatusMenu!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "StatusMenuTests")!
        defaults.removePersistentDomain(forName: "StatusMenuTests")
        loginItem = FakeLoginItem()
        settings = Settings(defaults: defaults, loginItem: loginItem)
        sut = StatusMenu(settings: settings, keepAwake: KeepAwakeController(defaults: defaults))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "StatusMenuTests")
        super.tearDown()
    }

    private func item(titled title: String) -> NSMenuItem? {
        menuItems.first { $0.title == title }
    }

    private var menuItems: [NSMenuItem] { sut.menu.items }

    private func click(_ item: NSMenuItem) {
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
    }

    // MARK: - Hotkey health warning

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

    // MARK: - Structure

    func testMenuContainsCoreItems() {
        for title in ["Launch at Login", "Window Tiling", "Clipboard History", "3 Seconds", "5 Seconds", "15 Seconds", "Forever", "Quit Ku-Ka"] {
            XCTAssertNotNil(item(titled: title), "missing menu item: \(title)")
        }
    }

    func testFeaturesSectionListsClipboardHistoryShortcut() {
        XCTAssertNotNil(item(titled: "⌘⇧C to open clipboard history"), "missing clipboard history feature line")
    }

    // MARK: - Window tiling

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

    // MARK: - Clipboard history

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

    // MARK: - Thumbnail duration

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

    // MARK: - Launch at login

    func testLaunchAtLoginToggleDrivesTheLoginSeam() {
        let login = item(titled: "Launch at Login")!
        XCTAssertEqual(login.state, .off)

        click(login)

        XCTAssertEqual(loginItem.setCalls, [true])
        XCTAssertEqual(login.state, .on)
    }

    // MARK: - Icon

    func testIconDiffersWhenKeepAwakeIsActive() {
        let plain = sut.icon(keepAwakeActive: false, warning: nil)
        let badged = sut.icon(keepAwakeActive: true, warning: nil)
        XCTAssertNotEqual(plain.tiffRepresentation, badged.tiffRepresentation)
    }
}
