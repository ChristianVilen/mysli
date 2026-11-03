import XCTest
@testable import KuKa

final class MeetingPanelCopyTests: XCTestCase {
    private func announcement(from old: MeetingControls.Status?, to new: MeetingControls.Status?) -> String? {
        MeetingPanelCopy.announcement(from: old, to: new).map { "\($0.priority.rawValue) \($0.text)" }
    }

    func testPauseAndResumeAreAnnouncedAtMediumPriority() {
        XCTAssertEqual(announcement(from: .recording, to: .paused),
                       "50 Recording paused. Nothing is recorded until you resume.")
        XCTAssertEqual(announcement(from: .paused, to: .recording), "50 Recording resumed.")
    }

    func testAnInterruptionIsAnnouncedAtHighPriorityWithItsReason() {
        XCTAssertEqual(announcement(from: .recording, to: .interrupted(reason: "The display was disconnected.")),
                       "90 Recording stopped. The display was disconnected.")
        XCTAssertEqual(announcement(from: .paused, to: .interrupted(reason: "The microphone stopped.")),
                       "90 Recording stopped. The microphone stopped.")
    }

    func testTheStartAndTheSavedRecordingAreAnnouncedAtMediumPriority() {
        XCTAssertEqual(announcement(from: .starting, to: .recording), "50 Recording started.")
        XCTAssertEqual(announcement(from: .recording, to: .saved), "50 Recording saved. Ku-Ka is making the notes.")
        XCTAssertEqual(announcement(from: .paused, to: .saved), "50 Recording saved. Ku-Ka is making the notes.")
    }

    func testATimeChangeIsNotAnnounced() {
        XCTAssertNil(announcement(from: .recording, to: .recording))
        XCTAssertNil(announcement(from: .paused, to: .paused))
        XCTAssertNil(announcement(from: .saved, to: .saved))
    }

    func testStartingIsNotAnnounced() {
        XCTAssertNil(announcement(from: nil, to: .starting))
        XCTAssertNil(announcement(from: .saved, to: .starting))
    }

    func testNothingIsAnnouncedWhileThePanelIsHiddenOrWhenItShowsAgain() {
        XCTAssertNil(announcement(from: .recording, to: nil))
        XCTAssertNil(announcement(from: .paused, to: nil))
        XCTAssertNil(announcement(from: nil, to: .recording))
        XCTAssertNil(announcement(from: nil, to: .paused))
    }

    func testTheEndOfARecordingIsAnnouncedAlsoWhenThePanelWasHidden() {
        XCTAssertEqual(announcement(from: nil, to: .interrupted(reason: "The display was disconnected.")),
                       "90 Recording stopped. The display was disconnected.")
        XCTAssertEqual(announcement(from: nil, to: .saved), "50 Recording saved. Ku-Ka is making the notes.")
    }
}
