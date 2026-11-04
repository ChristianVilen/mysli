import XCTest
@testable import Mysli

final class RequiredPermissionsTests: XCTestCase {
    func testEachToolNeedsOnlyItsOwnPermissions() {
        let cases: [(Set<MysliTool>, [MysliPermission])] = [
            ([], []), ([.screenshots], [.screenRecording]), ([.clipboard], [.accessibility]),
            ([.windows], [.accessibility]), ([.keepAwake], []),
            ([.meetings], [.screenRecording, .microphone])
        ]
        for (tools, expected) in cases {
            XCTAssertEqual(RequiredPermissions(tools: tools, calendarReminders: false).permissions, expected)
        }
    }

    func testSharedPermissionsAppearOnceAndRemindersNeedMeetings() {
        let tools = Set(MysliTool.allCases)
        XCTAssertEqual(RequiredPermissions(tools: tools, calendarReminders: false).permissions,
                       [.accessibility, .screenRecording, .microphone])
        XCTAssertEqual(RequiredPermissions(tools: tools, calendarReminders: true).permissions,
                       [.accessibility, .screenRecording, .microphone, .calendar, .notifications])
        XCTAssertEqual(RequiredPermissions(tools: [.keepAwake], calendarReminders: true).permissions, [])
    }

    func testOnlyRequiredPermissionsCanPreventCompletion() {
        let missing = PermissionSnapshot(accessibility: false, screenRecording: false,
                                         microphone: .denied, calendar: .denied, notifications: .denied)
        XCTAssertTrue(RequiredPermissions(tools: [.keepAwake], calendarReminders: false).allGranted(in: missing))
        let screenOnly = PermissionSnapshot(accessibility: false, screenRecording: true,
                                            microphone: .denied, calendar: .denied, notifications: .denied)
        XCTAssertTrue(RequiredPermissions(tools: [.screenshots], calendarReminders: false).allGranted(in: screenOnly))
        XCTAssertFalse(RequiredPermissions(tools: [.meetings], calendarReminders: false).allGranted(in: screenOnly))
        let meeting = PermissionSnapshot(accessibility: false, screenRecording: true,
                                         microphone: .granted, calendar: .full, notifications: .notDetermined)
        XCTAssertTrue(RequiredPermissions(tools: [.meetings], calendarReminders: false).allGranted(in: meeting))
        XCTAssertFalse(RequiredPermissions(tools: [.meetings], calendarReminders: true).allGranted(in: meeting))
        let complete = PermissionSnapshot(accessibility: true, screenRecording: true,
                                          microphone: .granted, calendar: .full, notifications: .granted)
        XCTAssertTrue(RequiredPermissions(tools: Set(MysliTool.allCases), calendarReminders: true).allGranted(in: complete))
    }

    func testEachMissingPermissionPreventsCompletionWhenAllToolsAndRemindersAreOn() {
        let required = RequiredPermissions(tools: Set(MysliTool.allCases), calendarReminders: true)
        let snapshots: [PermissionSnapshot] = [
            .init(accessibility: false, screenRecording: true, microphone: .granted, calendar: .full, notifications: .granted),
            .init(accessibility: true, screenRecording: false, microphone: .granted, calendar: .full, notifications: .granted),
            .init(accessibility: true, screenRecording: true, microphone: .notDetermined, calendar: .full, notifications: .granted),
            .init(accessibility: true, screenRecording: true, microphone: .granted, calendar: .denied, notifications: .granted),
            .init(accessibility: true, screenRecording: true, microphone: .granted, calendar: .full, notifications: .denied)
        ]
        for snapshot in snapshots { XCTAssertFalse(required.allGranted(in: snapshot)) }
    }
}
