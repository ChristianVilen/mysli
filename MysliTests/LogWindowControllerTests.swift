import XCTest
@testable import Mysli

@MainActor
final class LogWindowControllerTests: XCTestCase {
    private var sut: LogWindowController!

    override func tearDown() async throws { sut?.close(); sut = nil }

    func testFiltersCopyAndSaveUseExactlyTheDisplayedText() async throws {
        let reader = WindowLogReader([
            row("previous", date: "2026-10-29T11:00:00Z"), row("other process", pid: 99),
            row("app line"), row("meeting failed", category: "meeting", level: .error)
        ])
        var copied = ""
        var saved = ""
        sut = makeWindow(reader, copy: { copied = $0 }, save: { _, text in saved = text })
        sut.show()
        await sut.refresh()?.value
        XCTAssertFalse(sut.textView.string.contains("previous"))
        XCTAssertFalse(sut.textView.string.contains("other process"))
        sut.category.selectItem(withTitle: "meeting")
        sut.level.selectItem(withTitle: "Errors only")
        sut.category.sendAction(sut.category.action!, to: sut.category.target)
        await sut.refresh()?.value
        let expected = "2026-10-30 11:00:00.000 +0000 [42] error meeting: meeting failed\n"
        XCTAssertEqual(sut.textView.string, expected)
        sut.copyAll.performClick(nil)
        sut.save.performClick(nil)
        XCTAssertEqual(copied, expected)
        XCTAssertEqual(saved, expected)
        sut.category.selectItem(withTitle: "All")
        sut.level.selectItem(withTitle: "All")
        sut.range.selectItem(withTitle: "Everything kept")
        sut.range.sendAction(sut.range.action!, to: sut.range.target)
        await sut.refresh()?.value
        XCTAssertTrue(sut.textView.string.contains("previous"))
        XCTAssertTrue(sut.textView.string.contains("other process"))
    }

    func testRepeatedShowReusesWindowAndClosingKeepsAnotherWindowActive() async {
        var policies: [NSApplication.ActivationPolicy] = []
        var activations = 0
        let activation = OrdinaryWindowActivation.fake(setPolicy: { policies.append($0) }, activateApp: { activations += 1 })
        let other = NSWindow()
        activation.open(other)
        sut = makeWindow(WindowLogReader([]), activation: activation)
        sut.show()
        let first = sut.window
        sut.show()
        XCTAssertTrue(sut.window === first)
        XCTAssertEqual(activations, 3)
        sut.close()
        XCTAssertEqual(policies, [.regular])
        activation.close(other)
        XCTAssertEqual(policies, [.regular, .accessory])
    }

    func testCancelDeletesNothingAndConfirmedDeletionReloadsTheWindow() async {
        let reader = WindowLogReader([row("keep until confirmed")])
        var confirmed = false
        var deletions = 0
        sut = makeWindow(reader, confirm: { _ in confirmed }, delete: {
            deletions += 1
            await reader.setRows([])
        })
        sut.show()
        await sut.refresh()?.value
        sut.deleteAll.performClick(nil)
        await sut.operationTask?.value
        XCTAssertEqual(deletions, 0)
        XCTAssertTrue(sut.textView.string.contains("keep until confirmed"))
        confirmed = true
        sut.deleteAll.performClick(nil)
        await sut.operationTask?.value
        await sut.refresh()?.value
        XCTAssertEqual(deletions, 1)
        XCTAssertEqual(sut.textView.string, "")
        XCTAssertFalse(sut.copyAll.isEnabled)
        let alert = LogWindowController.deletionAlert()
        XCTAssertEqual(alert.buttons.map(\.title), ["Delete", "Cancel"])
        XCTAssertEqual(alert.buttons[1].keyEquivalent, "\u{1b}")
    }

    func testDeleteFailureKeepsTextAndReportsTheProblem() async {
        sut = makeWindow(WindowLogReader([row("kept")]), confirm: { _ in true },
                         delete: { throw CocoaError(.fileWriteNoPermission) })
        sut.show()
        await sut.refresh()?.value
        sut.deleteAll.performClick(nil)
        await sut.operationTask?.value
        await sut.refresh()?.value
        XCTAssertTrue(sut.textView.string.contains("kept"))
        XCTAssertEqual(sut.status.stringValue, "Could not delete logs. Try again.")
    }

