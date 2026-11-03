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

    func testTheWindowIsTitledWithTheDisplayTitleAndNativeEditingSaves() throws {
        let meeting = try meeting()
        let session = try MeetingTypedNotesSession(meeting: meeting)
        let editor = MeetingTypedNotesHost(session: session, requestUpdate: {},
                                                       activation: .fake(), present: { _ in })
        editor.show()
        defer { editor.close() }
        let window = try XCTUnwrap(editor.window)
        let field = try XCTUnwrap(descendants(try XCTUnwrap(window.contentView)).compactMap { $0 as? NSTextView }.first)
        XCTAssertEqual(window.title, "Release planning")

        field.insertText("Mira owns the release checklist.", replacementRange: NSRange(location: 0, length: 0))

        XCTAssertEqual(MeetingNoteDocument.parse(try meeting.read(.notes)).map(\.text), ["Mira owns the release checklist."])
    }

    func testUpdateButtonUsesItsBoundSessionAndTracksGenerationState() throws {
        let meeting = try meeting()
        try meeting.write("# Transcript", to: .transcript)
        try meeting.write("# Summary", to: .summary)
        let session = try MeetingTypedNotesSession(meeting: meeting)
        var requests = 0
        let editor = MeetingTypedNotesHost(session: session, requestUpdate: { requests += 1 },
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
        session.setFirstRow("Later action")
        XCTAssertFalse(update.isEnabled)
        session.context = { (.idle, .updated(snapshot: "")) }
        XCTAssertTrue(update.isEnabled)
        XCTAssertTrue(session.summaryMessage.contains("changed"))
    }

    func testClosingAndReopeningAnUnsavedWindowKeepsTheDraftAndSharedActivation() throws {
        let meeting = try meeting()
        let session = try MeetingTypedNotesSession(meeting: meeting)
        var policies: [NSApplication.ActivationPolicy] = []
        let editor = MeetingTypedNotesHost(session: session, requestUpdate: {},
                                                       activation: .fake(setPolicy: { policies.append($0) }), present: { _ in })
        editor.show()
        session.setFirstRow(String(repeating: "x", count: MeetingTypedNotesFile.maximumBytes + 1))
        XCTAssertTrue(session.hasUnsavedChanges)
        editor.close()
        editor.show()
        XCTAssertEqual(session.firstRowText?.count, MeetingTypedNotesFile.maximumBytes + 1)
        XCTAssertEqual(policies, [.regular, .accessory, .regular])
        editor.close()
    }

    func testFailedSaveRetainsDraftAndReloadRequiresConfirmation() throws {
        let meeting = try meeting()
        let session = try MeetingTypedNotesSession(meeting: meeting)
        var allowReload = false
        var confirmations = 0
        let editor = MeetingTypedNotesHost(session: session, requestUpdate: {}, activation: .fake(),
                                           present: { _ in }, confirmReload: { _ in
            confirmations += 1
            return allowReload
        })
        editor.show()
        defer { editor.close() }
        let content = try XCTUnwrap(editor.window?.contentView)
        let field = try XCTUnwrap(descendants(content).compactMap { $0 as? NSTextView }.first)
        try meeting.write("External notes", to: .notes)
        field.insertText("My draft", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(field.string, "My draft")
        let buttons = descendants(content).compactMap { $0 as? NSButton }
        let retry = try XCTUnwrap(buttons.first { $0.title == "Retry save" })
        let reload = try XCTUnwrap(buttons.first { $0.title == "Reload saved notes" })
        XCTAssertFalse(retry.isHidden)
        retry.performClick(nil)
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(try meeting.read(.notes), "External notes")
        reload.performClick(nil)
        XCTAssertEqual(confirmations, 1)
        XCTAssertEqual(field.string, "My draft")
        allowReload = true
        reload.performClick(nil)
        XCTAssertEqual(confirmations, 2)
        XCTAssertFalse(session.hasUnsavedChanges)
        let reloaded = descendants(content).compactMap { $0 as? NSTextView }
        XCTAssertEqual(reloaded.map(\.string), ["External notes"])
        XCTAssertTrue(retry.isHidden)
    }

    func testDetachingSharedViewReleasesActivationWithoutClosingItsSession() throws {
        let session = try MeetingTypedNotesSession(meeting: meeting())
        var policies: [NSApplication.ActivationPolicy] = []
        let view = MeetingTypedNotesView(session: session, requestUpdate: {})
        let host = MeetingTypedNotesHost(view: view, activation: .fake(setPolicy: { policies.append($0) }),
                                        present: { _ in })
        var closes = 0
        host.onClose = { closes += 1 }
        host.show()
        host.detach()
        XCTAssertEqual(policies, [.regular, .accessory])
        XCTAssertEqual(closes, 0)
        XCTAssertNil(view.window)
        let next = MeetingTypedNotesHost(view: view, activation: .fake(), present: { _ in })
        next.show()
        defer { next.close() }
        session.setFirstRow("Retained session")
        XCTAssertEqual(descendants(view).compactMap { $0 as? NSTextView }.map(\.string), ["Retained session"])
    }

    /// Writes pictures of the notes window when KUKA_TYPED_NOTES_SNAPSHOTS names a folder:
    ///
    ///     TEST_RUNNER_KUKA_TYPED_NOTES_SNAPSHOTS="$HOME/notes-snapshots" xcodebuild -project KuKa.xcodeproj \
    ///         -scheme KuKa test -only-testing:KuKaTests/MeetingTypedNotesWindowTests/testNativeSnapshots
    func testNativeSnapshots() throws {
        guard let path = ProcessInfo.processInfo.environment["KUKA_TYPED_NOTES_SNAPSHOTS"] else {
            throw XCTSkip("Set KUKA_TYPED_NOTES_SNAPSHOTS for native notes window images.")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = try MeetingTypedNotesSession(meeting: meeting())
        session.setFirstRow("# Decisions\n\nShip the release on Monday after QA signs off.\n\n# Action items\n\n- Mira: send the release checklist.\n- Jon: confirm the rollback steps.\n\n# Questions\n\nDo we need a separate notice for the pilot group?")
        let editor = MeetingTypedNotesHost(session: session, requestUpdate: {},
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
                session.setFirstRow("My unsaved draft. Mira owns the checklist.")
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
        session.setFirstRow("A saved note")
        session.context = { (.idle, .summarizing(snapshot: "Earlier note")) }
        let editor = MeetingTypedNotesHost(session: session, requestUpdate: {},
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
