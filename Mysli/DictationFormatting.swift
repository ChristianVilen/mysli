import Foundation

enum DictationFormatting {
    private static let phrases = [
        "new line": "\n", "new paragraph": "\n\n",
        "comma": ",", "period": ".", "full stop": ".",
        "question mark": "?", "exclamation mark": "!", "exclamation point": "!",
        "colon": ":", "semicolon": ";"
    ]

    private static let pattern: NSRegularExpression = {
        let commands = phrases.keys.sorted().map {
            NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: #"\s+"#)
        }.joined(separator: "|")
        return try! NSRegularExpression(pattern: #"\b("# + commands + #")\b[,.!?]?"#,
                                        options: [.caseInsensitive])
    }()

    static func apply(_ text: String) -> (text: String, hasCommands: Bool) {
        let quotedRanges = DictationQuotes.ranges(in: text)
        var result = text
        var hasCommands = false
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let phraseRange = Range(match.range(at: 1), in: text),
                  let originalRange = Range(match.range, in: text),
                  !quotedRanges.contains(where: { $0.overlaps(originalRange) }),
                  var range = Range(match.range, in: result) else { continue }
            let phrase = text[phraseRange].lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard let replacement = phrases[phrase] else { continue }
            if replacement.count == 1, let mark = replacement.first, !mark.isNewline,
               let previous = result[..<range.lowerBound].lastIndex(where: { !$0.isWhitespace }),
               result[previous] == mark {
                range = previous..<range.upperBound
            }
            result.replaceSubrange(range, with: replacement)
            hasCommands = true
        }
        let formatted = result
            .replacingOccurrences(of: #"[^\S\n]*\n[^\S\n]*"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\h+([,.;:!?])"#, with: "$1", options: .regularExpression)
        return (formatted, hasCommands)
    }
}
