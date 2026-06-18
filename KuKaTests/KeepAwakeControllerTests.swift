import XCTest
@testable import KuKa

final class KeepAwakeControllerTests: XCTestCase {
    private var clock: Date!
    private var preventer: FakeSleepPreventer!
    private var manager: WakeManager!
    private var controller: KeepAwakeController!
    private var menu: NSMenu!

    override func setUp() {
        super.setUp()
        clock = Date(timeIntervalSince1970: 1_000_000)
        preventer = FakeSleepPreventer()
        manager = WakeManager(preventer: preventer, now: { self.clock })
        controller = KeepAwakeController(wakeManager: manager, now: { self.clock })
        menu = NSMenu()
        controller.buildMenuSection(into: menu)
    }

    // MARK: - Menu lookups

    /// The "Keep Awake For" submenu is the only section item carrying a submenu.
    private var presetSubmenu: NSMenu {
        menu.items.first { $0.submenu != nil }!.submenu!
    }

    private func preset(_ title: String) -> NSMenuItem {
        presetSubmenu.items.first { $0.title == title }!
    }

    private var turnOffItem: NSMenuItem {
        menu.items.first { $0.title == "Turn Off" }!
    }

    /// The header is the disabled, actionless item directly before "Turn Off".
    private var headerItem: NSMenuItem {
        let turnOffIndex = menu.items.firstIndex(of: turnOffItem)!
        return menu.items[turnOffIndex - 1]
    }

    /// Invokes an item's target/action exactly as a click would, without
    /// needing a live menu tracking session.
    private func click(_ item: NSMenuItem) {
        _ = item.target?.perform(item.action, with: item)
    }

    // MARK: - Initial state

    func testInactiveSectionHidesStatusAndChecksNothing() {
        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(headerItem.isHidden)
        XCTAssertTrue(turnOffItem.isHidden)
        XCTAssertTrue(presetSubmenu.items.allSatisfy { $0.state == .off })
    }

    // MARK: - Selecting presets (exercises representedObject decode)

    func testClickingIndefinitePresetActivatesAndChecksIt() {
        click(preset("Until I turn it off"))

        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(preventer.beginCount, 1)
        XCTAssertFalse(headerItem.isHidden)
        XCTAssertFalse(turnOffItem.isHidden)
        XCTAssertEqual(headerItem.title, "☕ Awake · On")
        XCTAssertEqual(preset("Until I turn it off").state, .on)
        XCTAssertEqual(preset("1 hour").state, .off)
    }

    func testActivateTimedChecksMatchingPresetAndShowsCountdown() {
        controller.activate(.timed(30 * 60))

        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(preset("30 minutes").state, .on)
        XCTAssertEqual(preset("1 hour").state, .off)
        XCTAssertEqual(preset("Until I turn it off").state, .off)
        XCTAssertEqual(headerItem.title, "☕ Awake · 30 min left")
    }

    func testCountdownHeaderTracksTheInjectedClock() {
        controller.activate(.timed(60 * 60))
        XCTAssertEqual(headerItem.title, "☕ Awake · 1h left")

        clock = clock.addingTimeInterval(15 * 60)
        controller.menuWillOpen() // refreshes the header on open
        XCTAssertEqual(headerItem.title, "☕ Awake · 45 min left")
        controller.menuDidClose()
    }

    // MARK: - Turn off

    func testClickingTurnOffDeactivates() {
        controller.activate(.indefinite)
        click(turnOffItem)

        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(preventer.endCount, 1)
        XCTAssertTrue(headerItem.isHidden)
        XCTAssertTrue(turnOffItem.isHidden)
        XCTAssertTrue(presetSubmenu.items.allSatisfy { $0.state == .off })
    }

    func testSwitchingPresetMovesTheCheckmark() {
        controller.activate(.timed(60 * 60))
        XCTAssertEqual(preset("1 hour").state, .on)

        controller.activate(.timed(120 * 60))
        XCTAssertEqual(preset("1 hour").state, .off)
        XCTAssertEqual(preset("2 hours").state, .on)
    }

    // MARK: - State-change hook (drives the status-bar icon)

    func testOnStateChangeFiresOnActivateAndDeactivate() {
        var changes = 0
        controller.onStateChange = { changes += 1 }

        controller.activate(.indefinite)
        XCTAssertEqual(changes, 1)

        controller.deactivate()
        XCTAssertEqual(changes, 2)
    }

    // MARK: - formatRemaining boundaries

    func testFormatRemaining() {
        XCTAssertEqual(KeepAwakeController.formatRemaining(0), "less than a minute left")
        XCTAssertEqual(KeepAwakeController.formatRemaining(59), "1 min left")
        XCTAssertEqual(KeepAwakeController.formatRemaining(25 * 60), "25 min left")
        XCTAssertEqual(KeepAwakeController.formatRemaining(60 * 60), "1h left")
        XCTAssertEqual(KeepAwakeController.formatRemaining(61 * 60), "1h 1m left")
        XCTAssertEqual(KeepAwakeController.formatRemaining(2 * 60 * 60), "2h left")
    }
}
