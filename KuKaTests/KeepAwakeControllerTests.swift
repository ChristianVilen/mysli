import XCTest
@testable import KuKa

final class KeepAwakeControllerTests: XCTestCase {
    private static let defaultsSuite = "KeepAwakeControllerTests"

    private var clock: Date!
    private var preventer: FakeSleepPreventer!
    private var manager: WakeManager!
    private var defaults: UserDefaults!
    private var controller: KeepAwakeController!
    private var menu: NSMenu!

    override func setUp() {
        super.setUp()
        clock = Date(timeIntervalSince1970: 1_000_000)
        preventer = FakeSleepPreventer()
        manager = WakeManager(preventer: preventer, now: { self.clock })
        defaults = UserDefaults(suiteName: Self.defaultsSuite)!
        defaults.removePersistentDomain(forName: Self.defaultsSuite)
        controller = KeepAwakeController(wakeManager: manager, now: { self.clock }, defaults: defaults)
        menu = NSMenu()
        controller.buildMenuSection(into: menu)
    }

    // MARK: - Panel lookups

    private var panel: KeepAwakePanelView { controller.panelView }

    private var turnOffItem: NSMenuItem {
        menu.items.first { $0.title == "Turn Off" }!
    }

    /// Chip indices follow `KeepAwakeController.presets` order.
    private func chipIndex(_ chip: String) -> Int {
        KeepAwakeController.presets.firstIndex { $0.chip == chip }!
    }

    /// Drives the panel's segmented control exactly as a click would.
    private func clickChip(_ chip: String) {
        panel.durationControl.selectedSegment = chipIndex(chip)
        panel.durationClicked(panel.durationControl)
    }

    /// Flips the checkbox and fires its action, as a click would.
    private func toggleDisplayCheckbox() {
        let box = panel.displayAwakeCheckbox
        box.state = box.state == .on ? .off : .on
        panel.displayAwakeToggled(box)
    }

    /// Invokes an item's target/action exactly as a click would, without
    /// needing a live menu tracking session.
    private func click(_ item: NSMenuItem) {
        _ = item.target?.perform(item.action, with: item)
    }

    // MARK: - Initial state

    func testInactiveSectionShowsIdleTitleAndNoSelection() {
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(panel.titleLabel.stringValue, "Keep Awake")
        XCTAssertEqual(panel.durationControl.selectedSegment, -1)
        XCTAssertTrue(turnOffItem.isHidden)
    }

    // MARK: - Clicking chips (exercises index → preset decode)

    func testClickingIndefiniteChipActivatesAndSelectsIt() {
        clickChip("∞")

        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(preventer.beginCount, 1)
        XCTAssertFalse(turnOffItem.isHidden)
        XCTAssertEqual(panel.titleLabel.stringValue, "☕ Awake · On")
        XCTAssertEqual(panel.durationControl.selectedSegment, chipIndex("∞"))
    }

    func testActivateTimedSelectsMatchingChipAndShowsCountdown() {
        controller.activate(.timed(30 * 60))

        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(panel.durationControl.selectedSegment, chipIndex("30m"))
        XCTAssertEqual(panel.titleLabel.stringValue, "☕ Awake · 30 min left")
    }

    func testCountdownTitleTracksTheInjectedClock() {
        controller.activate(.timed(60 * 60))
        XCTAssertEqual(panel.titleLabel.stringValue, "☕ Awake · 1h left")

        clock = clock.addingTimeInterval(15 * 60)
        controller.menuWillOpen() // refreshes the title on open
        XCTAssertEqual(panel.titleLabel.stringValue, "☕ Awake · 45 min left")
        controller.menuDidClose()
    }

    // MARK: - Turn off

    func testClickingTurnOffDeactivates() {
        controller.activate(.indefinite)
        click(turnOffItem)

        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(preventer.endCount, 1)
        XCTAssertTrue(turnOffItem.isHidden)
        XCTAssertEqual(panel.titleLabel.stringValue, "Keep Awake")
        XCTAssertEqual(panel.durationControl.selectedSegment, -1)
    }

    func testSwitchingChipMovesSelection() {
        clickChip("1h")
        XCTAssertEqual(panel.durationControl.selectedSegment, chipIndex("1h"))

        clickChip("2h")
        XCTAssertEqual(panel.durationControl.selectedSegment, chipIndex("2h"))
        XCTAssertEqual(manager.session?.duration, .timed(120 * 60))
    }

    // MARK: - Keep display awake preference

    func testDisplayAwakeDefaultsToOn() {
        XCTAssertEqual(panel.displayAwakeCheckbox.state, .on)
        XCTAssertTrue(manager.keepDisplayAwake)

        clickChip("∞")
        XCTAssertEqual(preventer.lastKeepDisplayAwake, true)
    }

    func testTogglingDisplayCheckboxUpdatesManagerAndPersists() {
        toggleDisplayCheckbox()

        XCTAssertFalse(manager.keepDisplayAwake)
        XCTAssertEqual(defaults.object(forKey: KeepAwakeController.displayAwakeDefaultsKey) as? Bool, false)

        // A fresh controller (fresh app launch) reads the persisted value.
        let newManager = WakeManager(preventer: FakeSleepPreventer(), now: { self.clock })
        _ = KeepAwakeController(wakeManager: newManager, now: { self.clock }, defaults: defaults)
        XCTAssertFalse(newManager.keepDisplayAwake)
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
