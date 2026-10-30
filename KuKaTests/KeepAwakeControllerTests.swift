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
        controller = KeepAwakeController(wakeManager: manager, now: { self.clock }, keepDisplayAwake: true,
                                         notifier: FakeNotifier())
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
        controller.menuWillOpen()
        XCTAssertEqual(panel.titleLabel.stringValue, "☕ Awake · 45 min left")
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

    func testTheSavedDisplayPreferenceReachesThePowerAssertion() {
        let preventer = FakeSleepPreventer()
        let controller = KeepAwakeController(wakeManager: WakeManager(preventer: preventer, now: { self.clock }),
                                             now: { self.clock }, keepDisplayAwake: false, notifier: FakeNotifier())
        controller.activate(.indefinite)
        XCTAssertEqual(preventer.lastKeepDisplayAwake, false)
        controller.deactivate()
    }

    func testChangingDisplayPreferenceUpdatesActivePowerAssertion() {
        clickChip("∞")
        controller.setDisplayAwake(false)
        XCTAssertEqual(preventer.lastKeepDisplayAwake, false)
        XCTAssertTrue(controller.isActive)
    }

    func testMenuDisplayToggleKeepsTheCurrentSessionAndExpiry() throws {
        let toggle = try XCTUnwrap(menu.items.first { $0.title == "Keep screen on" })
        XCTAssertEqual(toggle.state, .on)
        clickChip("1h")
        let expiry = manager.session?.expiresAt
        clock = clock.addingTimeInterval(60)
        click(toggle)
        XCTAssertEqual(toggle.state, .off)
        XCTAssertEqual(preventer.lastKeepDisplayAwake, false)
        XCTAssertEqual(manager.session?.expiresAt, expiry)
        XCTAssertTrue(controller.isActive)
        click(toggle)
        XCTAssertEqual(toggle.state, .on)
        XCTAssertEqual(preventer.lastKeepDisplayAwake, true)
        XCTAssertEqual(manager.session?.expiresAt, expiry)
    }

    func testMenuDisplayTogglePersistsTheChoiceWithoutStartingASession() throws {
        let suite = "KeepAwakeControllerTests.DisplayPreference"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults, loginItem: FakeLoginItem())
        controller.onDisplayAwakeChanged = { settings.keepDisplayAwake = $0 }
        let toggle = try XCTUnwrap(menu.items.first { $0.title == "Keep screen on" })
        click(toggle)
        XCTAssertEqual(defaults.object(forKey: "keepDisplayAwake") as? Bool, false)
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(preventer.beginCount, 0)
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
