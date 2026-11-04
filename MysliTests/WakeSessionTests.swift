import XCTest
@testable import Mysli

final class WakeSessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testIndefiniteHasNoExpiry() {
        let session = WakeSession(startedAt: start, duration: .indefinite)
        XCTAssertNil(session.expiresAt)
        XCTAssertNil(session.remaining(now: start))
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
