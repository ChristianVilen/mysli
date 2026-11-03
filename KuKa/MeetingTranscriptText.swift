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
    }

    private(set) var rows: [LiveRow] = []
    /// The UTF-16 length of each row's block.
    private var rowLengths: [Int] = []

    /// Moves to `newRows`. `shown` is the text that the view shows now, the text of `rows`.
    /// Renders only the rows after the unchanged ones.
    mutating func update(to newRows: [LiveRow], shown: String) -> Replacement {
        let keptRows = zip(rows, newRows).prefix { $0 == $1 }.count
        let keptLength = rowLengths.prefix(keptRows).reduce(0, +)
        let rendered = Self.render(Array(newRows.dropFirst(keptRows)))
        let old = shown as NSString
        var location = keptLength + zip(old.substring(from: keptLength).utf16, rendered.text.string.utf16)
            .prefix { $0 == $1 }.count
        if location > 0, UTF16.isLeadSurrogate(old.character(at: location - 1)) { location -= 1 }
        rows = newRows
        rowLengths = Array(rowLengths.prefix(keptRows)) + rendered.lengths
        let start = location - keptLength
        return Replacement(location: location,
                           text: rendered.text.attributedSubstring(from: NSRange(location: start,
                                                                                  length: rendered.text.length - start)))
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
