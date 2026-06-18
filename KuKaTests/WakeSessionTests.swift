import XCTest
@testable import KuKa

final class WakeSessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testIndefiniteHasNoExpiry() {
        let session = WakeSession(startedAt: start, duration: .indefinite)
        XCTAssertNil(session.expiresAt)
        XCTAssertNil(session.remaining(now: start))
        XCTAssertFalse(session.isExpired(now: start.addingTimeInterval(10_000)))
    }

    func testTimedExpiresAtStartPlusInterval() {
        let session = WakeSession(startedAt: start, duration: .timed(3600))
        XCTAssertEqual(session.expiresAt, start.addingTimeInterval(3600))
    }

    func testIsExpiredBeforeAtAndAfter() {
        let session = WakeSession(startedAt: start, duration: .timed(3600))
        XCTAssertFalse(session.isExpired(now: start.addingTimeInterval(3599)))
        XCTAssertTrue(session.isExpired(now: start.addingTimeInterval(3600)))
        XCTAssertTrue(session.isExpired(now: start.addingTimeInterval(3601)))
    }

    func testRemainingCountsDown() {
        let session = WakeSession(startedAt: start, duration: .timed(3600))
        XCTAssertEqual(session.remaining(now: start), 3600)
        XCTAssertEqual(session.remaining(now: start.addingTimeInterval(600)), 3000)
    }

    func testRemainingClampsToZero() {
        let session = WakeSession(startedAt: start, duration: .timed(3600))
        XCTAssertEqual(session.remaining(now: start.addingTimeInterval(5000)), 0)
    }
}
