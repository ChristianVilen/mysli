import XCTest
@testable import KuKa

private typealias ButtonCopy = MeetingPanelCopy.Button

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

    func testThePillNamesEveryStatusButRecordingInWords() {
        let statuses: [MeetingControls.Status] = [.starting, .recording, .paused, .saved,
                                                  .interrupted(reason: "The display was disconnected.")]

        XCTAssertEqual(statuses.map(MeetingPanelCopy.word), ["Starting…", nil, "Paused", "Recording saved", "Recording stopped"])
        XCTAssertEqual(MeetingPanelCopy.timeLabel(245), "Recorded time 4:05")
    }

    func testTheEndOfARecordingSaysWhatHappensToTheNotes() {
        XCTAssertEqual(MeetingPanelCopy.note(for: .saved),
                       "Ku-Ka is making the transcript and notes. You get a notification when they are ready.")
        XCTAssertEqual(MeetingPanelCopy.note(for: .interrupted(reason: "The display was disconnected.")),
                       "The display was disconnected. Ku-Ka makes notes from what it recorded. To record the rest, choose Start Recording Meeting.")
        XCTAssertNil(MeetingPanelCopy.note(for: .recording))
        XCTAssertNil(MeetingPanelCopy.note(for: .paused))
        XCTAssertNil(MeetingPanelCopy.note(for: .starting))
    }

    func testThePauseButtonSaysResumeInTextWhilePaused() {
        XCTAssertEqual(MeetingPanelCopy.pauseButton(isPaused: false),
                       ButtonCopy(title: nil, label: "Pause recording",
                                  tooltip: "Pause recording. Nothing is recorded until you resume."))
        XCTAssertEqual(MeetingPanelCopy.pauseButton(isPaused: true),
                       ButtonCopy(title: "Resume", label: "Resume recording", tooltip: "Resume recording"))
    }

    func testEveryOtherButtonHasALabelAndATooltip() {
        XCTAssertEqual(MeetingPanelCopy.stopButton,
                       ButtonCopy(title: nil, label: "Stop recording", tooltip: "Stop recording and make notes"))
        XCTAssertEqual(MeetingPanelCopy.closeButton, ButtonCopy(title: nil, label: "Close", tooltip: "Close"))
        XCTAssertEqual(MeetingPanelCopy.transcriptButton(isOpen: false),
                       ButtonCopy(title: nil, label: "Show live transcript", tooltip: "Show live transcript"))
        XCTAssertEqual(MeetingPanelCopy.transcriptButton(isOpen: true),
                       ButtonCopy(title: nil, label: "Hide live transcript", tooltip: "Hide live transcript"))
        XCTAssertEqual(MeetingPanelCopy.hideButton,
                       ButtonCopy(title: "Hide panel", label: "Hide panel",
                                  tooltip: "Recording continues. Choose Show Meeting Controls in the Ku-Ka menu to bring the panel back."))
    }

    func testTheDrawerSaysItIsADraft() {
        XCTAssertEqual(MeetingPanelCopy.transcriptTitle, "Live transcript")
        XCTAssertEqual(MeetingPanelCopy.draftNote, "Draft until you stop")
        XCTAssertEqual(MeetingPanelCopy.draftTooltip,
                       "Rough text while you record. Ku-Ka writes the full transcript after you stop.")
        XCTAssertEqual(MeetingPanelCopy.transcriptLabel, "Live transcript draft")
        XCTAssertEqual(MeetingPanelCopy.heightGripTooltip, "Drag to change the height")
    }

    func testTheDrawerExplainsALiveTranscriptThatIsNotRunningAndThatRecordingGoesOn() {
        XCTAssertEqual(MeetingPanelCopy.message(for: .preparing)?.title, "Preparing live transcript")
        XCTAssertEqual(MeetingPanelCopy.message(for: .preparing)?.body, "Recording has started and is not affected.")
        let unavailable = MeetingPanelCopy.message(for: .unavailable("Live transcript is not available for Finnish on this Mac."))
        XCTAssertEqual(unavailable?.title, "No live transcript for this meeting")
        XCTAssertEqual(unavailable?.body, "Live transcript is not available for Finnish on this Mac. "
                       + "Ku-Ka still records both sides and writes the full transcript after you stop.")
        let failed = MeetingPanelCopy.message(for: .failed("The speech model stopped."))
        XCTAssertEqual(failed?.title, "Live transcript stopped")
        XCTAssertEqual(failed?.body, "The speech model stopped. Recording continues, and Ku-Ka writes the full transcript after you stop.")
        XCTAssertNil(MeetingPanelCopy.message(for: .live))
    }

    func testTheBehindChipShowsWholeSecondsAndNothingWhileTheTextKeepsUp() {
        XCTAssertEqual(MeetingPanelCopy.behindChip(6.4), "6 s behind")
        XCTAssertNil(MeetingPanelCopy.behindChip(nil))
    }

    func testRowsMarkDraftTextAndPausesInWords() {
        XCTAssertEqual(MeetingPanelCopy.speech("So the plan", isFinal: false), "So the plan…")
        XCTAssertEqual(MeetingPanelCopy.speech("So the plan is to ship.", isFinal: true), "So the plan is to ship.")
        XCTAssertEqual(MeetingPanelCopy.pauseRow(at: 636, duration: nil), "Paused at 10:36")
        XCTAssertEqual(MeetingPanelCopy.pauseRow(at: 636, duration: 30), "Paused at 10:36 for 0:30")
    }

    func testReturnToLiveCountsTheNewRows() {
        XCTAssertEqual(MeetingPanelCopy.returnToLive(newRows: 0), "Return to live")
        XCTAssertEqual(MeetingPanelCopy.returnToLive(newRows: 3), "Return to live · 3 new")
    }
}
