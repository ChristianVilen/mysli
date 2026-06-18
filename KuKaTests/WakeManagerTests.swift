import XCTest
@testable import KuKa

final class WakeManagerTests: XCTestCase {
    private var clock: Date!
    private var preventer: FakeSleepPreventer!
    private var manager: WakeManager!

    override func setUp() {
        super.setUp()
        clock = Date(timeIntervalSince1970: 1_000_000)
        preventer = FakeSleepPreventer()
        manager = WakeManager(preventer: preventer, now: { self.clock })
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

        XCTAssertEqual(preventer.beginCount, 1) // begin is idempotent; no double-assert
        XCTAssertEqual(preventer.endCount, 0)
        XCTAssertTrue(manager.isActive)
        XCTAssertEqual(manager.session?.duration, .timed(7200))
    }

    func testDoubleDeactivateIsBalanced() {
        manager.activate(.indefinite)
        manager.deactivate()
        manager.deactivate()

        XCTAssertEqual(preventer.beginCount, 1)
        XCTAssertEqual(preventer.endCount, 1)
    }

    func testTimedSessionExpiresAndFiresCallbacks() {
        var expired = false
        manager.onExpire = { expired = true }

        let done = expectation(description: "timed session expires")
        manager.onStateChange = {
            if !self.manager.isActive { done.fulfill() }
        }

        manager.activate(.timed(0.2))
        wait(for: [done], timeout: 2.0)

        XCTAssertFalse(manager.isActive)
        XCTAssertEqual(preventer.endCount, 1)
        XCTAssertTrue(expired)
    }

    func testSwitchingToIndefiniteCancelsExpiryTimer() {
        var expired = false
        manager.onExpire = { expired = true }

        manager.activate(.timed(0.2))
        manager.activate(.indefinite)

        // Wait past the original 0.2s expiry to prove the cancelled timer never fires.
        let stayedActive = expectation(description: "remains active past original expiry")
        let waiter = Timer(timeInterval: 0.5, repeats: false) { _ in stayedActive.fulfill() }
        RunLoop.current.add(waiter, forMode: .common)
        wait(for: [stayedActive], timeout: 2.0)

        XCTAssertTrue(manager.isActive)
        XCTAssertFalse(expired)
        XCTAssertEqual(preventer.endCount, 0)
    }
}
