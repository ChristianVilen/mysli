import XCTest
@testable import KuKa

final class ClipboardHistoryTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func text(_ plain: String, rtf: Data? = nil, html: Data? = nil, at offset: TimeInterval = 0) -> ClipboardItem {
        .text(plain: plain, rtf: rtf, html: html, copiedAt: t0.addingTimeInterval(offset))
    }

    private func image(bytes: Int, fill: UInt8 = 0xAB, at offset: TimeInterval = 0) -> ClipboardItem {
        .image(png: Data(repeating: fill, count: bytes), pixelSize: CGSize(width: 100, height: 100), copiedAt: t0.addingTimeInterval(offset))
    }

    /// The real limits scaled down a million times, so no test allocates
    /// and hashes 100 MB.
    private func smallHistory() -> ClipboardHistory {
        ClipboardHistory(maxImageBytes: 100, maxItemBytes: 50)
    }

    // MARK: - Ordering

    func testAddPutsNewestFirst() {
        var history = ClipboardHistory()
        let first = text("first", at: 0)
        let second = text("second", at: 1)
        history.add(first)
        history.add(second)
        XCTAssertEqual(history.items.map(\.contentHash), [second.contentHash, first.contentHash])
    }

    func testDuplicateHashMovesToTopWithoutGrowing() {
        var history = ClipboardHistory()
        let hello = text("hello", at: 0)
        let world = text("world", at: 1)
        let helloAgain = text("hello", at: 2)
        history.add(hello)
        history.add(world)
        history.add(helloAgain)
        XCTAssertEqual(history.items.count, 2)
        XCTAssertEqual(history.items[0].contentHash, hello.contentHash)
        XCTAssertEqual(history.items[0].copiedAt, helloAgain.copiedAt)
        XCTAssertEqual(history.items[1].contentHash, world.contentHash)
    }

    func testItemCapEvictsOldest() {
        var history = ClipboardHistory()
        var itemsAdded: [ClipboardItem] = []
        for i in 0..<(ClipboardHistory.maxItems + 1) {
            let item = text("item\(i)", at: TimeInterval(i))
            itemsAdded.append(item)
            history.add(item)
        }
        XCTAssertEqual(history.items.count, ClipboardHistory.maxItems)
        XCTAssertFalse(history.items.contains { $0.contentHash == itemsAdded[0].contentHash })
        XCTAssertEqual(history.items.first?.contentHash, itemsAdded.last?.contentHash)
    }

    // MARK: - Budgets

    func testImageByteBudgetEvictsOldestUntilUnderBudget() {
        var history = smallHistory()
        // a, b, c sum to 90 (under the 100 image budget). Adding d (45)
        // pushes the total to 135, which requires evicting *two* oldest
        // items (a, then b) to fall back under budget (75).
        let a = image(bytes: 30, fill: 0x01, at: 0)
        let b = image(bytes: 30, fill: 0x02, at: 1)
        let c = image(bytes: 30, fill: 0x03, at: 2)
        let d = image(bytes: 45, fill: 0x04, at: 3)
        history.add(a)
        history.add(b)
        history.add(c)
        history.add(d)
        XCTAssertEqual(history.items.map(\.contentHash), [d.contentHash, c.contentHash])
    }

    func testImageByteBudgetSkipsTextItemsWhenEvicting() {
        var history = smallHistory()
        // Interleave texts and images: oldest→newest is
        // textOld1, imageA, textOld2, imageB, textNew, imageC. Naive
        // tail-eviction (removeLast() regardless of kind) would delete
        // textOld1 first without freeing any budget, since text costs 0.
        // The fix must skip straight to the oldest *image* (imageA).
        let textOld1 = text("old one", at: 0)
        let imageA = image(bytes: 40, fill: 0x01, at: 1)
        let textOld2 = text("old two", at: 2)
        let imageB = image(bytes: 40, fill: 0x02, at: 3)
        let textNew = text("new", at: 4)
        let imageC = image(bytes: 40, fill: 0x03, at: 5)

        history.add(textOld1)
        history.add(imageA)
        history.add(textOld2)
        history.add(imageB)
        history.add(textNew)
        history.add(imageC) // total image bytes 120 > 100 budget

        let hashes = Set(history.items.map(\.contentHash))
        XCTAssertFalse(hashes.contains(imageA.contentHash), "oldest image should be evicted")
        XCTAssertTrue(hashes.contains(imageB.contentHash))
        XCTAssertTrue(hashes.contains(imageC.contentHash))
        XCTAssertTrue(hashes.contains(textOld1.contentHash), "text must survive the byte-budget eviction regardless of age")
        XCTAssertTrue(hashes.contains(textOld2.contentHash))
        XCTAssertTrue(hashes.contains(textNew.contentHash))
        XCTAssertEqual(history.items.count, 5)
    }

    func testItemAboveMaxItemBytesIsRefused() {
        var history = smallHistory()
        let keeper = text("keeper", at: 0)
        history.add(keeper)
        let tooBig = image(bytes: 51, at: 1)
        history.add(tooBig)
        XCTAssertEqual(history.items.map(\.contentHash), [keeper.contentHash])
    }

    // MARK: - Filtering

    func testFilterMatchesTextContentCaseInsensitive() {
        var history = ClipboardHistory()
        let hello = text("Hello World", at: 0)
        let bye = text("Goodbye", at: 1)
        history.add(hello)
        history.add(bye)
        XCTAssertEqual(history.filtered(query: "hello").map(\.contentHash), [hello.contentHash])
        XCTAssertEqual(history.filtered(query: "").count, 2)
    }

    // MARK: - Removal

    func testRemoveByHash() {
        var history = ClipboardHistory()
        let first = text("first", at: 0)
        let second = text("second", at: 1)
        history.add(first)
        history.add(second)
        history.remove(hash: first.contentHash)
        XCTAssertEqual(history.items.map(\.contentHash), [second.contentHash])
    }

    // MARK: - Flavors

    func testHasRichFlavorsOnlyWhenRtfOrHtmlPresent() {
        let plain = text("plain", at: 0)
        let withRTF = text("rtf", rtf: Data([0x01]), at: 1)
        let withHTML = text("html", html: Data([0x02]), at: 2)
        let picture = image(bytes: 100, at: 3)

        XCTAssertFalse(plain.hasRichFlavors)
        XCTAssertTrue(withRTF.hasRichFlavors)
        XCTAssertTrue(withHTML.hasRichFlavors)
        XCTAssertFalse(picture.hasRichFlavors)
    }

    // MARK: - Preview Label

    func testWhitespaceOnlyPrefixGetsPlaceholderLabel() {
        let whitespacePrefix = String(repeating: "\n", count: 3000)
        let item = text(whitespacePrefix + "hello", at: 0)
        XCTAssertEqual(item.previewLabel, "(whitespace)")
    }
}
