import XCTest
@testable import Mysli

@MainActor
final class MeetingNoteEditingTests: XCTestCase {
    func testSplitUndoAndRedoEachSaveOneCompleteDocument() throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: localDate(2026, 11, 3, 10, 0))
        let session = try MeetingTypedNotesSession(meeting: meeting)
        session.undoManager.groupsByEvent = false
        session.noteTime = { .recording(12) }
        let first = session.entries[0].id
        session.updateEntry(id: first, text: "First second")
        session.noteTime = { .recording(24) }
        var snapshots: [[String]] = []
        session.onSaved = { snapshots.append(MeetingNoteDocument.parse(session.savedText).map(\.text)) }

        session.undoManager.beginUndoGrouping()
        let second = try XCTUnwrap(session.splitEntry(id: first, selection: NSRange(location: 6, length: 0)))
        session.undoManager.endUndoGrouping()
        XCTAssertEqual(snapshots, [["First ", "second"]])
        XCTAssertEqual(session.entries.map(\.time), [.recording(12), .recording(24)])
        XCTAssertEqual(session.entries.last?.id, second)

        session.undoManager.undo()
        XCTAssertEqual(snapshots, [["First ", "second"], ["First second"]])
        session.noteTime = { .afterRecording }
        session.undoManager.redo()
        XCTAssertEqual(snapshots, [["First ", "second"], ["First second"], ["First ", "second"]])
        XCTAssertEqual(session.entries.map(\.time), [.recording(12), .recording(24)])
        XCTAssertEqual(session.entries.last?.id, second)
    }

    func testFailedSplitSaveKeepsBothDraftRowsWithoutChangingExternalText() throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: localDate(2026, 11, 3, 10, 0))
        let session = try MeetingTypedNotesSession(meeting: meeting)
        let first = session.entries[0].id
        session.updateEntry(id: first, text: "First second")
        try meeting.write("External edit", to: .notes)
        var saved = 0
        session.onSaved = { saved += 1 }
        XCTAssertNotNil(session.splitEntry(id: first, selection: NSRange(location: 6, length: 0)))
        XCTAssertEqual(session.entries.map(\.text), ["First ", "second"])
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(saved, 0)
        XCTAssertEqual(try meeting.read(.notes), "External edit")
    }
}
