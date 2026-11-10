import XCTest
import AppKit
@testable import Mysli

@MainActor
final class DictationPanelTests: XCTestCase {
    func testPanelNeverTakesFocusAndPlacesWithinChosenScreen() {
        let panel = DictationPanel(screenFrame: { NSRect(x: 900, y: 40, width: 1200, height: 800) },
                                   reduceTransparency: { true })
        defer { panel.close() }
        panel.show(.listening(level: 0.6, warning: false))
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertEqual(panel.frame.midX, 1500)
        XCTAssertGreaterThan(panel.frame.minY, 40)
        XCTAssertEqual(panel.meter.doubleValue, 0.6, accuracy: 0.001)
        XCTAssertTrue(panel.isVisible)
        panel.show(.idle)
        XCTAssertFalse(panel.isVisible)
    }

    func testNoticesDifferByShapeAndHaveNoVisibleText() {
        let panel = DictationPanel(screenFrame: { NSRect(x: 0, y: 0, width: 1200, height: 800) },
                                   reduceTransparency: { true })
        defer { panel.close() }
        panel.show(.unpolished)
        let unpolished = panel.stateSymbol
        panel.show(.error)
        XCTAssertNotEqual(panel.stateSymbol, unpolished)
        func labels(_ view: NSView) -> [NSTextField] {
            view.subviews.flatMap { ($0 as? NSTextField).map { [$0] } ?? labels($0) }
        }
        XCTAssertTrue(labels(panel.contentView!).isEmpty)
    }

    // Opt-in native renders use only synthetic state. Set TEST_RUNNER_MYSLI_DICTATION_SNAPSHOTS for xcodebuild.
    func testWritesPictures() throws {
        guard let path = ProcessInfo.processInfo.environment["MYSLI_DICTATION_SNAPSHOTS"] else {
            throw XCTSkip("Set MYSLI_DICTATION_SNAPSHOTS to write native renders.")
        }
        let folder = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for solid in [false, true] {
            let panel = DictationPanel(screenFrame: { NSRect(x: 0, y: 0, width: 1200, height: 800) },
                                       reduceTransparency: { solid })
            defer { panel.close() }
            for (name, state) in [("listen", DictationPresentation.listening(level: 0.6, warning: false)),
                                  ("limit", .listening(level: 0.8, warning: true)), ("progress", .polishing),
                                  ("fallback", .unpolished), ("error", .error)] {
                panel.show(state)
                for (theme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    panel.appearance = NSAppearance(named: appearance)
                    panel.show(state)
                    let view = try XCTUnwrap(panel.contentView)
                    view.layoutSubtreeIfNeeded()
                    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    try data.write(to: folder.appendingPathComponent("\(name)-\(theme)-\(solid ? "solid" : "glass").png"))
                }
            }
        }
    }
}
