import Foundation

enum DictationQuotes {
    static func ranges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var quote: (start: String.Index, closing: Character)?
        var escaped = false
        for index in text.indices {
            let character = text[index]
            if escaped { escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            let apostrophe = character == "'" || character == "’"
            let afterWord = index > text.startIndex && isWordCharacter(text[text.index(before: index)])
            if let current = quote {
                let next = text.index(after: index)
                let contraction = apostrophe && afterWord && next < text.endIndex && isWordCharacter(text[next])
                if character == current.closing, !contraction {
                    ranges.append(current.start..<next)
                    quote = nil
                }
            } else if !(apostrophe && afterWord) {
                switch character {
                case "\"", "'": quote = (index, character)
                case "“": quote = (index, "”")
                case "‘": quote = (index, "’")
                default: break
                }
            }
        }
        if let quote { ranges.append(quote.start..<text.endIndex) }
        return ranges
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}
