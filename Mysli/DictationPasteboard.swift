import AppKit

typealias DictationPasteSnapshot = [[NSPasteboard.PasteboardType: Data]]

protocol DictationPasteboardItem {
    var types: [NSPasteboard.PasteboardType] { get }
    func data(forType type: NSPasteboard.PasteboardType) -> Data?
}

struct DictationPasteWrite {
    let changeCount: Int
    let succeeded: Bool
}

@MainActor
protocol DictationPasteboardAccess: AnyObject {
    var changeCount: Int { get }
    var items: [any DictationPasteboardItem] { get throws }
    /// Throws only before ownership changes. A partial write returns its owned count.
    func replace(with snapshot: DictationPasteSnapshot) throws -> DictationPasteWrite
}

enum DictationPasteError: Error, Equatable { case snapshot, changed, write, restore }

@MainActor
final class DictationPasteboard: DictationPasting {
    private let board: any DictationPasteboardAccess
    private let keystrokes: any KeystrokeSending
    private let schedule: DictationSchedule
    private let settleInterval: Double
    private let adoptOwnWrite: (Int) -> Void
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(board: any DictationPasteboardAccess = NativeDictationPasteboard(),
         keystrokes: any KeystrokeSending = CGEventKeystrokeSender(),
         schedule: @escaping DictationSchedule,
         settleInterval: Double = 0.15,
         adoptOwnWrite: @escaping (Int) -> Void) {
        self.board = board
        self.keystrokes = keystrokes
        self.schedule = schedule
        self.settleInterval = settleInterval
        self.adoptOwnWrite = adoptOwnWrite
    }

    func paste(_ text: PasteText) async throws {
        if busy { await withCheckedContinuation { waiting.append($0) } }
        busy = true
        defer {
            if waiting.isEmpty { busy = false }
            else { waiting.removeFirst().resume() }
        }
        try Task.checkCancellation()
        let baseline = board.changeCount
        let original = try board.items.map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let value = item.data(forType: type) else { throw DictationPasteError.snapshot }
                data[type] = value
            }
            return data
        }
        guard board.changeCount == baseline else { throw DictationPasteError.changed }
        try Task.checkCancellation()
        let write = try board.replace(with: [[.string: Data(text.value.utf8),
                                              .init("org.nspasteboard.TransientType"): Data()]])
        var failure: Error?
        do {
            guard write.succeeded else { throw DictationPasteError.write }
            guard board.changeCount == write.changeCount else { throw DictationPasteError.changed }
            try Task.checkCancellation()
            try keystrokes.sendPasteKeystroke()
            // CGEvent posting has no consumption acknowledgement. Cancellation must still wait.
            await withCheckedContinuation { continuation in
                _ = schedule(settleInterval) { continuation.resume() }
            }
            try Task.checkCancellation()
        } catch { failure = error }
        if board.changeCount == write.changeCount {
            let restored = try board.replace(with: original)
            adoptOwnWrite(restored.changeCount)
            guard restored.succeeded else { throw DictationPasteError.restore }
        }
        if let failure { throw failure }
    }
}

@MainActor
final class NativeDictationPasteboard: DictationPasteboardAccess {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    var changeCount: Int { pasteboard.changeCount }

    var items: [any DictationPasteboardItem] {
        get throws {
            if let items = pasteboard.pasteboardItems { return items.map(NativeItem.init) }
            guard (pasteboard.types ?? []).isEmpty else { throw DictationPasteError.snapshot }
            return []
        }
    }

    func replace(with snapshot: DictationPasteSnapshot) throws -> DictationPasteWrite {
        let items = try snapshot.map { representations in
            let item = NSPasteboardItem()
            for (type, data) in representations {
                guard item.setData(data, forType: type) else { throw DictationPasteError.write }
            }
            return item
        }
        let count = pasteboard.clearContents()
        guard pasteboard.changeCount == count else {
            return DictationPasteWrite(changeCount: count, succeeded: false)
        }
        // writeObjects adds to this ownership without incrementing the returned count.
        let succeeded = items.isEmpty || pasteboard.writeObjects(items)
        return DictationPasteWrite(changeCount: count, succeeded: succeeded)
    }

    private struct NativeItem: DictationPasteboardItem {
        let item: NSPasteboardItem
        init(_ item: NSPasteboardItem) { self.item = item }
        var types: [NSPasteboard.PasteboardType] { item.types }
        func data(forType type: NSPasteboard.PasteboardType) -> Data? { item.data(forType: type) }
    }
}
