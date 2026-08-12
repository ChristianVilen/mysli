import XCTest
@testable import KuKa

final class ThumbnailStackManagerTests: XCTestCase {
    var fakeStore: FakeImageStore!
    var sut: ThumbnailStackManager!

    override func setUp() {
        super.setUp()
        fakeStore = FakeImageStore()
        sut = ThumbnailStackManager(store: fakeStore)
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
        let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                    visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875))
        sut.add(image: result.image, result: result, screen: screen, duration: 0)
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

    // MARK: - combine()

    func testCombinePassesOlderImageAsTopAndReplacesBothEntries() {
        let older = makeResult(name: "older.png")
        let newer = makeResult(name: "newer.png")
        add(older)
        add(newer)

        let combinedResult = makeResult(name: "combined.png")
        fakeStore.combinedResultToReturn = combinedResult

        sut.combine(upperIndex: 0, lowerIndex: 1)

        XCTAssertEqual(fakeStore.combinedCalls.count, 1)
        XCTAssertTrue(fakeStore.combinedCalls[0].top === older.image, "chronologically older capture goes on top")
        XCTAssertTrue(fakeStore.combinedCalls[0].bottom === newer.image)
        XCTAssertEqual(sut.entries.count, 1)
        XCTAssertEqual(sut.entries[0].result.fileURL, combinedResult.fileURL)
    }

    func testCombineKeepsEntriesWhenStoreFails() {
        add(makeResult(name: "a.png"))
        add(makeResult(name: "b.png"))
        fakeStore.combinedResultToReturn = nil

        sut.combine(upperIndex: 0, lowerIndex: 1)

        XCTAssertEqual(sut.entries.count, 2)
    }

    func testCombineIgnoresOutOfRangeIndices() {
        add(makeResult(name: "only.png"))

        sut.combine(upperIndex: 0, lowerIndex: 1)

        XCTAssertTrue(fakeStore.combinedCalls.isEmpty)
        XCTAssertEqual(sut.entries.count, 1)
    }

    // MARK: - Panel callbacks

    func testDismissCallbackRemovesPanel() {
        add(makeResult())

        sut.entries[0].panel.onDismiss?()

        XCTAssertTrue(sut.entries.isEmpty)
    }

    func testDeleteCallbackDeletesStoredFileAndRemovesPanel() {
        let result = makeResult(name: "deleted.png")
        add(result)

        sut.entries[0].panel.onDelete?()

        XCTAssertEqual(fakeStore.deletedURLs, [result.fileURL])
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
