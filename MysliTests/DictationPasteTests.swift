import AppKit
import XCTest
@testable import Mysli

@MainActor
final class DictationPasteTests: XCTestCase {
    func testControllerDeliveryAndReplayUseClipboardKeyAndClockSeams() async {
        let fixture = DictationFixture()
        let board = DictationTestPasteboard()
        let keys = DictationPasteTestKeys()
        let sent = DictationTestGate<Void>()
        keys.sent = { sent.resume(()) }
        fixture.pasteOverride = DictationPasteboard(board: board, keystrokes: keys,
                                                   schedule: fixture.clock.schedule, adoptOwnWrite: { _ in })
        await fixture.enable()
        fixture.hold()
        await sent.value()
        XCTAssertEqual(board.contents[0][.string], Data("polished".utf8))
        fixture.clock.advance(to: 1)
        await fixture.waitFor(.idle)
        fixture.controller.pasteLastAgain()
        await sent.value()
        XCTAssertEqual(board.contents[0][.string], Data("polished".utf8))
        fixture.clock.advance(to: 2)
        await fixture.waitFor(.idle)
        XCTAssertEqual(fixture.polisher.requests.count, 1)
        XCTAssertEqual(fixture.controller.lastDictation?.heardText, "as heard")
    }

    func testIncompleteAndRacedSnapshotsRefuseBeforeWrite() async {
        for raced in [false, true] {
            let board = DictationTestPasteboard()
            board.contents = [[.string: Data([7])]]
            board.incomplete = !raced
            board.raceOnRead = raced
            let keys = DictationPasteTestKeys()
            let paster = DictationPasteboard(board: board, keystrokes: keys, schedule: { _, _ in XCTFail(); return {} }, adoptOwnWrite: { _ in XCTFail() })
            do { try await paster.paste(PasteText("hello")!); XCTFail() } catch {}
            XCTAssertEqual(board.contents, [[.string: Data([7])]])
            XCTAssertEqual(board.writes, 0)
            XCTAssertEqual(keys.count, 0)
        }
    }