    func testNewTextPreservesScrollAndSelectionUntilTheUserReturnsToTheBottom() async throws {
        let rows = (0..<62).map { row("line \($0)") }
        let reader = WindowLogReader(Array(rows.prefix(60)))
        sut = makeWindow(reader)
        sut.show()
        await sut.refresh()?.value
        sut.textView.setSelectedRange(NSRange(location: 4, length: 10))
        sut.scrollView.contentView.scroll(to: .zero)
        sut.scrollView.reflectScrolledClipView(sut.scrollView.contentView)
        await reader.setRows(Array(rows.prefix(61)))
        await sut.refresh()?.value
        XCTAssertEqual(sut.scrollView.contentView.bounds.origin.y, 0, accuracy: 1)
        XCTAssertEqual(sut.textView.selectedRange(), NSRange(location: 4, length: 10))
        sut.textView.scrollToEndOfDocument(nil)
        await reader.setRows(rows)
        await sut.refresh()?.value
        XCTAssertGreaterThanOrEqual(sut.scrollView.documentVisibleRect.maxY, sut.textView.bounds.maxY - 2)
    }

    func testOldReadCannotReplaceNewFilterResultsOrUpdateAClosedWindow() async {
        let reader = WindowLogReader([row("current", category: "meeting")])
        sut = makeWindow(reader)
        sut.show()
        await sut.refresh()?.value
        await reader.holdNext()
        let old = sut.refresh()
        await waitForHeldRead(reader)
        sut.category.selectItem(withTitle: "meeting")
        await sut.refresh()?.value
        await reader.release([row("stale")])
        await old?.value
        XCTAssertTrue(sut.textView.string.contains("current"))
        XCTAssertFalse(sut.textView.string.contains("stale"))
        await reader.holdNext()
        let closing = sut.refresh()
        await waitForHeldRead(reader)
        sut.close()
        await reader.release([row("closed result", category: "meeting")])
        await closing?.value
        XCTAssertFalse(sut.textView.string.contains("closed result"))
    }

