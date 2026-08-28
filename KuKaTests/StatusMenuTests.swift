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

    func testHotkeyWarningAppearsOnceWithHolderNameAndClears() {
        sut.updateHotkeyHealth(.secureInputStuck(holderName: "Arc"))
        sut.updateHotkeyHealth(.secureInputStuck(holderName: "Arc"))

        let warnings = menuItems.filter { $0.title == "⚠️ Hotkeys blocked by Arc" }
        XCTAssertEqual(warnings.count, 1, "repeated updates must not duplicate the warning")
        XCTAssertNotNil(item(titled: "Lock and unlock the screen to fix"))

        sut.updateHotkeyHealth(.healthy)

        XCTAssertNil(item(titled: "⚠️ Hotkeys blocked by Arc"))
        XCTAssertNil(item(titled: "Lock and unlock the screen to fix"))
    }

    func testHotkeyWarningNamesAnotherAppWhenHolderIsUnknown() {
        sut.updateHotkeyHealth(.secureInputStuck(holderName: nil))

        XCTAssertNotNil(item(titled: "⚠️ Hotkeys blocked by another app"))
    }

    func testHotkeyWarningForMissingPermission() {
        sut.updateHotkeyHealth(.noPermission)

        XCTAssertNotNil(item(titled: "⚠️ Hotkeys off — Accessibility permission missing"))
        XCTAssertNotNil(item(titled: "Grant it under Permissions… below"))
    }

    func testHotkeyWarningForDeadTap() {
        sut.updateHotkeyHealth(.tapDead)

        XCTAssertNotNil(item(titled: "⚠️ Hotkeys stopped working"))
        XCTAssertNotNil(item(titled: "Quit and reopen Ku-Ka to fix"))
    }

    func testHotkeyWarningSwitchesWhenTheCauseChanges() {
        sut.updateHotkeyHealth(.noPermission)
        sut.updateHotkeyHealth(.tapDead)

        XCTAssertNil(item(titled: "⚠️ Hotkeys off — Accessibility permission missing"))
        XCTAssertNotNil(item(titled: "⚠️ Hotkeys stopped working"))
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
