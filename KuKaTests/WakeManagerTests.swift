import XCTest
@testable import KuKa

final class WakeManagerTests: XCTestCase {
    private var clock: Date!
    private var preventer: FakeSleepPreventer!
    private var manager: WakeManager!
    private var expiry: FakeExpiry!

    override func setUp() {
        super.setUp()
        clock = Date(timeIntervalSince1970: 1_000_000)
        preventer = FakeSleepPreventer()
        expiry = FakeExpiry()
        manager = WakeManager(preventer: preventer, now: { self.clock }, scheduleExpiry: expiry.schedule)
    }

    func testActivateIndefiniteBeginsPreventionAndIsActive() {
        var stateChanges = 0
        manager.onStateChange = { stateChanges += 1 }

        manager.activate(.indefinite)

        XCTAssertTrue(manager.isActive)
        XCTAssertEqual(preventer.beginCount, 1)
        XCTAssertEqual(preventer.endCount, 0)
        XCTAssertEqual(stateChanges, 1)
        XCTAssertNil(manager.session?.expiresAt)
    }

    func testManualDeactivateEndsPreventionWithoutFiringExpiry() {
        var expired = false
        manager.onExpire = { expired = true }

        manager.activate(.indefinite)
        manager.deactivate()

        XCTAssertFalse(manager.isActive)
        XCTAssertEqual(preventer.endCount, 1)
        XCTAssertFalse(expired)
    }

    func testReactivateKeepsSingleAssertion() {
        manager.activate(.timed(3600))
        manager.activate(.timed(7200))

        XCTAssertTrue(manager.isActive)
        XCTAssertEqual(manager.session?.duration, .timed(7200))
    }

    func testDoubleDeactivateIsBalanced() {
        manager.activate(.indefinite)
        var stateChanges = 0
        manager.onStateChange = { stateChanges += 1 }

        manager.deactivate()
        manager.deactivate()

        XCTAssertEqual(stateChanges, 1)
    }

    func testTimedSessionExpiresAndFiresCallbacks() {
        var expired = false
        manager.onExpire = { expired = true }
        manager.activate(.timed(60))
        var stateChanges = 0
        manager.onStateChange = { stateChanges += 1 }
        XCTAssertEqual(expiry.intervals, [60])

        expiry.fire()

        XCTAssertFalse(manager.isActive)
        XCTAssertEqual(stateChanges, 1)
        XCTAssertEqual(preventer.endCount, 1)
        XCTAssertTrue(expired)
    }

    // MARK: - Keep display awake

    func testActivatePassesDisplayAwakeFlagToPreventer() {
        manager.keepDisplayAwake = true
        manager.activate(.indefinite)

        XCTAssertEqual(preventer.lastKeepDisplayAwake, true)
    }

    func testTogglingDisplayAwakeMidSessionSwapsAssertionWithoutEndingSession() {
        manager.activate(.timed(3600))
        manager.keepDisplayAwake = true

        XCTAssertEqual(preventer.endCount, 1)
        XCTAssertEqual(preventer.beginCount, 2)
        XCTAssertEqual(preventer.lastKeepDisplayAwake, true)
        XCTAssertTrue(manager.isActive)
        XCTAssertEqual(manager.session?.duration, .timed(3600))
    }

    func testTogglingDisplayAwakeWhileInactiveDoesNotTouchPreventer() {
        manager.keepDisplayAwake = true

        XCTAssertEqual(preventer.beginCount, 0)
        XCTAssertEqual(preventer.endCount, 0)
    }

    func testFailedActivationDoesNotStartSession() {
        preventer.failNextBegin = true
        var stateChanges = 0
        manager.onStateChange = { stateChanges += 1 }

        manager.activate(.indefinite)

        XCTAssertFalse(manager.isActive)
        XCTAssertEqual(preventer.beginCount, 0)
        XCTAssertEqual(stateChanges, 0)
    }

    func testFailedMidSessionSwapDeactivates() {
        manager.activate(.indefinite)
        preventer.failNextBegin = true

        manager.keepDisplayAwake = true

        XCTAssertFalse(manager.isActive)
        XCTAssertEqual(preventer.endCount, 1)
        XCTAssertNil(manager.session)
    }

    func testSettingSameDisplayAwakeValueMidSessionDoesNothing() {
        manager.activate(.indefinite)
        manager.keepDisplayAwake = false

        XCTAssertEqual(preventer.beginCount, 1)
        XCTAssertEqual(preventer.endCount, 0)
    }

    func testSwitchingToIndefiniteCancelsExpiryTimer() {
        var expired = false
        manager.onExpire = { expired = true }

        manager.activate(.timed(60))
        manager.activate(.indefinite)

        XCTAssertEqual(expiry.intervals, [60])
        XCTAssertFalse(expiry.isPending, "the timed session's expiry must be cancelled")
        XCTAssertTrue(manager.isActive)
        XCTAssertFalse(expired)
        XCTAssertEqual(preventer.endCount, 0)
    }
}

/// Holds the scheduled expiry instead of a real timer, so a test fires it at once.
private final class FakeExpiry {
    private(set) var intervals: [TimeInterval] = []
    private var pending: (id: Int, work: () -> Void)?
    var isPending: Bool { pending != nil }

    func schedule(_ interval: TimeInterval, _ work: @escaping () -> Void) -> () -> Void {
        intervals.append(interval)
        let id = intervals.count
        pending = (id, work)
        return { [weak self] in
            if self?.pending?.id == id { self?.pending = nil }
        }
    }

    func fire() {
        let work = pending?.work
        pending = nil
        work?()
    }
}
