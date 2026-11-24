import AppKit
import XCTest
@testable import Mysli

@MainActor
final class NoteRowTextViewTests: XCTestCase {
    func testImageOnlyClipboardEnablesPasteAndAttachesScreenshot() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var readPrivatePasteboard = false
        let editor = NoteRowTextView(entryID: UUID(), pasteboard: {
            readPrivatePasteboard = true
            return board
        })
        editor.isRichText = false
        editor.string = "Decision"
        let paste = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 3,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))

        for (type, format) in [(NSPasteboard.PasteboardType.png, NSBitmapImageRep.FileType.png), (.tiff, .tiff)] {
            board.declareTypes([type], owner: nil)
            XCTAssertTrue(board.setData(try XCTUnwrap(bitmap.representation(using: format, properties: [:])), forType: type))
            var screenshots: [MeetingScreenshot] = []
            editor.onImage = { screenshots.append($0) }

            readPrivatePasteboard = false
            XCTAssertTrue(editor.validateMenuItem(paste), type.rawValue)
            XCTAssertTrue(readPrivatePasteboard, "Paste validation must use the supplied pasteboard")
            editor.paste(paste)

            XCTAssertEqual(screenshots.count, 1)
            let image = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(screenshots.first).png))
            XCTAssertEqual(image.pixelsWide, 2)
            XCTAssertEqual(image.pixelsHigh, 3)
            XCTAssertEqual(editor.string, "Decision")
        }
    }
}
