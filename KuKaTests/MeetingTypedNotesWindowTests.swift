import AppKit
import XCTest
@testable import KuKa

@MainActor
final class MeetingTypedNotesWindowTests: XCTestCase {
    private func meeting() throws -> MeetingFolder {
        let meeting = try MeetingFolder.create(in: try makeTemporaryDirectory(), startingAt: localDate(2026, 10, 30, 10, 0))
        try meeting.saveDisplayTitle("Release planning")
        return meeting
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    func testNativeEditingSavesAndUndoRestoresThePreviousSavedText() async throws {
        let meeting = try meeting()
        let session = try MeetingTypedNotesSession(meeting: meeting)
        let editor = MeetingTypedNotesWindowController(session: session, requestUpdate: {},
                                                       activation: .fake(), present: { _ in })
        editor.show()
        defer { editor.close() }
        let window = try XCTUnwrap(editor.window)
        let field = try XCTUnwrap(descendants(try XCTUnwrap(window.contentView)).compactMap { $0 as? NSTextView }.first)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.title, "Release planning")
        XCTAssertFalse(field.isRichText)
        XCTAssertTrue(field.allowsUndo)
        XCTAssertEqual(field.accessibilityLabel(), "Meeting notes")

        field.insertText("Mira owns the release checklist.", replacementRange: NSRange(location: 0, length: 0))

        XCTAssertEqual(try meeting.read(.notes), "Mira owns the release checklist.")
        XCTAssertTrue(try XCTUnwrap(field.undoManager).canUndo)
        if let undo = field.undoManager, undo.groupingLevel > 0 { undo.endUndoGrouping() }
        XCTAssertTrue(field.undoManager === window.undoManager)
        window.undoManager?.undo()
        XCTAssertEqual(field.string, "", "native undo must change the text view before autosave")
        await waitUntil { session.text.isEmpty }
        XCTAssertEqual(session.text, "")
        XCTAssertEqual(try meeting.read(.notes), "")
        window.undoManager?.redo()
        XCTAssertEqual(session.text, "Mira owns the release checklist.")
        XCTAssertEqual(try meeting.read(.notes), "Mira owns the release checklist.")
    }

    func testNativeCopyAndPasteUsesPlainTextAndSavesTheResult() throws {
        let meeting = try meeting()
        let session = try MeetingTypedNotesSession(meeting: meeting)
        let editor = MeetingTypedNotesWindowController(session: session, requestUpdate: {},
                                                       activation: .fake(), present: { _ in })
        editor.show()
        defer { editor.close() }
        let field = try XCTUnwrap(descendants(try XCTUnwrap(editor.window?.contentView)).compactMap { $0 as? NSTextView }.first)
        field.insertText("Action", replacementRange: NSRange(location: 0, length: 0))
        field.setSelectedRange(NSRange(location: 0, length: 6))
        XCTAssertEqual(field.selectedRange(), NSRange(location: 0, length: 6))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(field.writeSelection(to: pasteboard, types: field.writablePasteboardTypes))
        XCTAssertEqual(pasteboard.string(forType: .string), "Action")
        field.setSelectedRange(NSRange(location: 6, length: 0))
        XCTAssertTrue(field.readSelection(from: pasteboard, type: .string))
        XCTAssertEqual(try meeting.read(.notes), "ActionAction")
    }

    func testUpdateButtonUsesItsBoundSessionAndTracksGenerationState() throws {
        let meeting = try meeting()
        try meeting.write("# Transcript", to: .transcript)
        try meeting.write("# Summary", to: .summary)
        let session = try MeetingTypedNotesSession(meeting: meeting)
        var requests = 0
        let editor = MeetingTypedNotesWindowController(session: session, requestUpdate: { requests += 1 },
                                                       activation: .fake(), present: { _ in })
        editor.show()
        defer { editor.close() }
        let buttons = descendants(try XCTUnwrap(editor.window?.contentView)).compactMap { $0 as? NSButton }
        let update = try XCTUnwrap(buttons.first { $0.title == "Update summary" })
        XCTAssertTrue(update.isEnabled)
        update.performClick(nil)
        XCTAssertEqual(requests, 1)
        session.context = { (.idle, .summarizing(snapshot: "")) }
        XCTAssertFalse(update.isEnabled)
        session.edit("Later action")
        XCTAssertFalse(update.isEnabled)
        session.context = { (.idle, .updated(snapshot: "")) }
        XCTAssertTrue(update.isEnabled)
        XCTAssertTrue(session.summaryMessage.contains("changed"))
    }

