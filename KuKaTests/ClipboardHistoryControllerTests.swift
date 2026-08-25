import XCTest
@testable import KuKa

@MainActor
final class ClipboardHistoryControllerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private var pasteboard: FakePasteboard!
    private var keystrokeSender: FakeKeystrokeSender!
    private var controller: ClipboardHistoryController!

    override func setUp() {
        super.setUp()
        pasteboard = FakePasteboard()
        keystrokeSender = FakeKeystrokeSender()
        controller = ClipboardHistoryController(
            reader: pasteboard,
            writer: pasteboard,
            keystrokes: keystrokeSender,
            delay: { $0() }
        )
    }

    override func tearDown() {
        // enable() starts a real, repeating RunLoop timer; without this a
        // test that enabled the controller keeps polling for the rest of
        // the run.
        controller.disable()
        super.tearDown()
    }

    private func text(_ plain: String, rtf: Data? = nil, html: Data? = nil) -> ClipboardItem {
        .text(plain: plain, rtf: rtf, html: html, copiedAt: t0)
    }

    private func image() -> ClipboardItem {
        .image(png: Data([0x01, 0x02, 0x03]), pixelSize: CGSize(width: 10, height: 10), copiedAt: t0)
    }

    /// Scripts the fake pasteboard the way a real copy would: new content,
    /// and a bumped change count for the next poll to notice.
    private func copyToPasteboard(_ item: ClipboardItem) {
        pasteboard.currentItem = item
        pasteboard.changeCount += 1
    }

    // MARK: - Polling

    func testPollWithNewChangeCountAddsItem() {
        controller.enable()
        copyToPasteboard(text("hello"))

        controller.pollNow()

        XCTAssertEqual(controller.visibleItems.map(\.contentHash), [text("hello").contentHash])
    }

    func testPollWithSameChangeCountReadsNothing() {
        controller.enable()

        controller.pollNow() // no copy happened since enable(); change count unchanged

        XCTAssertEqual(pasteboard.readCount, 0)
        XCTAssertTrue(controller.visibleItems.isEmpty)
    }

    func testPollSkipsWhenReaderReturnsNil() {
        controller.enable()
        pasteboard.currentItem = nil
        pasteboard.changeCount += 1 // changed, but marked/oversized — reader returns nil

        controller.pollNow()

        XCTAssertEqual(pasteboard.readCount, 1, "the reader must still be asked, even though it has nothing usable")
        XCTAssertTrue(controller.visibleItems.isEmpty)
    }

    func testPasteMovesItemToTopPreservingRichFlavors() {
        controller.enable()
        let rich = text("rich", rtf: Data([0x01]))
        copyToPasteboard(rich)
        controller.pollNow()
        let plain = text("plain")
        copyToPasteboard(plain)
        controller.pollNow()
        // Newest first: [plain, rich]. Select "rich" — row 1, NOT already on
        // top — so a real move is the only way to pass this.
        controller.moveSelectionDown()

        controller.enterPressed() // rich has flavors -> chooser
        controller.enterPressed() // confirms the chooser; index 0 = without formatting

        // Even though the paste itself carried no formatting, the item
        // stored in history must keep the RTF it was copied with — so the
        // chooser still offers it next time this row is pasted.
        XCTAssertEqual(controller.visibleItems.map(\.contentHash), [rich.contentHash, plain.contentHash])
        XCTAssertTrue(controller.visibleItems[0].hasRichFlavors)
    }

    func testOwnPasteWriteIsNotRecordedByNextPoll() {
        controller.enable()
        let item = text("hello")
        copyToPasteboard(item)
        controller.pollNow()
        let readCountBeforePaste = pasteboard.readCount

        controller.enterPressed() // plain text -> pastes immediately, bumping changeCount
        controller.pollNow() // must not treat our own write as new incoming content

        XCTAssertEqual(pasteboard.readCount, readCountBeforePaste, "self-write suppression should skip the read entirely")
        XCTAssertEqual(controller.visibleItems.map(\.contentHash), [item.contentHash])
    }

    func testInitBaselineIgnoresPreExistingPasteboardContent() {
        let preloaded = FakePasteboard()
        preloaded.currentItem = text("already there before launch")
        preloaded.changeCount = 5
        let freshController = ClipboardHistoryController(
            reader: preloaded,
            writer: preloaded,
            keystrokes: keystrokeSender,
            delay: { $0() }
        )

        freshController.enable()
        freshController.pollNow()

        XCTAssertTrue(freshController.visibleItems.isEmpty)
        freshController.disable()
    }

    // MARK: - Enable / disable

    func testDisableStopsPollingAndClearsHistory() {
        controller.enable()
        copyToPasteboard(text("hello"))
        controller.pollNow()
        XCTAssertEqual(controller.visibleItems.count, 1)

        controller.disable()
        XCTAssertTrue(controller.visibleItems.isEmpty)

        // A poll tick that fires after disable (e.g. the real timer racing
        // with the toggle) must not resurrect anything.
        copyToPasteboard(text("late"))
        controller.pollNow()
        XCTAssertTrue(controller.visibleItems.isEmpty)
    }

    func testEnableResumesPolling() {
        controller.enable()
        controller.disable()

        controller.enable()
        copyToPasteboard(text("hello"))
        controller.pollNow()

        XCTAssertEqual(controller.visibleItems.count, 1)
    }

    func testEnableRebaselinesSoChangesWhileDisabledAreNotRecorded() {
        controller.enable()
        controller.disable()

        // A copy happens while the feature is off — enable() must adopt
        // this as the new baseline rather than treating it as "new since
        // the old baseline."
        copyToPasteboard(text("copied while disabled"))

        controller.enable()
        controller.pollNow()

        XCTAssertTrue(controller.visibleItems.isEmpty)
    }

    // MARK: - Paste hand-off

    func testEnterOnPlainTextPastesImmediately() {
        controller.enable()
        let item = text("hello")
        copyToPasteboard(item)
        controller.pollNow()
        var closed = false
        controller.onPanelShouldClose = { closed = true }

        controller.enterPressed()

        XCTAssertEqual(pasteboard.writes.count, 1)
        XCTAssertEqual(pasteboard.writes[0].item.contentHash, item.contentHash)
        XCTAssertFalse(pasteboard.writes[0].withFormatting)
        XCTAssertEqual(keystrokeSender.sendCount, 1)
        XCTAssertTrue(closed)
    }

    func testEnterOnImagePastesImmediately() {
        controller.enable()
        let item = image()
        copyToPasteboard(item)
        controller.pollNow()
        var closed = false
        controller.onPanelShouldClose = { closed = true }

        controller.enterPressed()

        XCTAssertEqual(pasteboard.writes.count, 1)
        XCTAssertEqual(pasteboard.writes[0].item.contentHash, item.contentHash)
        XCTAssertEqual(keystrokeSender.sendCount, 1)
        XCTAssertTrue(closed)
    }

    func testEnterOnRichTextEntersChooserMode() {
        controller.enable()
        let item = text("rich", rtf: Data([0x01]))
        copyToPasteboard(item)
        controller.pollNow()

        controller.enterPressed()

        XCTAssertEqual(controller.mode, .chooser(item: item))
        XCTAssertEqual(controller.selectionIndex, 0, "without formatting is pre-selected")
        XCTAssertTrue(pasteboard.writes.isEmpty)
        XCTAssertEqual(keystrokeSender.sendCount, 0)
    }

    func testChooserFirstOptionPastesWithoutFormatting() {
        controller.enable()
        let item = text("rich", rtf: Data([0x01]))
        copyToPasteboard(item)
        controller.pollNow()
        controller.enterPressed() // enters chooser, index 0 pre-selected

        controller.enterPressed()

        XCTAssertEqual(pasteboard.writes.count, 1)
        XCTAssertFalse(pasteboard.writes[0].withFormatting)
        XCTAssertEqual(keystrokeSender.sendCount, 1)
        XCTAssertEqual(controller.mode, .list)
    }

    func testChooserSecondOptionPastesWithFormatting() {
        controller.enable()
        let item = text("rich", html: Data([0x02]))
        copyToPasteboard(item)
        controller.pollNow()
        controller.enterPressed()
        controller.moveSelectionDown()

        controller.enterPressed()

        XCTAssertEqual(pasteboard.writes.count, 1)
        XCTAssertTrue(pasteboard.writes[0].withFormatting)
        XCTAssertEqual(keystrokeSender.sendCount, 1)
    }

    func testEnterInChooserConfirmsSelection() {
        controller.enable()
        let item = text("rich", rtf: Data([0x01]))
        copyToPasteboard(item)
        controller.pollNow()
        controller.enterPressed() // enters chooser, index 0 pre-selected
        controller.moveSelectionDown() // index -> 1 ("with formatting")

        controller.enterPressed() // panel forwards Enter blindly — must confirm, not re-open

        XCTAssertEqual(pasteboard.writes.count, 1)
        XCTAssertTrue(pasteboard.writes[0].withFormatting)
        XCTAssertEqual(keystrokeSender.sendCount, 1)
        XCTAssertEqual(controller.mode, .list)
    }

    func testEscInChooserReturnsToList() {
        controller.enable()
        let item = text("rich", rtf: Data([0x01]))
        copyToPasteboard(item)
        controller.pollNow()
        controller.enterPressed()

        controller.escPressed()

        XCTAssertEqual(controller.mode, .list)
        XCTAssertTrue(pasteboard.writes.isEmpty, "esc must not paste")
    }

    func testEscInChooserClampsRestoredSelectionAfterItemsWereRemoved() {
        controller.enable()
        let rich = text("rich", rtf: Data([0x01]))
        copyToPasteboard(rich)
        controller.pollNow()
        let b = text("b")
        copyToPasteboard(b)
        controller.pollNow()
        let a = text("a")
        copyToPasteboard(a)
        controller.pollNow()
        // Newest first: [a, b, rich]. Select "rich" (index 2) and open the chooser.
        controller.moveSelectionDown()
        controller.moveSelectionDown()
        controller.enterPressed()
        XCTAssertTrue(controller.mode.isChooser)

        // While the chooser is open, the other two rows disappear (e.g.
        // their screenshots got deleted), leaving only the chooser's item.
        controller.removeItem(hash: a.contentHash)
        controller.removeItem(hash: b.contentHash)
        XCTAssertEqual(controller.visibleItems.count, 1)

        controller.escPressed()

        XCTAssertEqual(controller.mode, .list)
        XCTAssertEqual(controller.selectionIndex, 0, "the stale saved index (2) must clamp to the last valid row")
    }

    func testEscInListFiresPanelShouldClose() {
        var closed = false
        controller.onPanelShouldClose = { closed = true }

        controller.escPressed()

        XCTAssertTrue(closed)
    }

    func testPasteClosesThenWritesThenSendsKeystrokeAfterDelay() {
        var events: [String] = []
        pasteboard.onWrite = { events.append("write") }
        var capturedWork: (() -> Void)?
        let localController = ClipboardHistoryController(
            reader: pasteboard,
            writer: pasteboard,
            keystrokes: keystrokeSender,
            delay: { work in
                events.append("delay")
                capturedWork = work
            }
        )
        localController.onPanelShouldClose = { events.append("close") }
        localController.enable()
        let item = text("hello")
        copyToPasteboard(item)
        localController.pollNow()

        localController.enterPressed()

        XCTAssertEqual(events, ["close", "write", "delay"])
        XCTAssertEqual(keystrokeSender.sendCount, 0, "the keystroke must wait for the captured work to run")

        capturedWork?()

        XCTAssertEqual(keystrokeSender.sendCount, 1)
        localController.disable()
    }

    // MARK: - Removal

    func testScreenshotHashRemovalDropsItem() {
        controller.enable()
        let item = image()
        copyToPasteboard(item)
        controller.pollNow()
        XCTAssertEqual(controller.visibleItems.count, 1)

        controller.removeItem(hash: item.contentHash)

        XCTAssertTrue(controller.visibleItems.isEmpty)
    }

    // MARK: - onListChanged

    func testOnListChangedFiresAfterPollAddsItem() {
        controller.enable()
        copyToPasteboard(text("hello"))
        var fired = false
        controller.onListChanged = { fired = true }

        controller.pollNow()

        XCTAssertTrue(fired)
    }

    func testOnListChangedFiresAfterMoveSelectionDown() {
        controller.enable()
        copyToPasteboard(text("a"))
        controller.pollNow()
        copyToPasteboard(text("b"))
        controller.pollNow()
        var fired = false
        controller.onListChanged = { fired = true }

        controller.moveSelectionDown()

        XCTAssertTrue(fired)
    }

    func testOnListChangedFiresOnChooserEnterAndExit() {
        controller.enable()
        let item = text("rich", rtf: Data([0x01]))
        copyToPasteboard(item)
        controller.pollNow()
        var fireCount = 0
        controller.onListChanged = { fireCount += 1 }

        controller.enterPressed() // rich item -> enters chooser mode
        XCTAssertTrue(controller.mode.isChooser)
        XCTAssertEqual(fireCount, 1, "onListChanged must fire when entering chooser mode")

        controller.escPressed() // chooser -> list
        XCTAssertEqual(controller.mode, .list)
        XCTAssertEqual(fireCount, 2, "onListChanged must fire when leaving chooser mode via Esc")
    }

    // MARK: - Selection / filtering (pinning)

    func testMoveSelectionDownClampsAtListEnd() {
        controller.enable()
        copyToPasteboard(text("only"))
        controller.pollNow()

        controller.moveSelectionDown()
        controller.moveSelectionDown()

        XCTAssertEqual(controller.selectionIndex, 0)
    }

    func testMoveSelectionUpClampsAtZero() {
        controller.enable()
        copyToPasteboard(text("only"))
        controller.pollNow()

        controller.moveSelectionUp()

        XCTAssertEqual(controller.selectionIndex, 0)
    }

    func testSelectRowClampsAndFiresOnceInBothModes() {
        controller.enable()
        copyToPasteboard(text("a"))
        controller.pollNow()
        copyToPasteboard(text("rich", rtf: Data([0x01])))
        controller.pollNow()
        // Newest first: [rich, a].
        var fireCount = 0
        controller.onListChanged = { fireCount += 1 }

        controller.selectRow(1)
        XCTAssertEqual(controller.selectionIndex, 1)
        XCTAssertEqual(fireCount, 1, "one callback per jump, not one per row crossed")

        // Past the end clamps to the last row.
        controller.selectRow(9)
        XCTAssertEqual(controller.selectionIndex, 1)
        XCTAssertEqual(fireCount, 2)

        // Below zero clamps to the top row.
        controller.selectRow(-3)
        XCTAssertEqual(controller.selectionIndex, 0)
        XCTAssertEqual(fireCount, 3)

        // A click lands on the chooser's rows the same way, clamped to the
        // two it has rather than to the history list's length.
        controller.enterPressed() // the rich item opens the chooser
        XCTAssertTrue(controller.mode.isChooser)

        controller.selectRow(1)
        XCTAssertEqual(controller.selectionIndex, 1)
        XCTAssertEqual(fireCount, 5, "one for entering the chooser, one for the jump")

        controller.selectRow(5)
        XCTAssertEqual(controller.selectionIndex, 1, "clamped to the chooser's last row")
        XCTAssertEqual(fireCount, 6)
    }

    func testSetSearchQueryIsIgnoredInChooserMode() {
        controller.enable()
        copyToPasteboard(text("rich", rtf: Data([0x01])))
        controller.pollNow()
        controller.enterPressed() // opens the chooser
        var fireCount = 0
        controller.onListChanged = { fireCount += 1 }

        controller.setSearchQuery("zzz")

        XCTAssertEqual(controller.searchQuery, "", "the chooser has nothing to filter")
        XCTAssertEqual(controller.selectionIndex, 0, "chooser selection stays where the chooser put it")
        XCTAssertEqual(fireCount, 0, "a no-op must not fire the change callback")
    }

    func testSetSearchQueryFiltersAndResetsSelection() {
        controller.enable()
        copyToPasteboard(text("apple pie"))
        controller.pollNow()
        copyToPasteboard(text("apple tart"))
        controller.pollNow()
        copyToPasteboard(text("banana"))
        controller.pollNow()
        // Newest first: [banana, apple tart, apple pie]. Select the third
        // row (below the top) before filtering.
        controller.moveSelectionDown()
        controller.moveSelectionDown()
        XCTAssertEqual(controller.selectionIndex, 2)

        controller.setSearchQuery("apple")

        // Two matches remain, so a plain clamp (max index 1) would only
        // pull the old index 2 down to 1 — proving the reset is an
        // explicit "back to the top," not just a side effect of clamping.
        XCTAssertEqual(controller.visibleItems.map(\.previewLabel), ["apple tart", "apple pie"])
        XCTAssertEqual(controller.selectionIndex, 0)
    }

    // MARK: - Presentation

    func testPrepareForPresentationResetsQuerySelectionAndMode() {
        controller.enable()
        copyToPasteboard(text("apple"))
        controller.pollNow()
        let richApple = text("apple rich", rtf: Data([0x01]))
        copyToPasteboard(richApple)
        controller.pollNow()
        copyToPasteboard(text("banana"))
        controller.pollNow()
        // Newest first: [banana, apple rich, apple].

        controller.setSearchQuery("apple") // -> [apple rich, apple], selection reset to 0
        controller.enterPressed() // "apple rich" has flavors -> chooser mode
        controller.moveSelectionDown() // chooser selection -> 1 ("with formatting")

        XCTAssertTrue(controller.mode.isChooser)
        XCTAssertEqual(controller.searchQuery, "apple")
        XCTAssertEqual(controller.selectionIndex, 1)

        controller.prepareForPresentation()

        XCTAssertEqual(controller.mode, .list)
        XCTAssertEqual(controller.searchQuery, "")
        XCTAssertEqual(controller.selectionIndex, 0)
        XCTAssertEqual(controller.visibleItems.map(\.previewLabel), ["banana", "apple rich", "apple"])
    }
}

/// Most chooser tests only care *that* the chooser is up, not which item it
/// holds — `mode` carries the item, so an equality check would have to name
/// it every time.
private extension ClipboardPanelMode {
    var isChooser: Bool {
        if case .chooser = self { return true }
        return false
    }
}
