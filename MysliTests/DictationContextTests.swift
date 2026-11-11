import XCTest
@testable import Mysli

final class DictationContextTests: XCTestCase {
    @MainActor
    func testFinalTextDoesNotReadAppOrCursorContext() async {
        let ax = ContextAX()
        var appReads = 0
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let context = DictationContext(knownWords: KnownWordsFile(url: { url }), nearbyText: { true },
            frontApp: { appReads += 1; return .init(pid: 123, name: "Editor") }, accessibility: ax)
        for (heard, expected) in [("git push", "git push"), ("new line", "\n")] {
            guard case .final(let text)? = await context.prepareText(heard) else {
                return XCTFail("Expected final local text")
            }
            XCTAssertEqual(text.value, expected)
        }
        XCTAssertEqual(appReads, 0)
        XCTAssertEqual(ax.focusReads, 0)
    }

    func testNativeProtectionQueryUsesPublicAttributeAndRequiresBoolean() {
        let cases: [(CFTypeRef?, Bool?)] = [(kCFBooleanFalse, false), (kCFBooleanTrue, true), ("false" as CFString, nil), (nil, nil)]
        for (value, expected) in cases {
            let node = DictationAXNode(attribute: { name in
                name == "AXContainsProtectedContent" ? value : nil
            })
            XCTAssertEqual(node.protected, expected)
        }
    }

    func testRangeReadUsesSelectionStartAndRejectsUnsafeFields() {
        let node = ContextNode()
        node.selection = CFRange(location: 700, length: 20)
        node.text = String(repeating: "a", count: 500)
        XCTAssertEqual(DictationContext.precedingText(in: node), String(repeating: "a", count: 499))
        XCTAssertEqual(node.ranges.map(\.location), [200])
        XCTAssertEqual(node.ranges.map(\.length), [500])
        for protection in [true, nil] as [Bool?] {
            node.protected = protection
            node.ranges = []
            node.selectionReads = 0
            XCTAssertNil(DictationContext.precedingText(in: node))
            XCTAssertTrue(node.ranges.isEmpty)
            XCTAssertEqual(node.selectionReads, 0)
        }
        node.protected = false
        node.subrole = "AXSecureTextField"
        XCTAssertNil(DictationContext.precedingText(in: node))
        XCTAssertTrue(node.ranges.isEmpty)
        XCTAssertEqual(node.selectionReads, 0)
    }

    func testMalformedRangesAndUnicode() {
        let node = ContextNode()
        for range in [CFRange(location: -1, length: 0), CFRange(location: 2, length: -1),
                      CFRange(location: Int.max, length: 1)] {
            node.selection = range
            XCTAssertNil(DictationContext.precedingText(in: node))
        }
        XCTAssertTrue(node.ranges.isEmpty)
        node.selection = CFRange(location: 5, length: 0)
        node.text = "a😀éz"
        XCTAssertEqual(DictationContext.precedingText(in: node), "a😀éz")
        node.text = "too long"
        XCTAssertNil(DictationContext.precedingText(in: node))
        node.selection = CFRange(location: 502, length: 0)
        node.text = "\u{FFFD}" + String(repeating: "a", count: 499)
        XCTAssertNil(DictationContext.precedingText(in: node))
        node.text = "\u{301}" + String(repeating: "a", count: 499)
        XCTAssertEqual(DictationContext.precedingText(in: node), String(repeating: "a", count: 499))
    }