    func testClosingAndReopeningAnUnsavedWindowKeepsTheDraftAndSharedActivation() throws {
        let meeting = try meeting()
        let session = try MeetingTypedNotesSession(meeting: meeting)
        var policies: [NSApplication.ActivationPolicy] = []
        let editor = MeetingTypedNotesWindowController(session: session, requestUpdate: {},
                                                       activation: .fake(setPolicy: { policies.append($0) }), present: { _ in })
        editor.show()
        session.edit(String(repeating: "x", count: MeetingTypedNotesFile.maximumBytes + 1))
        XCTAssertTrue(session.hasUnsavedChanges)
        editor.close()
        editor.show()
        XCTAssertEqual(session.text.count, MeetingTypedNotesFile.maximumBytes + 1)
        XCTAssertEqual(policies, [.regular, .accessory, .regular])
        editor.close()
    }

    func testNativeSnapshots() throws {
        guard let path = ProcessInfo.processInfo.environment["KUKA_TYPED_NOTES_SNAPSHOTS"] else {
            throw XCTSkip("Set KUKA_TYPED_NOTES_SNAPSHOTS for native notes window images.")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = try MeetingTypedNotesSession(meeting: meeting())
        session.edit("# Decisions\n\nShip the release on Monday after QA signs off.\n\n# Action items\n\n- Mira: send the release checklist.\n- Jon: confirm the rollback steps.\n\n# Questions\n\nDo we need a separate notice for the pilot group?")
        let editor = MeetingTypedNotesWindowController(session: session, requestUpdate: {},
                                                       activation: .fake(), present: { _ in })
        editor.show()
        defer { editor.close() }
        let window = try XCTUnwrap(editor.window)
        let view = try XCTUnwrap(window.contentView)
        window.orderFront(nil)
        for (name, appearance, size, phase, state, saveError) in [
            ("recording-light", NSAppearance.Name.aqua, NSSize(width: 680, height: 560), RecorderPhase.recording, TypedNotesSummaryState.idle, false),
            ("paused-dark", .darkAqua, NSSize(width: 680, height: 560), .paused, .idle, false),
            ("updated-light", .aqua, NSSize(width: 680, height: 560), .idle, .updated(snapshot: session.text), false),
            ("minimum-dark", .darkAqua, NSSize(width: 460, height: 330), .idle, .summarizing(snapshot: "Earlier notes"), false),
            ("save-error-minimum-light", .aqua, NSSize(width: 460, height: 330), .idle, .waitingForSave, true),
        ] {
            if case .updated = state {
                try session.meeting.write("# Transcript", to: .transcript)
                try session.meeting.write("# Summary", to: .summary)
            }
            if saveError {
                try session.meeting.write("Changed in another editor", to: .notes)
                session.edit("My unsaved draft. Mira owns the checklist.")
            }
            window.appearance = NSAppearance(named: appearance)
            window.setContentSize(size)
            session.context = { (phase, state) }
            view.layoutSubtreeIfNeeded()
            view.needsDisplay = true
            view.displayIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            window.appearance?.performAsCurrentDrawingAppearance {
                view.cacheDisplay(in: view.bounds, to: bitmap)
            }
            let context = try XCTUnwrap(CGContext(data: nil, width: bitmap.pixelsWide, height: bitmap.pixelsHigh,
                                                  bitsPerComponent: 8, bytesPerRow: 0,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            let pixels = CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
            window.appearance?.performAsCurrentDrawingAppearance {
                context.setFillColor(NSColor.windowBackgroundColor.cgColor)
                context.fill(pixels)
            }
            context.setBlendMode(.normal)
            context.draw(try XCTUnwrap(bitmap.cgImage), in: pixels)
            let image = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
            try XCTUnwrap(image.representation(using: .png, properties: [:]))
                .write(to: directory.appendingPathComponent(name + ".png"))
        }
    }

    func testMinimumWidthKeepsLongStatusAndEditorInsideTheWindow() throws {
        let session = try MeetingTypedNotesSession(meeting: meeting())
        session.edit("A saved note")
        session.context = { (.idle, .summarizing(snapshot: "Earlier note")) }
        let editor = MeetingTypedNotesWindowController(session: session, requestUpdate: {},
                                                       activation: .fake(), present: { _ in })
        editor.show()
        defer { editor.close() }
        let window = try XCTUnwrap(editor.window)
        window.setContentSize(NSSize(width: 460, height: 330))
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        XCTAssertEqual(content.bounds.width, 460)
        for label in descendants(content).compactMap({ $0 as? NSTextField }) {
            let frame = content.convert(label.bounds, from: label)
            XCTAssertGreaterThanOrEqual(frame.minX, 0)
            XCTAssertLessThanOrEqual(frame.maxX, 460)
        }
    }
}