    func testCancellationBeforeSendRestoresEmptyClipboard() async {
        let board = DictationTestPasteboard()
        let keys = DictationPasteTestKeys()
        var task: Task<Void, Error>!
        board.afterWrite = { task.cancel() }
        let paster = DictationPasteboard(board: board, keystrokes: keys, schedule: { _, _ in XCTFail(); return {} }, adoptOwnWrite: { _ in })
        task = Task { try await paster.paste(PasteText("hello")!) }
        do { try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(board.contents, [])
        XCTAssertEqual(board.writes, 2)
        XCTAssertEqual(keys.count, 0)
    }

    func testCancellationAfterSendWaitsForCleanupAndSerializesNextPaste() async throws {
        let board = DictationTestPasteboard()
        board.contents = [[.string: Data("original".utf8)]]
        let keys = DictationPasteTestKeys()
        let clock = DictationTestClock()
        let firstSent = DictationTestGate<Void>()
        keys.sent = { firstSent.resume(()) }
        let paster = DictationPasteboard(board: board, keystrokes: keys, schedule: clock.schedule, adoptOwnWrite: { _ in })
        let first = Task { try await paster.paste(PasteText("one")!) }
        await firstSent.value()
        first.cancel()
        let entered = DictationTestGate<Void>()
        let second = Task { entered.resume(()); try await paster.paste(PasteText("two")!) }
        await entered.value()
        XCTAssertEqual(board.writes, 1)
        let secondSent = DictationTestGate<Void>()
        keys.sent = { secondSent.resume(()) }
        clock.advance(to: 1)
        await secondSent.value()
        do { try await first.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(board.contents[0][.string], Data("two".utf8))
        clock.advance(to: 2)
        try await second.value
        XCTAssertEqual(board.contents, [[.string: Data("original".utf8)]])
        XCTAssertEqual(board.writes, 4)
    }

    func testWhenIdleWaitsForTheOwedRestore() async throws {
        let board = DictationTestPasteboard()
        board.contents = [[.string: Data("original".utf8)]]
        let keys = DictationPasteTestKeys()
        let clock = DictationTestClock()
        let sent = DictationTestGate<Void>()
        keys.sent = { sent.resume(()) }
        let paster = DictationPasteboard(board: board, keystrokes: keys, schedule: clock.schedule, adoptOwnWrite: { _ in })
        await paster.whenIdle()
        let paste = Task { try await paster.paste(PasteText("hello")!) }
        await sent.value()
        paste.cancel()
        XCTAssertTrue(paster.isBusy)
        var restoredWhenIdle: DictationPasteSnapshot?
        let idle = Task { await paster.whenIdle(); restoredWhenIdle = board.contents }
        clock.advance(to: 1)
        await idle.value
        XCTAssertEqual(restoredWhenIdle, [[.string: Data("original".utf8)]])
        XCTAssertFalse(paster.isBusy)
        _ = try? await paste.value
    }

    func testExternalCopyDuringSettleWins() async throws {
        let board = DictationTestPasteboard()
        let keys = DictationPasteTestKeys()
        let clock = DictationTestClock()
        let sent = DictationTestGate<Void>()
        keys.sent = { sent.resume(()) }
        let paster = DictationPasteboard(board: board, keystrokes: keys, schedule: clock.schedule, adoptOwnWrite: { _ in XCTFail() })
        let task = Task { try await paster.paste(PasteText("hello")!) }
        await sent.value()
        board.changeCount += 1
        board.contents = [[.string: Data("external".utf8)]]
        clock.advance(to: 1)
        try await task.value
        XCTAssertEqual(board.contents, [[.string: Data("external".utf8)]])
        XCTAssertEqual(board.writes, 1)
    }

    func testWriteAndKeyFailuresRestoreAndThrow() async {
        for failKey in [false, true] {
            let board = DictationTestPasteboard()
            board.contents = [[.string: Data("original".utf8)]]
            board.failWrite = failKey ? 0 : 1
            let keys = DictationPasteTestKeys()
            keys.fails = failKey
            let paster = DictationPasteboard(board: board, keystrokes: keys, schedule: { _, _ in XCTFail(); return {} }, adoptOwnWrite: { _ in })
            do { try await paster.paste(PasteText("hello")!); XCTFail() } catch {}
            XCTAssertEqual(board.contents, [[.string: Data("original".utf8)]])
            XCTAssertEqual(board.writes, 2)
        }
    }

    func testRestoreFailureThrowsAndStillAdoptsItsExactCount() async {
        let board = DictationTestPasteboard()
        board.failWrite = 2
        let keys = DictationPasteTestKeys()
        var adopted: [Int] = []
        let paster = DictationPasteboard(board: board, keystrokes: keys,
                                        schedule: { _, work in work(); return {} }, adoptOwnWrite: { adopted.append($0) })
        do { try await paster.paste(PasteText("hello")!); XCTFail() }
        catch { XCTAssertEqual(error as? DictationPasteError, .restore) }
        XCTAssertEqual(adopted, [2])
    }

    func testOwnWriteTokenCannotAdoptExternalCopy() async {
        let board = DictationTestPasteboard()
        board.afterWrite = { board.changeCount += 1; board.contents = [[.string: Data("external".utf8)]] }
        let keys = DictationPasteTestKeys()
        let paster = DictationPasteboard(board: board, keystrokes: keys, schedule: { _, _ in XCTFail(); return {} }, adoptOwnWrite: { _ in XCTFail() })
        do { try await paster.paste(PasteText("hello")!); XCTFail() } catch {}
        XCTAssertEqual(board.contents, [[.string: Data("external".utf8)]])
        XCTAssertEqual(board.writes, 1)
        XCTAssertEqual(keys.count, 0)
    }

    func testRestoreSuppressionUsesActualHistoryPollWithoutSwallowingNextCopy() async throws {
        let board = DictationTestPasteboard()
        let keys = DictationPasteTestKeys()
        let history = ClipboardHistoryController(reader: board, writer: board, keystrokes: keys)
        history.enable()
        defer { history.disable() }
        board.contents = [[.string: Data("original".utf8)]]
        board.changeCount += 1
        history.pollNow()
        board.reads = 0
        let paster = DictationPasteboard(board: board, keystrokes: keys,
                                        schedule: { _, work in work(); return {} },
                                        adoptOwnWrite: history.adoptOwnWrite)
        try await paster.paste(PasteText("private")!)
        history.pollNow()
        XCTAssertEqual(board.reads, 0)
        XCTAssertEqual(history.visibleItems.count, 1)
        board.changeCount += 1
        board.contents = [[.string: Data("external".utf8)]]
        history.pollNow()
        XCTAssertEqual(board.reads, 1)
        XCTAssertEqual(history.visibleItems.map(\.previewLabel), ["external", "original"])
        board.afterWrite = {
            if board.writes == 4 {
                board.changeCount += 1
                board.contents = [[.string: Data("newest".utf8)]]
            }
        }
        try await paster.paste(PasteText("again")!)
        history.pollNow()
        XCTAssertEqual(history.visibleItems.map(\.previewLabel), ["newest", "external", "original"])
    }

    func testRestoresEveryItemAndUnknownRepresentationAfterSettle() async throws {
        let board = DictationTestPasteboard()
        let original: DictationPasteSnapshot = [[.string: Data("old".utf8), .init("custom"): Data([0, 255])], [.html: Data([4])]]
        board.contents = original
        let keys = DictationPasteTestKeys()
        let clock = DictationTestClock()
        let gate = DictationTestGate<Void>()
        keys.sent = { gate.resume(()) }
        let paster = DictationPasteboard(board: board, keystrokes: keys, schedule: clock.schedule, adoptOwnWrite: { _ in })
        let task = Task { try await paster.paste(PasteText("hello\n\nworld\n")!) }
        await gate.value()
        XCTAssertEqual(board.contents, [[.string: Data("hello\n\nworld\n".utf8), .init("org.nspasteboard.TransientType"): Data()]])
        XCTAssertEqual(keys.count, 1)
        clock.advance(to: 1)
        try await task.value
        XCTAssertEqual(board.contents, original)
    }
}

@MainActor
final class DictationTestPasteboard: DictationPasteboardAccess, @MainActor PasteboardReading, @MainActor PasteboardWriting {
    var changeCount = 0
    var contents: DictationPasteSnapshot = []
    var incomplete = false
    var raceOnRead = false
    var writes = 0
    var reads = 0
    var failWrite = 0
    var afterWrite: (() -> Void)?
    var items: [any DictationPasteboardItem] {
        if raceOnRead { changeCount += 1 }
        return contents.map { DictationTestPasteboardItem(data: $0, incomplete: incomplete) }
    }
    func replace(with snapshot: DictationPasteSnapshot) -> DictationPasteWrite {
        writes += 1
        changeCount += 1
        let count = changeCount
        contents = snapshot
        afterWrite?()
        return .init(changeCount: count, succeeded: writes != failWrite)
    }
    func readCurrentItem(now: Date) -> ClipboardItem? {
        reads += 1
        guard let first = contents.first,
              let data = first[.string], let value = String(data: data, encoding: .utf8) else { return nil }
        return .text(plain: value, copiedAt: now)
    }
    func write(_ item: ClipboardItem, withFormatting: Bool) -> Int { XCTFail(); return changeCount }
}

struct DictationTestPasteboardItem: DictationPasteboardItem {
    let data: [NSPasteboard.PasteboardType: Data]
    let incomplete: Bool
    var types: [NSPasteboard.PasteboardType] { Array(data.keys) }
    func data(forType type: NSPasteboard.PasteboardType) -> Data? { incomplete ? nil : data[type] }
}

final class DictationPasteTestKeys: KeystrokeSending {
    var count = 0
    var sent: (() -> Void)?
    var fails = false
    func sendPasteKeystroke() throws {
        if fails { throw DictationTestError.failed }
        count += 1
        sent?()
    }
}
