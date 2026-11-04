import Foundation

struct LogText {
    let text: String
    let ids: [LogRow.ID]
    private let ranges: [NSRange]
    private let positions: [LogRow.ID: NSRange]

    init(_ rows: [LogRow]) {
        ids = rows.map(\.id)
        text = rows.isEmpty ? "" : rows.map(\.text).joined(separator: "\n") + "\n"
        var offset = 0
        ranges = rows.map { row in
            let length = (row.text as NSString).length + 1
            defer { offset += length }
            return NSRange(location: offset, length: length)
        }
        positions = Dictionary(uniqueKeysWithValues: zip(ids, ranges))
    }

    func position(_ character: Int, from old: LogText) -> Int? {
        guard let index = old.ranges.firstIndex(where: { NSLocationInRange(character, $0) })
                ?? (character == (old.text as NSString).length ? old.ranges.indices.last : nil),
              let range = positions[old.ids[index]] else { return nil }
        return range.location + min(character - old.ranges[index].location, range.length)
    }
}
