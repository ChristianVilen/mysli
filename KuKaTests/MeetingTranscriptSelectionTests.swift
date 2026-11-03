import AppKit
import XCTest
@testable import KuKa

@MainActor
final class MeetingTranscriptSelectionTests: XCTestCase {
    func testRoundedPillFillDoesNotCoverContentOutsideItsBounds() throws {
        let backdrop = TranscriptTestBackdrop(frame: NSRect(x: 0, y: 0, width: 100, height: 60))
        let fill = MeetingPanelFill(color: .red, radius: 18, rounded: .top)
        fill.frame = NSRect(x: 0, y: 20, width: 100, height: 20)
        backdrop.addSubview(fill)
        let bitmap = try XCTUnwrap(backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds))
        backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
        let scale = bitmap.pixelsHigh / 60
        for y in [10, 50] {
            let color = try XCTUnwrap(bitmap.colorAt(x: 50 * scale, y: y * scale)?.usingColorSpace(.deviceRGB))
            XCTAssertGreaterThan(color.greenComponent, 0.9, "Pill fill must not paint outside its 20-point height.")
        }
    }

    func testTranscriptHeaderFitsItsDrawerAndDoesNotOverlapTheTextViewport() throws {
        let drawer = MeetingTranscriptDrawer(mouseLocation: { .zero }, reduceMotion: { true })
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 190),
                             styleMask: [.nonactivatingPanel], backing: .buffered, defer: true)
        window.contentView = drawer
        drawer.isHidden = false
        drawer.showMessage(for: .live)
        drawer.showRows([speech(2, .them, "We can start the work tomorrow.")])
        drawer.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants) }
        let views = descendants(drawer)
        let label = try XCTUnwrap(views.compactMap { $0 as? NSTextField }.first { $0.stringValue == "Live transcript" })
        let rect = drawer.convert(label.bounds, from: label)
        XCTAssertTrue(drawer.bounds.contains(rect), "Header \(rect) must fit inside \(drawer.bounds).")
        let scroll = try XCTUnwrap(views.compactMap { $0 as? NSScrollView }.first)
        XCTAssertFalse(rect.intersects(drawer.convert(scroll.bounds, from: scroll)))
    }

    func testReducedMotionOpensTranscriptAtFullOpacityImmediately() {
        let drawer = MeetingTranscriptDrawer(mouseLocation: { .zero }, reduceMotion: { true })
        drawer.opened()
        XCTAssertEqual(drawer.alphaValue, 1)
    }

    private func textView(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView { return text }
        return view.subviews.lazy.compactMap { self.textView(in: $0) }.first
    }

    private func speech(_ time: TimeInterval, _ speaker: Speaker, _ text: String, final: Bool = true) -> LiveRow {
        LiveRow(at: time, content: .speech(speaker, text: text, isFinal: final))
    }

    func testUnchangedSelectionSurvivesAppendingAndReplacingDraftText() throws {
        let drawer = MeetingTranscriptDrawer(mouseLocation: { .zero }, reduceMotion: { true })
        let committed = speech(1, .them, "Keep thirty days.")
        drawer.showRows([committed, speech(3, .me, "Mira", final: false)])
        let text = try XCTUnwrap(textView(in: drawer))
        let selection = (text.string as NSString).range(of: "Keep thirty days.")
        text.setSelectedRange(selection)

        drawer.showRows([committed, speech(3, .me, "Mira will check", final: false)])
        XCTAssertEqual(text.selectedRange(), selection)
        XCTAssertEqual((text.string as NSString).substring(with: text.selectedRange()), "Keep thirty days.")

        drawer.showRows([committed, speech(3, .me, "Mira will check."), speech(6, .them, "Thanks.")])
        XCTAssertEqual(text.selectedRange(), selection)
    }

    func testEveryMessageHasATimestampEvenWithTheSameSpeaker() throws {
        let drawer = MeetingTranscriptDrawer(mouseLocation: { .zero }, reduceMotion: { true })
        drawer.showRows([speech(1, .me, "Yeah."), speech(3, .me, "Okay.")])
        let text = try XCTUnwrap(textView(in: drawer))
        XCTAssertEqual(text.string, "0:01  Me\nYeah.\n\n0:03  Me\nOkay.\n\n")
    }
}

private final class TranscriptTestBackdrop: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()
    }
}
