import XCTest
@testable import KuKa

final class LogTests: XCTestCase {
    func testStringsArePrivateUnlessMarkedPublic() {
        let path = "/Users/someone/Meetings"
        let message: LogMessage = "read \(path), wrote \(path, privacy: .public)"
        XCTAssertEqual(message.text, "read <private>, wrote /Users/someone/Meetings")
    }

    func testNumbersBooleansAndReasonCodesArePublic() {
        let message: LogMessage = "\(412) scans, \(0.25) s, \(true), \(TeamsScanReason.axError(-25204))"
        XCTAssertEqual(message.text, "412 scans, 0.25 s, true, axError(-25204)")
    }

    func testAPrivateValueCanBeMarkedPrivateExplicitly() {
        let message: LogMessage = "\(TeamsScanReason.noTeamsApp, privacy: .private)"
        XCTAssertEqual(message.text, "<private>")
    }

    func testEveryCategoryUsesTheAppSubsystem() {
        XCTAssertEqual(Log.subsystem, "com.kuka.screenshot")
        XCTAssertEqual([Log.app, Log.capture, Log.tiling, Log.hotkeys, Log.permissions, Log.keepAwake,
                        Log.clipboard, Log.meeting, Log.teams].map(\.category),
                       ["app", "capture", "tiling", "hotkeys", "permissions", "keepAwake", "clipboard", "meeting",
                        "teams"])
    }
}
