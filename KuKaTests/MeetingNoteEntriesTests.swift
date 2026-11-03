import AppKit
import XCTest
@testable import KuKa

@MainActor
final class MeetingNoteEntriesTests: XCTestCase {
    func testDuplicatedRowIdentifiersPreserveTheExternalDocumentAsLegacyText() {
        let entry = MeetingNoteEntry(time: .recording(12), text: "Copied row")
        let externalText = MeetingNoteDocument.render([entry, entry])
        let parsed = MeetingNoteDocument.parse(externalText)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.time, .undated)
        XCTAssertEqual(parsed.first?.text, externalText)
    }

    func testMalformedDelimiterOrderKeepsWholeDocumentAsLegacyText() {
        let valid = MeetingNoteDocument.render([MeetingNoteEntry(time: .recording(15), text: "Decision")])
        let malformed = valid.replacingOccurrences(of: "**0:15**\n\n", with: "**0:15**\n") + "\n"
        let entries = MeetingNoteDocument.parse(malformed)
        XCTAssertEqual(entries.first?.time, .undated)
        XCTAssertEqual(entries.first?.text, malformed)
    }

    func testPlaceholderUsesTimeOfFirstTextAndKeepsItThroughEditsAndUndo() throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: localDate(2026, 11, 3, 10, 0))
        let session = try MeetingTypedNotesSession(meeting: meeting)
        session.noteTime = { .recording(15) }
        let id = session.entries[0].id
        session.noteTime = { .recording(45) }
        session.updateEntry(id: id, text: "First text")
        XCTAssertEqual(session.entries.first?.time, .recording(45))
        session.noteTime = { .afterRecording }
        session.updateEntry(id: id, text: "")
        session.updateEntry(id: id, text: "Retyped")
        XCTAssertEqual(session.entries.first?.time, .recording(45))
    }

    func testBlankPlaceholderFirstFilledAfterStopIsAfterRecording() throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: localDate(2026, 11, 3, 10, 0))
        let session = try MeetingTypedNotesSession(meeting: meeting)
        session.noteTime = { .recording(15) }
        let id = session.entries[0].id
        session.updateEntry(id: id, text: "")
        session.noteTime = { .afterRecording }
        session.updateEntry(id: id, text: "Written after Stop")
        XCTAssertEqual(session.entries.first?.time, .afterRecording)
    }

    func testUndoRestoresPendingPlaceholderButPersistedRowsKeepTheirTime() throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: localDate(2026, 11, 3, 10, 0))
        let persisted = MeetingNoteEntry(time: .recording(5), text: "Saved")
        try meeting.write(MeetingNoteDocument.render([persisted]), to: .notes)
        let session = try MeetingTypedNotesSession(meeting: meeting)
        session.undoManager.groupsByEvent = false
        session.noteTime = { .recording(15) }
        session.undoManager.beginUndoGrouping()
        let id = try XCTUnwrap(session.splitEntry(id: persisted.id, selection: NSRange(location: 5, length: 0)))
        session.undoManager.endUndoGrouping()
        session.undoManager.undo()
        session.undoManager.redo()
        session.noteTime = { .afterRecording }
        session.updateEntry(id: id, text: "After Stop")
        session.updateEntry(id: persisted.id, text: "")
        session.updateEntry(id: persisted.id, text: "Retyped saved row")
        XCTAssertEqual(session.entries.map(\.time), [.recording(5), .afterRecording])
    }

    func testScreenshotWriteFailureLeavesPlaceholderWaitingForFirstContent() throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: localDate(2026, 11, 3, 10, 0))
        let session = try MeetingTypedNotesSession(meeting: meeting)
        session.noteTime = { .recording(15) }
        let id = session.entries[0].id
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try Data().write(to: meeting.url.appendingPathComponent("attachments"))
        session.noteTime = { .recording(30) }
        XCTAssertThrowsError(try session.addScreenshot(MeetingScreenshot.decode(png), to: id))
        session.noteTime = { .afterRecording }
        session.updateEntry(id: id, text: "First content")
        XCTAssertEqual(session.entries.first?.time, .afterRecording)
        XCTAssertEqual(session.entries.first?.attachments, [])
    }

    func testScreenshotStampsFirstContentAfterStop() throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: localDate(2026, 11, 3, 10, 0))
        let session = try MeetingTypedNotesSession(meeting: meeting)
        session.noteTime = { .recording(15) }
        let id = session.entries[0].id
        session.noteTime = { .afterRecording }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try session.addScreenshot(MeetingScreenshot.decode(XCTUnwrap(bitmap.representation(using: .png, properties: [:]))), to: id)
        XCTAssertEqual(session.entries.first?.time, .afterRecording)
    }

    func testEntryKeepsItsCreationTimeAndRoundTripsMultilineText() throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: localDate(2026, 11, 3, 10, 0))
        let session = try MeetingTypedNotesSession(meeting: meeting)
        session.noteTime = { .recording(754) }
        let id = session.entries[0].id
        session.updateEntry(id: id, text: "Mira checks access.\nKeep thirty days.")
        session.noteTime = { .recording(800) }
        session.updateEntry(id: id, text: "Mira checks access tomorrow.\nKeep thirty days.")
        XCTAssertEqual(session.entries.first?.time, .recording(754))
        let parsed = MeetingNoteDocument.parse(try meeting.read(.notes))
        XCTAssertEqual(parsed.first?.text, "Mira checks access tomorrow.\nKeep thirty days.")
        XCTAssertEqual(parsed.first?.time, .recording(754))
    }

    func testEmptyPlaceholderDoesNotBecomeSummaryEvidence() throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: localDate(2026, 11, 3, 10, 0))
        let session = try MeetingTypedNotesSession(meeting: meeting)
        XCTAssertEqual(session.entries.map(\.text), [""])
        XCTAssertEqual(session.text, "")
        XCTAssertEqual(try MeetingTypedNotesFile.read(in: meeting), "")
    }

    func testSummaryTextHasLabelsTextAndScreenshotLinksButNoStorageMarkers() {
        let name = UUID().uuidString + ".png"
        let entries = [
            MeetingNoteEntry(time: .recording(754), text: "Mira checks access.\nKeep thirty days.", attachments: [name]),
            MeetingNoteEntry(time: .recording(760), text: " \n"),
            MeetingNoteEntry(time: .afterRecording, attachments: [name]),
            MeetingNoteEntry(time: .undated, text: "# Old notes"),
        ]
        let summary = MeetingNoteDocument.summaryText(entries)
        for part in ["12:34", "Mira checks access.\nKeep thirty days.", "After recording", "Undated", "# Old notes"] {
            XCTAssertTrue(summary.contains(part), part)
        }
        XCTAssertEqual(summary.components(separatedBy: "(attachments/\(name))").count, 3, "one link for each screenshot")
        XCTAssertFalse(summary.contains("12:40"), "the blank row is left out")
        XCTAssertFalse(summary.contains("<!--"), "no storage markers")
        XCTAssertEqual(MeetingNoteDocument.summaryText([MeetingNoteEntry(time: .recording(1))]), "")
    }

    func testLegacyMarkdownIsNotReinterpretedAsAttachments() {
        let original = "# Decisions\n\n- [12:34] literal task\n![Image](../../private.png)\n"
        let entries = MeetingNoteDocument.parse(original)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.time, .undated)
        XCTAssertEqual(entries.first?.text, original)
        XCTAssertEqual(entries.first?.attachments, [])
    }

    func testMarkdownKeepsTextReadableWithoutDuplicatingItInMetadata() {
        let entry = MeetingNoteEntry(time: .recording(15), text: "A unique decision\n<!-- Ku-Ka row literal -->")
        let markdown = MeetingNoteDocument.render([entry])
        XCTAssertEqual(markdown.components(separatedBy: "A unique decision").count, 2)
        XCTAssertTrue(markdown.hasPrefix("<!-- Ku-Ka notes v2 -->\n"))
        XCTAssertEqual(MeetingNoteDocument.parse(markdown), [entry])
    }

    func testScreenshotIsSavedBeforeItsRelativeLinkAndSurvivesFailedNoteSave() throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: localDate(2026, 11, 3, 10, 0))
        let session = try MeetingTypedNotesSession(meeting: meeting)
        session.noteTime = { .recording(15) }
        let id = session.entries[0].id
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try session.addScreenshot(MeetingScreenshot.decode(png), to: id)
        let name = try XCTUnwrap(session.entries.first?.attachments.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: meeting.url.appendingPathComponent("attachments/" + name).path))
        XCTAssertTrue(try meeting.read(.notes).contains("attachments/" + name))
        try meeting.write("Changed outside", to: .notes)
        session.updateEntry(id: id, text: "Unsaved caption")
        XCTAssertNotNil(session.saveError)
        XCTAssertEqual(try meeting.read(.notes), "Changed outside")
        XCTAssertEqual(session.entries.first?.attachments, [name])
    }

    func testNotePositionFreezesThroughPausesAndIncludesAllResumeGaps() {
        var clock = RecordingClock(origin: HostTime(seconds: 100))
        clock.pause(at: HostTime(seconds: 110))
        XCTAssertEqual(clock.notePosition(at: HostTime(seconds: 120)), 10)
        clock.resume(at: HostTime(seconds: 130))
        XCTAssertEqual(clock.notePosition(at: HostTime(seconds: 135)), 18)
        clock.pause(at: HostTime(seconds: 140))
        XCTAssertEqual(clock.notePosition(at: HostTime(seconds: 150)), 23)
        clock.resume(at: HostTime(seconds: 160))
        XCTAssertEqual(clock.notePosition(at: HostTime(seconds: 165)), 31)
    }
}
