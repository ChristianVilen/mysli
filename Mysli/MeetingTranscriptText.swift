import Cocoa

/// The drawer's transcript as text, one block per row. An update keeps the old text up to the
/// first change, so a selection in text that did not change survives new speech.
struct TranscriptText {
    private typealias Layout = MeetingControlsPanel.Layout
    private typealias Colors = MeetingControlsPanel.Colors

    struct Replacement {
        /// UTF-16 offset where the old text stops matching. The text before it stays.
        let location: Int
        /// Replaces the old text from `location` to its end.
        let text: NSAttributedString
        let selection: NSRange
    }

    private(set) var rows: [LiveRow] = []
    /// The UTF-16 length of each row's block.
    private var rowLengths: [Int] = []

    /// Moves to `newRows`. `shown` is the text that the view shows now, the text of `rows`.
    /// Renders only the rows after the unchanged ones.
    mutating func update(to newRows: [LiveRow], shown: String, selection: NSRange = NSRange()) -> Replacement {
        let keptRows = zip(rows, newRows).prefix { $0 == $1 }.count
        let keptLength = rowLengths.prefix(keptRows).reduce(0, +)
        let rendered = Self.render(Array(newRows.dropFirst(keptRows)))
        let old = shown as NSString
        var location = keptLength + zip(old.substring(from: keptLength).utf16, rendered.text.string.utf16)
            .prefix { $0 == $1 }.count
        if location > 0, UTF16.isLeadSurrogate(old.character(at: location - 1)) { location -= 1 }
        var nextSelection = Self.selection(selection, keptBefore: location)
        if selection.length > 0, nextSelection != selection, selection.location >= keptLength {
            nextSelection = remappedSelection(selection, old: old, newRows: newRows, firstRow: keptRows,
                                              keptLength: keptLength, rendered: rendered) ?? nextSelection
        }
        rows = newRows
        rowLengths = Array(rowLengths.prefix(keptRows)) + rendered.lengths
        let start = location - keptLength
        return Replacement(location: location,
                           text: rendered.text.attributedSubstring(from: NSRange(location: start,
                                                                                  length: rendered.text.length - start)),
                           selection: nextSelection)
    }

    /// A speaker edit can shift both the end of its own heading and every later row.
    private func remappedSelection(_ selection: NSRange, old: NSString, newRows: [LiveRow], firstRow: Int,
                                   keptLength: Int, rendered: (text: NSAttributedString, lengths: [Int])) -> NSRange? {
        let new = rendered.text.string as NSString
        let selectionEnd = NSMaxRange(selection)
        func matchingRange(from oldAnchor: Int, to newAnchor: Int, through end: Int) -> NSRange? {
            let length = end - oldAnchor
            guard newAnchor + length <= new.length,
                  (0..<length).allSatisfy({ old.character(at: oldAnchor + $0) == new.character(at: newAnchor + $0) })
            else { return nil }
            return NSRange(location: keptLength + newAnchor + selection.location - oldAnchor, length: selection.length)
        }

        var oldStart = keptLength
        var newStart = 0
        for index in firstRow..<min(rows.count, newRows.count) {
            let oldEnd = oldStart + rowLengths[index]
            let newEnd = newStart + rendered.lengths[index - firstRow]
            if selection.location < oldEnd {
                let before = rows[index]
                let after = newRows[index]
                guard before.at == after.at else { return nil }
                if let prefix = matchingRange(from: oldStart, to: newStart, through: selectionEnd) {
                    return prefix
                }
                guard case .speech(let oldSpeaker, _, _) = before.content,
                      case .speech(let newSpeaker, _, _) = after.content,
                      oldSpeaker.track == newSpeaker.track else { return nil }
                let oldBody = NSMaxRange(old.range(of: "\n", range: NSRange(oldStart..<oldEnd)))
                let newBody = NSMaxRange(new.range(of: "\n", range: NSRange(newStart..<newEnd)))
                // The unchanged span can start in the heading suffix and continue into the words.
                let oldAnchor = min(selection.location, oldBody)
                let newAnchor = newBody - (oldBody - oldAnchor)
                guard newAnchor >= newStart else { return nil }
                return matchingRange(from: oldAnchor, to: newAnchor, through: max(selectionEnd, oldBody))
            }
            oldStart = oldEnd
            newStart = newEnd
        }
        return nil
    }

    /// A selection that ends in the kept text stays. Any other collapses to where the change starts.
    static func selection(_ selection: NSRange, keptBefore location: Int) -> NSRange {
        NSMaxRange(selection) <= location ? selection : NSRange(location: min(selection.location, location), length: 0)
    }

    static func render(_ rows: [LiveRow]) -> (text: NSAttributedString, lengths: [Int]) {
        let text = NSMutableAttributedString(string: "")
        var lengths: [Int] = []
        let body = NSMutableParagraphStyle()
        body.lineSpacing = 3
        for row in rows {
            let start = text.length
            switch row.content {
            case .speech(let speaker, let words, let isFinal):
                let heading = "\(RecordedTime.format(row.at))  \(speaker.label)" + (isFinal ? "" : " · Draft") + "\n"
                text.append(NSAttributedString(string: heading, attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium),
                    .foregroundColor: Colors.speaker(speaker),
                ]))
                text.append(NSAttributedString(string: MeetingPanelCopy.speech(words, isFinal: isFinal) + "\n\n", attributes: [
                    .font: NSFont.systemFont(ofSize: Layout.textSize),
                    .foregroundColor: isFinal ? NSColor.labelColor : NSColor.secondaryLabelColor,
                    .paragraphStyle: body,
                ]))
            case .pause(let duration):
                text.append(NSAttributedString(string: MeetingPanelCopy.pauseRow(at: row.at, duration: duration) + "\n\n",
                    attributes: [.font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
                                 .foregroundColor: NSColor.secondaryLabelColor]))
            }
            lengths.append(text.length - start)
        }
        return (text, lengths)
    }
}
