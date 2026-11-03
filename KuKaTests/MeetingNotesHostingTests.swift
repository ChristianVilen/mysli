import AppKit
import XCTest
@testable import KuKa

@MainActor
final class MeetingNotesHostingTests: MeetingNotesTestCase {
    private var slot: FakeNotesSlot!
    private var windows: [MeetingTypedNotesHost] = []
    private var hosting: MeetingNotesHosting!

    override func setUpWithError() throws {
        try super.setUpWithError()
        slot = FakeNotesSlot()
        windows = []
        hosting = MeetingNotesHosting(panel: slot, recorder: recorder, notes: sut, makeWindow: { [unowned self] view in
            let window = MeetingTypedNotesHost(view: view, activation: .fake(), present: { _ in })
            windows.append(window)
            return window
        })
        sut.onStateChange = { [unowned self] in hosting.activeMeetingChanged() }
    }

    override func tearDown() {
        for window in windows { window.detach() }
        super.tearDown()
    }

    private func recordAndStop() async throws -> MeetingFolder {
        await recorder.toggleRecording()
        let meeting = try XCTUnwrap(recorder.activeMeeting)
        recorder.stopRecording()
        await sut.waitUntilIdle()
        return meeting
    }

    func testNotesOfTheRecordingMeetingOpenInThePanel() async throws {
        await recorder.toggleRecording()
        let meeting = try XCTUnwrap(recorder.activeMeeting)

        try hosting.open(meeting)

        XCTAssertEqual(slot.attached?.session.meeting, meeting)
        XCTAssertTrue(windows.isEmpty)
    }

    func testNotesOfAMeetingThatIsNotRecordingOpenInOneWindow() async throws {
        let meeting = try await recordAndStop()

        try hosting.open(meeting)
        try hosting.open(meeting)

        XCTAssertNil(slot.attached)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual((windows[0].window?.contentView as? MeetingTypedNotesView)?.session.meeting, meeting)
    }

    func testNotesStayInThePanelAfterStopAndMoveToAWindowWhenTheNextRecordingStarts() async throws {
        await recorder.toggleRecording()
        let first = try XCTUnwrap(recorder.activeMeeting)
        try hosting.open(first)
        let view = try XCTUnwrap(slot.attached)
        view.session.setFirstRow("Decision")
        recorder.stopRecording()
        await sut.waitUntilIdle()
        XCTAssertTrue(slot.attached === view)

        await recorder.toggleRecording()

        XCTAssertNotEqual(recorder.activeMeeting, first)
        XCTAssertNil(slot.attached)
        XCTAssertTrue(windows.last?.window?.contentView === view)
        XCTAssertEqual(view.session.firstRowText, "Decision")
    }

    func testClosingUnsavedNotesInThePanelKeepsTheDraftForTheNextOpen() async throws {
        await recorder.toggleRecording()
        let meeting = try XCTUnwrap(recorder.activeMeeting)
        try hosting.open(meeting)
        let view = try XCTUnwrap(slot.attached)
        try meeting.write("Changed elsewhere", to: .notes)
        view.session.setFirstRow("Unsaved draft")
        XCTAssertTrue(view.session.hasUnsavedChanges)

        slot.onCloseNotes?()
        XCTAssertNil(slot.attached)
        try hosting.open(meeting)

        XCTAssertTrue(slot.attached === view)
    }

    func testClosingSavedNotesInThePanelReleasesTheSessionOnce() async throws {
        await recorder.toggleRecording()
        let meeting = try XCTUnwrap(recorder.activeMeeting)
        try hosting.open(meeting)
        let view = try XCTUnwrap(slot.attached)

        slot.onCloseNotes?()
        slot.onCloseNotes?()

        XCTAssertNil(slot.attached)
        XCTAssertFalse(try sut.typedNotes(for: meeting) === view.session)
    }

    func testClosingTheWindowOfSavedNotesReleasesThem() async throws {
        let meeting = try await recordAndStop()
        try hosting.open(meeting)
        let firstView = try XCTUnwrap(windows.first?.window?.contentView)

        windows[0].close()
        try hosting.open(meeting)

        XCTAssertEqual(windows.count, 2)
        XCTAssertFalse(windows[1].window?.contentView === firstView)
    }
}

@MainActor
private final class FakeNotesSlot: MeetingNotesSlot {
    private(set) var attached: MeetingTypedNotesView?
    var onCloseNotes: (() -> Void)?

    func attachNotes(_ view: MeetingTypedNotesView) { attached = view }
    func detachNotes() { attached = nil }
}
