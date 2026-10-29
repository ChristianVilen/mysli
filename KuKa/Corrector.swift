import Foundation

/// A word or phrase from the known-words list, prepared for whole-token matching.
///
/// A token is a run of letters, digits, apostrophes (' and ’), and hyphens. Apostrophes and
/// hyphens at a token's two ends are not part of it. So "acme-opsdocks" is one token, "'Convio'"
/// has the token "Convio", and "Ida" never matches inside "Idaho".
///
/// `tokens` is never empty, and each token is lowercased with ’ as '. Diacritics are kept, so
/// "Jyri" and "Jyrí" are different phrases.
struct Phrase: Hashable, Sendable {
    /// As the list or the CLI spells it.
    let text: String
    let tokens: [String]

    init?(_ text: String) {
        let tokens = Token.all(in: text).map(\.folded)
        guard !tokens.isEmpty else { return nil }
        self.text = text
        self.tokens = tokens
    }

    /// NFC, lowercased, ’ as ', trimmed, and each run of whitespace as one space. The folding rule
    /// for whole texts, such as "is this quote in the transcript".
    static func fold(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased().replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

struct PhraseMatch: Equatable {
    /// The matched tokens and the whitespace between them. A possessive "'s" or "’s" after the
    /// last token is outside the range, so a replacement keeps it.
    let range: Range<String.Index>
    let phrase: Phrase
}

/// A match covers whole tokens only, and the tokens of a phrase may have any whitespace between
/// them and nothing else. Case is ignored. At each token the phrase with the most tokens wins,
/// then the longest text. Matches never overlap, and the scan never goes back into a matched range.
struct PhraseMatcher: Sendable {
    /// In the order they win at one token. The sort is stable, so on a full tie the first given wins.
    private let phrases: [Phrase]
    private let byFirstToken: [String: [Int]]

    init(_ phrases: [Phrase]) {
        let ordered = phrases.sorted { ($0.tokens.count, $0.text.count) > ($1.tokens.count, $1.text.count) }
        self.phrases = ordered
        byFirstToken = Dictionary(grouping: ordered.indices) { ordered[$0].tokens[0] }
    }

    func matches(in text: String) -> [PhraseMatch] {
        let tokens = Token.all(in: text)
        var matches: [PhraseMatch] = []
        var index = 0
        while index < tokens.count {
            if let match = firstMatch(at: index, in: tokens, of: text) {
                matches.append(match)
                index += match.phrase.tokens.count
            } else {
                index += 1
            }
        }
        return matches
    }

    private func firstMatch(at index: Int, in tokens: [Token], of text: String) -> PhraseMatch? {
        let first = tokens[index].folded
        var candidates = byFirstToken[first] ?? []
        if first.hasSuffix("'s") {
            candidates = (candidates + (byFirstToken[String(first.dropLast(2))] ?? [])).sorted()
        }
        for candidate in candidates {
            let phrase = phrases[candidate]
            if let range = Self.range(of: phrase, at: index, in: tokens, of: text) {
                return PhraseMatch(range: range, phrase: phrase)
            }
        }
        return nil
    }

    private static func range(of phrase: Phrase, at first: Int, in tokens: [Token], of text: String)
        -> Range<String.Index>? {
        let last = first + phrase.tokens.count - 1
        guard last < tokens.count else { return nil }
        for index in first..<last {
            guard tokens[index].folded == phrase.tokens[index - first],
                  text[tokens[index].range.upperBound..<tokens[index + 1].range.lowerBound].allSatisfy(\.isWhitespace)
            else { return nil }
        }
        let start = tokens[first].range.lowerBound
        let end = tokens[last].range.upperBound
        if tokens[last].folded == phrase.tokens.last! {
            return start..<end
        }
        if tokens[last].folded == phrase.tokens.last! + "'s" {
            return start..<text.index(end, offsetBy: -2)
        }
        return nil
    }
}

private struct Token {
    let range: Range<String.Index>
    let folded: String

    static func all(in text: String) -> [Token] {
        var tokens: [Token] = []
        var rest = text[...]
        while let first = rest.firstIndex(where: isTokenCharacter) {
            let end = rest[first...].firstIndex { !isTokenCharacter($0) } ?? rest.endIndex
            let run = rest[first..<end].drop(while: isEdgeCharacter)
            if let last = run.lastIndex(where: { !isEdgeCharacter($0) }) {
                let range = run.startIndex..<run.index(after: last)
                tokens.append(Token(range: range, folded: fold(text[range])))
            }
            rest = rest[end...]
        }
        return tokens
    }

    private static func isTokenCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || isEdgeCharacter(character)
    }

    private static func isEdgeCharacter(_ character: Character) -> Bool {
        "-'’".contains(character)
    }

    /// No NFC step: Swift compares and hashes strings by canonical equivalence, so a decomposed
    /// "ä" already equals a composed one.
    private static func fold(_ token: Substring) -> String {
        token.lowercased().replacingOccurrences(of: "’", with: "'")
    }
}

struct Replacement: Equatable, Sendable {
    let heard: Phrase
    /// As the list spells it. Written exactly like this.
    let right: String
}

/// How often one heard form was replaced. `heard` is the list's spelling, so "convio" and
/// "CONVIO" in the text count as one pair.
struct AppliedCorrection: Equatable, Sendable {
    let heard: String
    let right: String
    let count: Int
}

/// Replaces heard forms with the list's right form, in one pass. Text the corrector wrote is never
/// matched again, so "A → B" and "B → C" never make "A" into "C". Text without a match comes back
/// byte for byte, and so does a match that already is the right form, which is not counted either.
struct Corrector: Sendable {
    private let matcher: PhraseMatcher
    private let rightForms: [Phrase: String]

    init(replacements: [Replacement]) {
        matcher = PhraseMatcher(replacements.map(\.heard))
        rightForms = Dictionary(replacements.map { ($0.heard, $0.right) }, uniquingKeysWith: { first, _ in first })
    }

    /// `applied` is in the order of each heard form's first match.
    func correct(_ text: String) -> (text: String, applied: [AppliedCorrection]) {
        var result = ""
        var copied = text.startIndex
        var firstMatched: [Phrase] = []
        var counts: [Phrase: Int] = [:]
        for match in matcher.matches(in: text) {
            let right = rightForms[match.phrase]!
            guard text[match.range] != right else { continue }
            result += text[copied..<match.range.lowerBound]
            result += right
            copied = match.range.upperBound
            if counts[match.phrase] == nil { firstMatched.append(match.phrase) }
            counts[match.phrase, default: 0] += 1
        }
        result += text[copied...]
        let applied = firstMatched.map {
            AppliedCorrection(heard: $0.text, right: rightForms[$0]!, count: counts[$0]!)
        }
        return (result, applied)
    }
}
