import XCTest
@testable import KuKa

@MainActor
final class NotifierTests: XCTestCase {
    private func meeting() throws -> MeetingFolder {
        try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: localDate(2026, 10, 23, 14, 2))
    }

    func testAClickSurvivesARoundTripThroughTheNotificationUserInfo() throws {
        let meeting = try meeting()
        let summary = meeting.url(for: .summary)

        XCTAssertEqual(NotificationClick(userInfo: NotificationClick.open(summary).userInfo), .open(summary))
        XCTAssertEqual(NotificationClick(userInfo: NotificationClick.open(meeting.url).userInfo), .open(meeting.url))
        XCTAssertEqual(NotificationClick(userInfo: NotificationClick.checkWords(meeting).userInfo), .checkWords(meeting))
    }

    func testAUserInfoWithoutAClickGivesNil() {
        XCTAssertNil(NotificationClick(userInfo: [:]))
        XCTAssertNil(NotificationClick(userInfo: ["other": "file:///tmp/a"]))
        XCTAssertNil(NotificationClick(userInfo: ["url": 42]))
    }

    func testANotificationThatAnEarlierVersionPostedStillOpensItsFile() {
        XCTAssertEqual(NotificationClick(userInfo: ["url": "file:///Users/test/Meetings/2026-10-23_14-02/summary.md"]),
                       .open(URL(fileURLWithPath: "/Users/test/Meetings/2026-10-23_14-02/summary.md")))
    }

    func testAClickOpensItsFileOrCallsCheckWordsWithItsMeeting() throws {
        let meeting = try meeting()
        var opened: [URL] = []
        var checked: [MeetingFolder] = []
        let notifier = SystemNotifier(open: { opened.append($0) })
        notifier.onCheckWords = { checked.append($0) }

        notifier.perform(.open(meeting.url(for: .summary)))
        notifier.perform(.checkWords(meeting))

        XCTAssertEqual(opened, [meeting.url(for: .summary)])
        XCTAssertEqual(checked, [meeting])
    }
}