    @MainActor
    func testPreparationReadsCurrentWordsAndPreservesCommandData() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("words.md")
        try "- kestrell → **Kestrel** ✓ (2026-11-10 private note)\n## Correct as heard\n- Mysli (secret)\n- Kestrel\n".write(to: url, atomically: true, encoding: .utf8)
        let ax = ContextAX()
        let context = DictationContext(knownWords: KnownWordsFile(url: { url }), nearbyText: { false },
                                       frontApp: { .init(pid: 123, name: "Editor") }, accessibility: ax)
        let prepared = await context.prepareText("git checkout kestrell")
        guard case .final(let command)? = prepared else { return XCTFail("Expected a final command") }
        XCTAssertEqual(command.value, "git checkout kestrell")
        XCTAssertEqual(ax.focusReads, 0)
        let prose = await context.prepareText("please send kestrell")
        guard case .polish(let first)? = prose else { return XCTFail("Expected prose to need polish") }
        XCTAssertEqual(first.localText.value, "Please send Kestrel.")
        XCTAssertEqual(first.correctSpellings, ["Kestrel", "Mysli"])
        XCTAssertEqual(first.appName, "Editor")
        XCTAssertNil(first.precedingText)
        try "## Correct as heard\n- Updated\n".write(to: url, atomically: true, encoding: .utf8)
        guard case .polish(let second)? = await context.prepareText("please send this") else {
            return XCTFail("Expected prose to need polish")
        }
        XCTAssertEqual(second.correctSpellings, ["Updated"])
        XCTAssertEqual(second.localText.value, "Please send this.")
        let empty = await context.prepareText("um.")
        XCTAssertNil(empty)
    }

    func testMissingGrantAndReadFailureKeepAppName() async {
        let ax = ContextAX()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let context = DictationContext(knownWords: KnownWordsFile(url: { url }),
                                      nearbyText: { true }, frontApp: { .init(pid: 123, name: "Editor") }, accessibility: ax)
        ax.trusted = false
        guard case .polish(let denied)? = await context.prepareText("please send this") else {
            return XCTFail("Expected prose to need polish")
        }
        XCTAssertEqual(denied.appName, "Editor")
        XCTAssertNil(denied.precedingText)
        XCTAssertEqual(ax.focusReads, 0)
        ax.trusted = true
        guard case .polish(let failed)? = await context.prepareText("please send this") else {
            return XCTFail("Expected prose to need polish")
        }
        XCTAssertEqual(failed.appName, "Editor")
        XCTAssertNil(failed.precedingText)
    }

    func testOptionalNearbyTextAndNoContentAvoidPrivateReads() async {
        let ax = ContextAX()
        let node = ContextNode()
        node.selection = CFRange(location: 6, length: 8)
        node.text = "before"
        ax.node = node
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let context = DictationContext(knownWords: KnownWordsFile(url: { url }), nearbyText: { true },
                                      frontApp: { .init(pid: 1, name: "Editor") }, accessibility: ax)
        let empty = await context.prepareText("um.")
        XCTAssertNil(empty)
        XCTAssertEqual(ax.focusReads, 0)
        guard case .polish(let request)? = await context.prepareText("please send this") else {
            return XCTFail("Expected prose to need polish")
        }
        XCTAssertEqual(request.precedingText, "before")
        XCTAssertEqual(node.ranges.map(\.length), [6])
        node.ranges = []
        let off = DictationContext(knownWords: KnownWordsFile(url: { url }), nearbyText: { false },
                                  frontApp: { .init(pid: 1, name: "Editor") }, accessibility: ax)
        guard case .polish(let withoutText)? = await off.prepareText("please send this") else {
            return XCTFail("Expected prose to need polish")
        }
        XCTAssertEqual(withoutText.appName, "Editor")
        XCTAssertNil(withoutText.precedingText)
        XCTAssertTrue(node.ranges.isEmpty)
        XCTAssertEqual(ax.focusReads, 1)
    }
}

private final class ContextNode: DictationContextNode {
    var role: String? = "AXTextArea"
    var subrole: String? = "AXUnknown"
    var protected: Bool? = false
    var selectionReads = 0
    var selectionValue: CFRange? = CFRange(location: 0, length: 0)
    var selection: CFRange? {
        get { selectionReads += 1; return selectionValue }
        set { selectionValue = newValue }
    }
    var text: String? = ""
    var ranges: [CFRange] = []
    func string(for range: CFRange) -> String? { ranges.append(range); return text }
}

private final class ContextAX: DictationContextAccessibility {
    var trusted = true
    var focusReads = 0
    var node: ContextNode?
    func focusedNode(pid: Int32) -> (any DictationContextNode)? { focusReads += 1; return node }
}
