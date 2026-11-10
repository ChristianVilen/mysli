import XCTest
@testable import Mysli

@MainActor
final class PermissionListViewTests: XCTestCase {
    private var requested: [MysliPermission] = []

    private func makeList() -> PermissionListView {
        PermissionListView(actions: .init(
            accessibility: { self.requested.append(.accessibility) },
            screenRecording: { self.requested.append(.screenRecording) },
            microphone: { self.requested.append(.microphone) },
            calendar: { self.requested.append(.calendar) },
            notifications: { self.requested.append(.notifications) },
            keyboardSettings: { XCTFail("Keyboard setup is outside the permission list") },
            inputMonitoring: { self.requested.append(.inputMonitoring) }))
    }

    func testNeededRowsRenderGrantsAndRequestTheirOwnAccess() {
        let list = makeList()
        list.showRequired(RequiredPermissions(tools: Set(MysliTool.allCases), calendarReminders: true))
        list.render(.init(accessibility: true, screenRecording: false, microphone: .notDetermined,
                          calendar: .denied, notifications: .notDetermined))
        XCTAssertEqual(list.rows.filter { !$0.view.isHidden }.map(\.permission),
                       [.accessibility, .screenRecording, .microphone, .calendar, .notifications, .inputMonitoring])
        XCTAssertEqual(list.controls.map(\.isEnabled), [false, true, true, true, true, true])
        for button in list.controls where button.isEnabled { button.performClick(nil) }
        XCTAssertEqual(requested, [.screenRecording, .microphone, .calendar, .notifications, .inputMonitoring])
        list.render(.init(accessibility: false, screenRecording: true, microphone: .granted,
                          calendar: .full, notifications: .granted, inputMonitoring: true))
        for button in list.controls where button.isEnabled { button.performClick(nil) }
        XCTAssertEqual(requested, [.screenRecording, .microphone, .calendar, .notifications, .inputMonitoring, .accessibility])
    }

    func testChangingNeededRowsKeepsTheirCurrentGrantsAndHidesAnEmptyList() {
        let list = makeList()
        list.render(.init(accessibility: false, screenRecording: true, microphone: .granted,
                          calendar: .denied, notifications: .denied))
        list.showRequired(RequiredPermissions(tools: [.keepAwake], calendarReminders: false))
        XCTAssertTrue(list.isHidden)
        XCTAssertTrue(list.controls.isEmpty)
        list.showRequired(RequiredPermissions(tools: [.meetings], calendarReminders: false))
        XCTAssertFalse(list.isHidden)
        XCTAssertEqual(list.rows.filter { !$0.view.isHidden }.map(\.permission), [.screenRecording, .microphone])
        XCTAssertEqual(list.controls.map(\.isEnabled), [false, false])
    }
}
