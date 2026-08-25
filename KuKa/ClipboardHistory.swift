import Foundation

/// Pure, side-effect-free model of the recorded clipboard history. Newest
/// item first. No AppKit, no pasteboard access — the controller adapts this
/// to the real `NSPasteboard`.
struct ClipboardHistory {
    static let maxItems = 100

    /// Total budget for image bytes summed across all items. Text always
    /// costs 0 (see `ClipboardItem.byteCost`), so only images ever push the
    /// sum toward this ceiling.
    static let maxImageBytes = 100_000_000

    /// A single item's payload must not exceed this to be accepted at all.
    /// In practice this only ever limits images, since text's `byteCost` is
    /// always 0 here — the pasteboard reader (Task 3) is responsible for
    /// capping text size before it becomes a `ClipboardItem`. Must stay
    /// below `maxImageBytes`: `add` assumes a single accepted item can never
    /// alone exceed the image budget, so evicting one oldest image at a time
    /// is always enough to fall back under it.
    static let maxItemBytes = 50_000_000

    private(set) var items: [ClipboardItem] = []

    /// Inserts at the front. When an item's hash already matches one
    /// already in the history, the existing entry is *replaced* by the new
    /// item — not merely moved to the front. Because `contentHash` is
    /// derived only from the plain-text (or PNG) bytes, re-copying the same
    /// text under a different set of rich flavors (say, plain the second
    /// time after rich the first) discards the stored RTF/HTML data in
    /// favor of whatever the new copy carries, and `copiedAt` updates to
    /// the new copy's date. An item whose `byteCost` exceeds `maxItemBytes`
    /// is refused outright and the history is left unchanged. After
    /// inserting, the oldest item is evicted if the count now exceeds the
    /// item cap, and the oldest *image* items are evicted, one at a time,
    /// while the total image-byte budget is still exceeded — text items are
    /// never evicted by the byte budget, no matter how old they are.
    mutating func add(_ item: ClipboardItem) {
        assert(Self.maxItemBytes < Self.maxImageBytes,
               "a single accepted item must never alone exceed the image byte budget")
        guard item.byteCost <= Self.maxItemBytes else { return }

        if let existingIndex = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            items.remove(at: existingIndex)
        }
        items.insert(item, at: 0)

        if items.count > Self.maxItems {
            items.removeLast()
        }

        while totalImageBytes > Self.maxImageBytes {
            // items is newest-first, so the *last* index with byteCost > 0
            // is the oldest image in the list. Text items (byteCost == 0)
            // are skipped no matter their age.
            guard let oldestImageIndex = items.lastIndex(where: { $0.byteCost > 0 }) else { break }
            items.remove(at: oldestImageIndex)
        }
    }

    mutating func remove(hash: String) {
        guard let index = items.firstIndex(where: { $0.contentHash == hash }) else { return }
        items.remove(at: index)
    }

    mutating func clear() {
        items.removeAll()
    }

    /// Empty query returns everything; otherwise a case-insensitive
    /// substring match against each item's `previewLabel`.
    func filtered(query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return items }
        return items.filter { $0.previewLabel.range(of: query, options: .caseInsensitive) != nil }
    }

    private var totalImageBytes: Int {
        items.reduce(0) { $0 + $1.byteCost }
    }
}