    func testCommandFOpensTheNativeFindBar() async throws {
        sut = makeWindow(WindowLogReader([row("find me")]))
        sut.show()
        await sut.refresh()?.value
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                                  timestamp: 0, windowNumber: sut.window!.windowNumber,
                                                  context: nil, characters: "f", charactersIgnoringModifiers: "f",
                                                  isARepeat: false, keyCode: 3))
        XCTAssertTrue(sut.window!.performKeyEquivalent(with: event))
        XCTAssertTrue(sut.scrollView.isFindBarVisible)
    }

    func testClosingStopsPeriodicReads() async throws {
        let reader = WindowLogReader([])
        var ticks: [@MainActor () -> Void] = []
        var stops = 0
        sut = makeWindow(reader, repeatRefresh: { tick in
            ticks.append(tick)
            return { stops += 1 }
        })
        sut.show()
        await sut.refresh()?.value
        let tick = try XCTUnwrap(ticks.first)
        let before = await reader.readCount
        tick()
        for _ in 0..<1000 {
            if await reader.readCount > before { break }
            await Task.yield()
        }
        let during = await reader.readCount
        XCTAssertEqual(during, before + 1)
        sut.close()
        XCTAssertEqual(stops, 1)
        tick()
        let after = await reader.readCount
        XCTAssertEqual(after, during)
    }

    func testReadFailureRetainsTextAndTheNextSuccessfulReadRecovers() async {
        let reader = WindowLogReader([row("kept")])
        sut = makeWindow(reader)
        sut.show()
        await sut.refresh()?.value
        await reader.fail(true)
        await sut.refresh()?.value
        XCTAssertEqual(sut.status.stringValue, "Could not read logs. Retrying…")
        XCTAssertTrue(sut.textView.string.contains("kept"))
        await reader.fail(false)
        await reader.setRows([row("recovered")])
        await sut.refresh()?.value
        XCTAssertEqual(sut.status.stringValue, "1 line")
        XCTAssertTrue(sut.textView.string.contains("recovered"))
    }

    func testDeletedLogsCannotReturnFromAnOlderRead() async {
        let oldRows = [row("deleted")]
        let reader = WindowLogReader(oldRows)
        sut = makeWindow(reader, confirm: { _ in true }, delete: { await reader.setRows([]) })
        sut.show()
        await sut.refresh()?.value
        await reader.holdNext()
        let old = sut.refresh()
        await waitForHeldRead(reader)
        sut.deleteAll.performClick(nil)
        await sut.operationTask?.value
        await reader.release(oldRows)
        await old?.value
        XCTAssertEqual(sut.textView.string, "")
    }

    func testLaunchFilterMatchesTheMillisecondPrecisionOfStoredTimes() async {
        let launch = logDate("2026-10-30T10:00:00Z").addingTimeInterval(0.0002)
        let emitted = LogLine(date: launch.addingTimeInterval(0.0001), processID: 42,
                              level: .info, category: "app", message: "first message", timeZone: .gmt)
        let reader = WindowLogReader([LogRow(text: emitted.formatted, day: launch)])
        sut = makeWindow(reader, launchDate: launch)
        sut.show()
        await sut.refresh()?.value
        XCTAssertTrue(sut.textView.string.contains("first message"))
    }

    func testFilterWithIdenticalResultsDoesNotForceAFutureScrollToTheBottom() async {
        let reader = WindowLogReader((0..<60).map { row("line \($0)") })
        sut = makeWindow(reader)
        sut.show()
        await sut.refresh()?.value
        sut.range.selectItem(withTitle: "Everything kept")
        sut.range.sendAction(sut.range.action!, to: sut.range.target)
        await sut.refresh()?.value
        sut.scrollView.contentView.scroll(to: .zero)
        await reader.setRows((0..<61).map { row("line \($0)") })
        await sut.refresh()?.value
        XCTAssertEqual(sut.scrollView.contentView.bounds.origin.y, 0, accuracy: 1)
    }

    func testTheDisplayCapPreservesSelectedAndVisibleRetainedText() async throws {
        let oldRows = (0..<100).map { row("line \($0)") }
        let reader = WindowLogReader(oldRows)
        sut = makeWindow(reader, rowLimit: 100)
        sut.show()
        await sut.refresh()?.value
        let selected = (sut.textView.string as NSString).range(of: "line 50")
        sut.textView.setSelectedRange(selected)
        sut.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 400))
        let before = firstVisibleLine()
        await reader.setRows(oldRows + [row("line 100")])
        await sut.refresh()?.value
        XCTAssertEqual((sut.textView.string as NSString).substring(with: sut.textView.selectedRange()), "line 50")
        XCTAssertEqual(firstVisibleLine(), before)
    }

    private func firstVisibleLine() -> String {
        let layout = sut.textView.layoutManager!
        let point = NSPoint(x: 0, y: sut.scrollView.documentVisibleRect.minY - sut.textView.textContainerInset.height + 1)
        let glyph = layout.glyphIndex(for: point, in: sut.textView.textContainer!)
        let character = layout.characterIndexForGlyph(at: glyph)
        let text = sut.textView.string as NSString
        return text.substring(with: text.lineRange(for: NSRange(location: character, length: 0)))
    }

    func testRepeatedTextKeepsTheSelectedOccurrenceAfterEarlierRowsLeave() async {
        let repeated = (0..<3).map { _ in row("same") }
        let reader = WindowLogReader(repeated)
        sut = makeWindow(reader)
        sut.show()
        await sut.refresh()?.value
        let length = (repeated[0].text as NSString).length + 1
        sut.textView.setSelectedRange(NSRange(location: 2 * length + 4, length: 3))
        await reader.setRows([repeated[2], row("same"), row("new")])
        await sut.refresh()?.value
        XCTAssertEqual(sut.textView.selectedRange(), NSRange(location: 4, length: 3))
    }

    func testReplacementWithIdenticalTextClearsTheOldSelection() async {
        let reader = WindowLogReader([row("same")])
        sut = makeWindow(reader)
        sut.show()
        await sut.refresh()?.value
        sut.textView.setSelectedRange(NSRange(location: 4, length: 3))
        await reader.setRows([row("same")])
        await sut.refresh()?.value
        XCTAssertEqual(sut.textView.selectedRange(), NSRange(location: 0, length: 0))
    }

    func testInsertedEarlierRowKeepsSelectionOnTheSameOccurrence() async {
        let retained = row("retained")
        let reader = WindowLogReader([retained])
        sut = makeWindow(reader)
        sut.show()
        await sut.refresh()?.value
        let selected = (sut.textView.string as NSString).range(of: "retained")
        sut.textView.setSelectedRange(selected)
        let earlier = row("earlier", date: "2026-10-30T10:30:00Z")
        await reader.setRows([retained, earlier])
        await sut.refresh()?.value
        XCTAssertEqual(sut.textView.selectedRange(),
                       NSRange(location: selected.location + (earlier.text as NSString).length + 1,
                               length: selected.length))
    }

    /// Writes pictures of the log window when MYSLI_LOG_SNAPSHOTS names a folder:
    ///
    ///     TEST_RUNNER_MYSLI_LOG_SNAPSHOTS="$HOME/log-snapshots" xcodebuild -project Mysli.xcodeproj \
    ///         -scheme Mysli test -only-testing:MysliTests/LogWindowControllerTests/testRendersLogWindowStates
    func testRendersLogWindowStates() async throws {
        guard let path = ProcessInfo.processInfo.environment["MYSLI_LOG_SNAPSHOTS"] else {
            throw XCTSkip("Set MYSLI_LOG_SNAPSHOTS to render the log window")
        }
        let reader = WindowLogReader((0..<50).map {
            row($0.isMultiple(of: 7) ? "Summary tool exited with status 1: <private>" : "Recording event \($0)",
                category: $0.isMultiple(of: 3) ? "teams" : "meeting", level: $0.isMultiple(of: 7) ? .error : .notice)
        })
        sut = makeWindow(reader)
        sut.show()
        await sut.refresh()?.value
        let folder = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, appearance, size) in [
            ("light", NSAppearance.Name.aqua, NSSize(width: 1000, height: 600)),
            ("dark-small", NSAppearance.Name.darkAqua, NSSize(width: 780, height: 360))
        ] {
            sut.window?.appearance = NSAppearance(named: appearance)
            sut.window?.setContentSize(size)
            sut.window?.orderFront(nil)
            try await Task.sleep(for: .milliseconds(100))
            let view = try XCTUnwrap(sut.window?.contentView)
            view.layoutSubtreeIfNeeded()
            view.needsDisplay = true
            view.displayIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let background = appearance == .darkAqua ? NSColor(white: 0.14, alpha: 1) : NSColor(white: 0.95, alpha: 1)
            let image = NSImage(size: size, flipped: false) { rect in
                background.setFill()
                rect.fill()
                bitmap.draw(in: rect)
                return true
            }
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            try png.write(to: folder.appendingPathComponent("log-window-\(name).png"))
        }
    }

    private func makeWindow(_ reader: WindowLogReader,
                            copy: @escaping (String) -> Void = { _ in },
                            save: @escaping (NSWindow, String) -> Void = { _, _ in },
                            confirm: @escaping (NSWindow) async -> Bool = { _ in false },
                            delete: @escaping () async throws -> Void = {},
                            activation: OrdinaryWindowActivation? = nil,
                            repeatRefresh: @escaping (@escaping @MainActor () -> Void) -> () -> Void = { _ in {} },
                            rowLimit: Int = LogFilter.defaultRowLimit,
                            launchDate: Date = logDate("2026-10-30T10:00:00Z")) -> LogWindowController {
        LogWindowController(reader: reader, launchDate: launchDate, processID: 42,
                            now: { logDate("2026-10-30T11:00:00Z") }, calendar: Calendar(identifier: .gregorian),
                            activation: activation ?? .fake(), present: { _ in }, copy: copy, save: save,
                            confirmDelete: confirm, deleteLogs: delete, repeatRefresh: repeatRefresh,
                            rowLimit: rowLimit)
    }

    private func row(_ message: String, date: String = "2026-10-30T11:00:00Z", pid: Int32 = 42,
                     category: String = "app", level: LogLevel = .info) -> LogRow {
        let date = logDate(date)
        return LogRow(text: LogLine(date: date, processID: pid, level: level, category: category,
                                    message: message, timeZone: .gmt).formatted, day: date)
    }

    private func waitForHeldRead(_ reader: WindowLogReader) async {
        for _ in 0..<1000 {
            if await reader.isHeld { return }
            await Task.yield()
        }
        XCTFail("Reader did not start")
    }
}

private actor WindowLogReader: LogReading {
    private var entries: [LogRow]
    private var shouldHold = false
    private var shouldFail = false
    private(set) var readCount = 0
    private var held: CheckedContinuation<[LogRow], Never>?
    var isHeld: Bool { held != nil }
    init(_ rows: [LogRow]) { entries = rows }
    func setRows(_ rows: [LogRow]) { entries = rows }
    func holdNext() { shouldHold = true }
    func fail(_ value: Bool) { shouldFail = value }
    func release(_ rows: [LogRow]) { held?.resume(returning: rows); held = nil }
    func rows(in interval: DateInterval?) async throws -> [LogRow] {
        readCount += 1
        if shouldFail { throw CocoaError(.fileReadNoPermission) }
        if shouldHold {
            shouldHold = false
            return await withCheckedContinuation { held = $0 }
        }
        return entries
    }
}
