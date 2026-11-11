import AppKit
import XCTest
@testable import Mysli

// TEST_RUNNER_MYSLI_DICTATION_PASTEBOARD_PROBE=1 xcodebuild -project Mysli.xcodeproj -scheme Mysli test -only-testing:MysliTests/RealDictationPasteboardTests
@MainActor
final class RealDictationPasteboardTests: XCTestCase {
    func testNamedPasteboardOwnershipCountsAndCompleteRepresentations() throws {
        guard ProcessInfo.processInfo.environment["MYSLI_DICTATION_PASTEBOARD_PROBE"] == "1" else {
            throw XCTSkip("Opt-in synthetic named pasteboard only.")
        }
        let named = NSPasteboard(name: .init("mysli-dictation-probe-\(UUID().uuidString)"))
        defer { named.releaseGlobally() }
        let board = NativeDictationPasteboard(pasteboard: named)
        let content: DictationPasteSnapshot = [[.string: Data("synthetic".utf8), .init("test.unknown"): Data([0, 255])], [.html: Data([4])]]
        let written = try board.replace(with: content)
        XCTAssertTrue(written.succeeded)
        XCTAssertEqual(board.changeCount, written.changeCount)
        let read = try board.items.map { item in
            try Dictionary(uniqueKeysWithValues: item.types.map { ($0, try XCTUnwrap(item.data(forType: $0))) })
        }
        XCTAssertEqual(read, content)
        let transient = try board.replace(with: [[.string: Data("private".utf8), .init("org.nspasteboard.TransientType"): Data()]])
        XCTAssertTrue(transient.succeeded)
        XCTAssertEqual(board.changeCount, transient.changeCount)
        let restored = try board.replace(with: read)
        XCTAssertTrue(restored.succeeded)
        XCTAssertEqual(board.changeCount, restored.changeCount)
        XCTAssertEqual(named.pasteboardItems?.count, 2)
        XCTAssertEqual(named.pasteboardItems?.first?.data(forType: .init("test.unknown")), Data([0, 255]))
        XCTAssertEqual(named.pasteboardItems?.last?.data(forType: .html), Data([4]))
        let empty = try board.replace(with: [])
        XCTAssertTrue(empty.succeeded)
        XCTAssertEqual(board.changeCount, empty.changeCount)
        XCTAssertTrue(try board.items.isEmpty)
    }
}
