import AppKit
import XCTest
@testable import Mysli

@MainActor
final class MeetingCombinedPanelTests: XCTestCase {
    func testNativeTypingSplitAndTypingUndoAndRedoAsSeparateActions() throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: localDate(2026, 11, 3, 10, 0))
        let session = try MeetingTypedNotesSession(meeting: meeting)
        let view = MeetingTypedNotesView(session: session, requestUpdate: {})
        let host = MeetingTypedNotesHost(view: view)
        defer { host.detach() }
        host.show()
        session.undoManager.groupsByEvent = false
        func event(_ action: () -> Void) {
            session.undoManager.beginUndoGrouping()
            action()
            session.undoManager.endUndoGrouping()
        }
        let first = try XCTUnwrap(descendants(view).compactMap { $0 as? NoteRowTextView }.first)
        event { first.insertText("First", replacementRange: first.selectedRange()) }
        let enter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: host.window!.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36))
        event { first.keyDown(with: enter) }
        let second = try XCTUnwrap(descendants(view).compactMap { $0 as? NoteRowTextView }.last)
        event { second.insertText("Second", replacementRange: second.selectedRange()) }

        session.undoManager.undo()
        XCTAssertEqual(session.entries.map(\.text), ["First", ""])
        session.undoManager.undo()
        XCTAssertEqual(session.entries.map(\.text), ["First"])
        session.undoManager.undo()
        XCTAssertEqual(try MeetingTypedNotesFile.read(in: meeting), "")
        session.undoManager.redo()
        session.undoManager.redo()
        session.undoManager.redo()
        XCTAssertEqual(session.entries.map(\.text), ["First", "Second"])
        XCTAssertEqual(MeetingNoteDocument.parse(try meeting.read(.notes)).map(\.text), ["First", "Second"])
        XCTAssertTrue(descendants(view).contains { $0 === second })
    }

    func testAppendingRowKeepsExistingScreenshotViewAndEditor() throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: localDate(2026, 11, 3, 10, 0))
        let session = try MeetingTypedNotesSession(meeting: meeting)
        let view = MeetingTypedNotesView(session: session, requestUpdate: {})
        let host = MeetingTypedNotesHost(view: view)
        defer { host.detach() }
        host.show()
        let editor = try XCTUnwrap(descendants(view).compactMap { $0 as? NSTextView }.first)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = try MeetingScreenshot.decode(XCTUnwrap(bitmap.representation(using: .png, properties: [:])))
        try session.addScreenshot(image, to: XCTUnwrap(session.entries.first?.id))
        let preview = try XCTUnwrap(descendants(view).compactMap { $0 as? NSImageView }.first)
        XCTAssertNotNil(session.splitEntry(id: session.entries[0].id, selection: NSRange(location: 0, length: 0)))
        XCTAssertEqual(session.entries.count, 2)
        XCTAssertTrue(descendants(view).contains { $0 === preview })
        XCTAssertTrue(descendants(view).contains { $0 === editor })
    }

    func testNotesRemainAfterStopAndNoticeExpires() async throws {
        let root = try makeTemporaryDirectory()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = Settings(defaults: defaults, loginItem: FakeLoginItem())
        let live = FakeLiveTranscriber()
        var expire: (() -> Void)?
        let recorder = MeetingRecorder(
            permissions: PermissionsManager(isAccessibilityTrusted: { true }, hasScreenCaptureAccess: { true },
                                            microphoneAccess: { .granted }, requestMicrophoneAccess: { true }),
            root: { root }, capture: FakeMeetingAudioCapture(), liveTranscriber: live,
            notifier: FakeNotifier(), alertStartFailure: { _, _ in false },
            hostNow: { HostTime(seconds: 1_000) }, closeSavedNoticeLater: { expire = $0 })
        let panel = MeetingControlsPanel(recorder: recorder, settings: settings, screens: CombinedTestScreens(),
                                         displayOptions: { (true, true) })
        panel.bindRecorder()
        await recorder.toggleRecording()
        let meeting = try XCTUnwrap(recorder.activeMeeting)
        let session = try MeetingTypedNotesSession(meeting: meeting)
        session.noteTime = { recorder.noteTime(for: meeting) }
        let view = MeetingTypedNotesView(session: session, requestUpdate: {})
        var closed = 0
        panel.onCloseNotes = { closed += 1 }
        panel.attachNotes(view)
        let drawer = try XCTUnwrap(descendants(try XCTUnwrap(panel.contentView)).compactMap { $0 as? MeetingTranscriptDrawer }.first)
        XCTAssertFalse(drawer.isHidden)
        XCTAssertGreaterThan(drawer.frame.height, 0)
        live.send(.started)
        live.send(.result(LiveResult(track: .system, start: 0, end: 2,
                                    text: "We can start the work tomorrow.", isFinal: true, finalizedThrough: 2)))
        await waitUntil { recorder.livePreview?.rows.isEmpty == false }
        let editorBefore = try XCTUnwrap(descendants(view).compactMap { $0 as? NoteRowTextView }.first)
        editorBefore.insertText("Decisions and action items", replacementRange: editorBefore.selectedRange())
        editorBefore.setSelectedRange(NSRange(location: 3, length: 2))
        panel.cancelOperation(nil)
        XCTAssertEqual(panel.frame.height, 42)
        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(closed, 0)
        let notesButton = try XCTUnwrap(descendants(try XCTUnwrap(panel.contentView)).compactMap { $0 as? NSButton }
            .first { $0.accessibilityLabel() == "Write meeting notes" })
        notesButton.performClick(nil)
        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(editorBefore.selectedRange(), NSRange(location: 3, length: 2))
        XCTAssertTrue(editorBefore.undoManager?.canUndo == true)
        let transcriptButton = try XCTUnwrap(descendants(try XCTUnwrap(panel.contentView)).compactMap { $0 as? NSButton }
            .first { $0.accessibilityLabel() == "Hide live transcript" })
        transcriptButton.performClick(nil)
        XCTAssertTrue(view.isHidden)
        XCTAssertFalse(drawer.isHidden)
        XCTAssertEqual(closed, 0)
        notesButton.performClick(nil)
        panel.contentView?.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(panel.frame.width, 460)
        XCTAssertGreaterThan(editorBefore.visibleRect.width, 0)
        XCTAssertGreaterThan(editorBefore.visibleRect.height, 0)
        try capture(panel, name: "combined")
        recorder.stopRecording()
        expire?()
        try capture(panel, name: "after-stop")
        XCTAssertTrue(panel.isVisible)
        let grip = try XCTUnwrap(descendants(try XCTUnwrap(panel.contentView)).compactMap { $0 as? MeetingDrawerGrip }
            .first { $0.accessibilityLabel() == "Resize meeting notes" })
        XCTAssertFalse(grip.isHiddenOrHasHiddenAncestor)
        XCTAssertGreaterThan(grip.visibleRect.height, 0)
        let oldFrame = panel.frame
        grip.onBegan?()
        grip.onMoved?(CGSize(width: -100, height: -40))
        grip.onEnded?()
        XCTAssertGreaterThan(panel.frame.width, oldFrame.width)
        XCTAssertGreaterThan(panel.frame.height, oldFrame.height)
        XCTAssertTrue(descendants(try XCTUnwrap(panel.contentView)).contains { $0 === view })
        let editor = try XCTUnwrap(descendants(view).compactMap { $0 as? NoteRowTextView }.first)
        editor.insertText(" after stop", replacementRange: editor.selectedRange())
        XCTAssertTrue(session.entries.first?.text.contains("after stop") == true)
        panel.cancelOperation(nil)
        XCTAssertTrue(view.isHidden)
        panel.detachNotes()
        XCTAssertFalse(view.isHidden)
        XCTAssertFalse(descendants(try XCTUnwrap(panel.contentView)).contains { $0 === view })
        XCTAssertEqual(closed, 0)
        panel.close()
    }

    func testExplicitCloseReleasesNotesOnce() async throws {
        let root = try makeTemporaryDirectory()
        var expire: (() -> Void)?
        let recorder = MeetingRecorder(
            permissions: PermissionsManager(isAccessibilityTrusted: { true }, hasScreenCaptureAccess: { true },
                                            microphoneAccess: { .granted }, requestMicrophoneAccess: { true }),
            root: { root }, capture: FakeMeetingAudioCapture(), liveTranscriber: FakeLiveTranscriber(),
            notifier: FakeNotifier(), alertStartFailure: { _, _ in false },
            closeSavedNoticeLater: { expire = $0 })
        let panel = MeetingControlsPanel(recorder: recorder,
                                        settings: Settings(defaults: UserDefaults(suiteName: UUID().uuidString)!, loginItem: FakeLoginItem()),
                                        screens: CombinedTestScreens(), displayOptions: { (true, true) })
        panel.bindRecorder()
        await recorder.toggleRecording()
        let view = MeetingTypedNotesView(session: try MeetingTypedNotesSession(meeting: XCTUnwrap(recorder.activeMeeting)), requestUpdate: {})
        var closed = 0
        panel.onCloseNotes = {
            closed += 1
            panel.detachNotes()
        }
        panel.attachNotes(view)
        recorder.stopRecording()
        expire?()
        let close = try XCTUnwrap(descendants(try XCTUnwrap(panel.contentView)).compactMap { $0 as? NSButton }
            .first { $0.accessibilityLabel() == "Close" })
        close.performClick(nil)
        close.performClick(nil)
        XCTAssertEqual(closed, 1)
        XCTAssertFalse(panel.isVisible)
        panel.close()
    }
    func testEditingAndUndoSurviveRehostingTheSameView() throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: localDate(2026, 11, 3, 10, 0))
        let session = try MeetingTypedNotesSession(meeting: meeting)
        session.noteTime = { .recording(12) }
        let view = MeetingTypedNotesView(session: session, requestUpdate: {})
        let first = MeetingTypedNotesHost(view: view)
        first.showWindow(nil)
        let editor = try XCTUnwrap(descendants(view).compactMap { $0 as? NSTextView }.first)
        first.window?.makeFirstResponder(editor)
        editor.insertText("Decision", replacementRange: editor.selectedRange())
        XCTAssertTrue(descendants(view).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "0:12" })
        XCTAssertEqual(session.entries.first?.text, "Decision")
        XCTAssertEqual(MeetingNoteDocument.parse(try meeting.read(.notes)).first?.text, "Decision")
        editor.setSelectedRange(NSRange(location: 3, length: 2))
        first.detach()
        let second = MeetingTypedNotesHost(view: view)
        second.showWindow(nil)
        second.window?.makeFirstResponder(editor)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 3, length: 2))
        editor.undoManager?.undo()
        XCTAssertEqual(session.entries.first?.text, "")
        XCTAssertEqual(try MeetingTypedNotesFile.read(in: meeting), "")
        XCTAssertEqual(session.entries.first?.time, .recording(12))
        second.detach()
    }

    func testShiftEnterAddsALineBreakInTheSameRow() throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: localDate(2026, 11, 3, 10, 0))
        let session = try MeetingTypedNotesSession(meeting: meeting)
        let view = MeetingTypedNotesView(session: session, requestUpdate: {})
        let host = MeetingTypedNotesHost(view: view)
        host.showWindow(nil)
        defer { host.detach() }
        let editor = try XCTUnwrap(descendants(view).compactMap { $0 as? NoteRowTextView }.first)
        editor.insertText("First", replacementRange: editor.selectedRange())
        let shiftEnter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0,
                                                        windowNumber: host.window?.windowNumber ?? 0, context: nil,
                                                        characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        editor.keyDown(with: shiftEnter)
        XCTAssertEqual(session.entries.map(\.text), ["First\n"])
    }

    func testPastingScreenshotSavesImageAndShowsPreview() throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: localDate(2026, 11, 3, 10, 0))
        let session = try MeetingTypedNotesSession(meeting: meeting)
        let view = MeetingTypedNotesView(session: session, requestUpdate: {})
        let host = MeetingTypedNotesHost(view: view)
        host.showWindow(nil)
        let editor = try XCTUnwrap(descendants(view).compactMap { $0 as? NoteRowTextView }.first)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let board = NSPasteboard.withUniqueName()
        board.declareTypes([.png], owner: nil)
        board.setData(png, forType: .png)
        XCTAssertTrue(editor.pasteImage(from: board))
        let name = try XCTUnwrap(session.entries.first?.attachments.first)
        XCTAssertNotNil(MeetingScreenshotStore(meeting: meeting).read(named: name))
        XCTAssertTrue(try meeting.read(.notes).contains("attachments/" + name))
        XCTAssertFalse(descendants(view).compactMap { $0 as? NSImageView }.isEmpty)
        editor.undoManager?.undo()
        XCTAssertEqual(session.entries.first?.attachments, [])
        XCTAssertNotNil(MeetingScreenshotStore(meeting: meeting).read(named: name))
        board.releaseGlobally()
        host.detach()
    }

    func testDroppingFileImportsPngIntoOriginalMeeting() throws {
        let root = try makeTemporaryDirectory()
        let meeting = try MeetingFolder.create(in: root, startingAt: localDate(2026, 11, 3, 10, 0))
        let session = try MeetingTypedNotesSession(meeting: meeting)
        let view = MeetingTypedNotesView(session: session, requestUpdate: {})
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let source = root.appendingPathComponent("dragged.png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: source)
        let board = NSPasteboard.withUniqueName()
        board.writeObjects([source as NSURL])
        XCTAssertTrue(view.dropImage(from: board))
        let name = try XCTUnwrap(session.entries.first?.attachments.first)
        XCTAssertNotNil(MeetingScreenshotStore(meeting: meeting).read(named: name))
        XCTAssertTrue(try meeting.read(.notes).contains("attachments/" + name))
        board.releaseGlobally()
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func capture(_ panel: NSWindow, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["MYSLI_COMBINED_SNAPSHOTS"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let view = try XCTUnwrap(panel.contentView)
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            panel.appearance = NSAppearance(named: appearance)
            view.layoutSubtreeIfNeeded()
            view.needsDisplay = true
            view.displayIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            panel.appearance?.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: bitmap) }
            let image = NSImage(size: view.bounds.size, flipped: false) { rect in
                (appearance == .darkAqua ? NSColor.darkGray : NSColor.lightGray).setFill()
                rect.fill()
                bitmap.draw(in: rect)
                return true
            }
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let data = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            try data.write(to: directory.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }
}

private final class CombinedTestScreens: Screens {
    let all = [ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                              visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))]
    let mainIndex: Int? = 0
}
