import XCTest
@testable import KuKa

@MainActor
final class MeetingTypedNotesFileTests: XCTestCase {
    private func meeting() throws -> MeetingFolder {
        try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: localDate(2026, 10, 30, 10, 0))
    }

    func testNotesDoNotMakeAFolderAMeetingOrAdvanceItsStage() throws {
        let meeting = try meeting()
        let editor = try MeetingTypedNotesSession(meeting: meeting)
        editor.setFirstRow("Decision only")
        XCTAssertNil(meeting.stage())
        FileManager.default.createFile(atPath: meeting.audioURL(.system).path, contents: Data())
        XCTAssertEqual(meeting.stage(), .pending(.transcribe))
        editor.setFirstRow("More notes")
        XCTAssertEqual(meeting.stage(), .pending(.transcribe))
    }

    func testNotesUseASeparateLockAndAnotherEditorCannotOpenThem() throws {
        let meeting = try meeting()
        let recordingLock = try meeting.lock()
        defer { recordingLock.release() }
        let editor = try MeetingTypedNotesSession(meeting: meeting)
        editor.setFirstRow("Saved during recording")
        XCTAssertEqual(try savedNoteTexts(in: meeting), ["Saved during recording"])
        XCTAssertThrowsError(try MeetingTypedNotesSession(meeting: meeting))
        editor.close()
        XCTAssertNoThrow(try MeetingTypedNotesSession(meeting: meeting))
    }

    func testOversizedAndInvalidEditsKeepTheDraftAndLastSavedFile() throws {
        let meeting = try meeting()
        let editor = try MeetingTypedNotesSession(meeting: meeting)
        editor.setFirstRow("Saved text")
        let saved = try meeting.read(.notes)
        let oversized = String(repeating: "ä", count: MeetingTypedNotesFile.maximumBytes / 2 + 1)
        editor.setFirstRow(oversized)
        XCTAssertTrue(editor.hasUnsavedChanges)
        XCTAssertEqual(editor.firstRowText, oversized)
        XCTAssertEqual(try meeting.read(.notes), saved)
        editor.setFirstRow("Invalid\0text")
        XCTAssertNotNil(editor.saveError)
        XCTAssertEqual(try meeting.read(.notes), saved)
        editor.setFirstRow("Repaired")
        XCTAssertNil(editor.saveError)
        XCTAssertEqual(try savedNoteTexts(in: meeting), ["Repaired"])
    }

    func testExternalEditsAreNotOverwrittenAndReloadIsExplicit() throws {
        let meeting = try meeting()
        let editor = try MeetingTypedNotesSession(meeting: meeting)
        editor.setFirstRow("Original")
        try meeting.write("External change", to: .notes)
        editor.setFirstRow("Local draft")
        XCTAssertEqual(try meeting.read(.notes), "External change")
        XCTAssertEqual(editor.firstRowText, "Local draft")
        XCTAssertNotNil(editor.saveError)
        editor.reloadSavedNotes()
        XCTAssertEqual(editor.text, "External change")
        XCTAssertFalse(editor.hasUnsavedChanges)
    }

    func testReadsRejectInvalidUTF8OversizedFilesAndDirectories() throws {
        let meeting = try meeting()
        XCTAssertEqual(try MeetingTypedNotesFile.read(in: meeting), "")
        try Data([0xff]).write(to: meeting.url(for: .notes))
        XCTAssertThrowsError(try MeetingTypedNotesFile.read(in: meeting))
        try Data(repeating: 65, count: MeetingTypedNotesFile.maximumBytes + 1).write(to: meeting.url(for: .notes))
        XCTAssertThrowsError(try MeetingTypedNotesFile.read(in: meeting))
        try FileManager.default.removeItem(at: meeting.url(for: .notes))
        try FileManager.default.createDirectory(at: meeting.url(for: .notes), withIntermediateDirectories: false)
        XCTAssertThrowsError(try MeetingTypedNotesFile.read(in: meeting))
    }
}
