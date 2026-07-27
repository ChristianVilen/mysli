import XCTest
@testable import KuKa

final class ThumbnailStackManagerTests: XCTestCase {
    var sut: ThumbnailStackManager!

    override func setUp() {
        super.setUp()
        sut = ThumbnailStackManager()
    }

    override func tearDown() {
        for entry in sut.entries { entry.panel.close() }
        sut = nil
        super.tearDown()
    }

    private func makeResult(name: String = "a.png") -> CaptureResult {
        let cg = MockScreenCapture.makeImage(width: 8, height: 6)
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        return CaptureResult(image: image, fileURL: URL(fileURLWithPath: "/tmp/kuka-test/\(name)"))
    }

    private func add(_ result: CaptureResult) {
        sut.add(image: result.image, result: result, screen: NSScreen.main!, duration: 0)
    }

    // MARK: - add()

    func testAddInsertsNewestFirst() {
        let first = makeResult(name: "first.png")
        let second = makeResult(name: "second.png")

        add(first)
        add(second)

        XCTAssertEqual(sut.entries.map { $0.result.fileURL }, [second.fileURL, first.fileURL])
    }

    func testStackCapsAtFiveAndDropsOldest() {
        let results = (0..<6).map { makeResult(name: "\($0).png") }
        results.forEach(add)

        XCTAssertEqual(sut.entries.count, 5)
        XCTAssertFalse(sut.entries.contains { $0.result.fileURL == results[0].fileURL })
        XCTAssertEqual(sut.entries.first?.result.fileURL, results[5].fileURL)
    }

    // MARK: - remove()

    func testRemovePanelRemovesItsEntry() {
        add(makeResult(name: "keep.png"))
        add(makeResult(name: "drop.png"))

        sut.remove(panel: sut.entries[0].panel)

        XCTAssertEqual(sut.entries.count, 1)
        XCTAssertEqual(sut.entries[0].result.fileURL.lastPathComponent, "keep.png")
    }

    func testRemoveLastPanelNotifiesStackEmptied() {
        add(makeResult(name: "a.png"))
        add(makeResult(name: "b.png"))
        var emptiedCount = 0
        sut.onStackEmptied = { emptiedCount += 1 }

        sut.remove(panel: sut.entries[0].panel)
        XCTAssertEqual(emptiedCount, 0)

        sut.remove(panel: sut.entries[0].panel)
        XCTAssertEqual(emptiedCount, 1)
    }

    // MARK: - combine()

    func testCombinePassesOlderImageAsTopAndReplacesBothEntries() {
        let older = makeResult(name: "older.png")
        let newer = makeResult(name: "newer.png")
        add(older)
        add(newer)

        var combinedTop: NSImage?
        var combinedBottom: NSImage?
        let combinedResult = makeResult(name: "combined.png")
        sut.onCombine = { top, bottom in
            combinedTop = top
            combinedBottom = bottom
            return combinedResult
        }

        sut.combine(upperIndex: 0, lowerIndex: 1)

        XCTAssertTrue(combinedTop === older.image, "chronologically older capture goes on top")
        XCTAssertTrue(combinedBottom === newer.image)
        XCTAssertEqual(sut.entries.count, 1)
        XCTAssertEqual(sut.entries[0].result.fileURL, combinedResult.fileURL)
    }

    func testCombineKeepsEntriesWhenCallbackFails() {
        add(makeResult(name: "a.png"))
        add(makeResult(name: "b.png"))
        sut.onCombine = { _, _ in nil }

        sut.combine(upperIndex: 0, lowerIndex: 1)

        XCTAssertEqual(sut.entries.count, 2)
    }

    func testCombineIgnoresOutOfRangeIndices() {
        add(makeResult(name: "only.png"))
        sut.onCombine = { _, _ in XCTFail("should not be called"); return nil }

        sut.combine(upperIndex: 0, lowerIndex: 1)

        XCTAssertEqual(sut.entries.count, 1)
    }

    // MARK: - Panel callbacks

    func testDismissCallbackRemovesPanel() {
        add(makeResult())

        sut.entries[0].panel.onDismiss?()

        XCTAssertTrue(sut.entries.isEmpty)
    }

    func testDeleteCallbackNotifiesOwnerAndRemovesPanel() {
        let result = makeResult(name: "deleted.png")
        add(result)
        var deleted: CaptureResult?
        sut.onDelete = { deleted = $0 }

        sut.entries[0].panel.onDelete?()

        XCTAssertEqual(deleted?.fileURL, result.fileURL)
        XCTAssertTrue(sut.entries.isEmpty)
    }

    func testEditCallbackNotifiesOwnerAndRemovesPanel() {
        let result = makeResult(name: "edited.png")
        add(result)
        var edited: CaptureResult?
        sut.onEdit = { edited = $0 }

        sut.entries[0].panel.onEdit?()

        XCTAssertEqual(edited?.fileURL, result.fileURL)
        XCTAssertTrue(sut.entries.isEmpty)
    }
}
