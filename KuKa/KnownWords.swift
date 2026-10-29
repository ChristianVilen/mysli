import Foundation

struct HeardForm: Equatable, Sendable {
    let phrase: Phrase
    /// A ✓ in the list confirms this form, so Ku-Ka replaces it without a question.
    let isConfirmed: Bool
}

/// Every understood line of the list for one right form, merged.
struct KnownWord: Equatable, Sendable {
    /// As the list spells it. Lines merge on this exact text.
    let right: String
    /// In the order the list first names them. Never empty. A form that two lines name appears
    /// once, confirmed when any line confirms it.
    let heard: [HeardForm]
}

struct RelevantKnownWords: Equatable, Sendable {
    static let none = RelevantKnownWords(words: [], correctAsHeard: [])

    /// In list order.
    let words: [KnownWord]
    /// As the list spells them.
    let correctAsHeard: [String]

    var isEmpty: Bool { words.isEmpty && correctAsHeard.isEmpty }
}

/// The user's known-words list, read from Markdown. Reading never fails: a line that Ku-Ka does not
/// understand has no effect.
///
/// - Front matter (a first line "---" through the next "---") and fenced code blocks are not read.
///   With no closing "---", nothing is read.
/// - A heading ("#" to "######", a space, and text) starts a section. Under "Correct as heard" (any
///   case), each bullet is a word that is right as written: its bold text when it starts with bold,
///   otherwise the text before " (".
/// - Any other bullet (optional spaces, "-", "*", or "+", and a space) holds segments split at " · "
///   outside parentheses: `heard / heard → **Right** tail`, with "→" or "->". Ku-Ka uses a bullet
///   only when it understands every segment. Heard forms lose their `**` marks and quotes.
/// - In the tail, a ✓ or ✔ confirms the heard form written just before it, or every form of the
///   segment when nothing is written before it. A form without ✓ is provisional.
struct KnownWordsList: Equatable, Sendable {
    static let empty = KnownWordsList(markdown: "")

    static let newFileHeader = """
        # Known words

        Ku-Ka reads this list before it writes meeting notes, and adds to it when you answer Check Words. You can edit it in any text editor.

        Each line is: what speech recognition wrote → **the right form**. Separate several wrong forms with " / ". Ku-Ka replaces a wrong form in the transcript only when the line has ✓. Lines without ✓ only help the summary. Words under "Correct as heard" are right as written.

        """

    let words: [KnownWord]
    /// As the list spells them, in list order, each once.
    let correctAsHeard: [Phrase]
    /// Every line of the text with its own ending, so `adding` can insert by position.
    private let lines: [Line]
    private let knownTokens: Set<[String]>

    init(markdown: String) {
        lines = Self.lines(of: markdown)
        words = Self.merged(lines.flatMap { line -> [KnownWord] in
            if case .replacements(let entries) = line.meaning { return entries }
            return []
        })
        var correctAsHeard: [Phrase] = []
        for case .correctAsHeard(let word) in lines.map(\.meaning) where !correctAsHeard.contains(where: { $0.tokens == word.tokens }) {
            correctAsHeard.append(word)
        }
        self.correctAsHeard = correctAsHeard
        knownTokens = Set((words.flatMap(Self.phrases) + correctAsHeard).map(\.tokens))
    }

    /// Two lists are equal when they say the same words. The text they come from can differ in line
    /// endings and in lines that Ku-Ka does not read, so `adding` can give different text for each.
    static func == (lhs: KnownWordsList, rhs: KnownWordsList) -> Bool {
        lhs.words == rhs.words && lhs.correctAsHeard == rhs.correctAsHeard
    }

    /// Confirmed forms only, without a form that two right forms both have as confirmed, that is the
    /// right form of another word, or that is correct as heard. Forms compare by tokens, so case is
    /// ignored: matching ignores it too, and "Konvio" as a form of "Konvio Group" would otherwise
    /// rewrite the right form "Konvio". A form may differ from its own right form only in case, so
    /// "chatgpt → ChatGPT" fixes the case.
    var corrector: Corrector {
        var confirmingWords: [[String]: Int] = [:]
        for word in words {
            for form in word.heard where form.isConfirmed { confirmingWords[form.phrase.tokens, default: 0] += 1 }
        }
        var rightFormsByTokens: [[String]: Set<String>] = [:]
        for word in words {
            if let phrase = Phrase(word.right) { rightFormsByTokens[phrase.tokens, default: []].insert(word.right) }
        }
        let correctAsHeard = Set(correctAsHeard.map(\.tokens))
        return Corrector(replacements: words.flatMap { word in
            word.heard
                .filter {
                    $0.isConfirmed && confirmingWords[$0.phrase.tokens] == 1 && !correctAsHeard.contains($0.phrase.tokens)
                        && rightFormsByTokens[$0.phrase.tokens, default: []].subtracting([word.right]).isEmpty
                }
                .map { Replacement(heard: $0.phrase, right: word.right) }
        })
    }

    /// True when the list already has an opinion about `heard`: it is a heard form in any state, a
    /// right form, or correct as heard. Case is ignored. Ku-Ka never asks about such a word.
    func knows(_ heard: String) -> Bool {
        guard let tokens = Phrase(heard)?.tokens else { return false }
        return knownTokens.contains(tokens)
    }

    /// The words whose right form or any heard form occurs in `text` as whole tokens, and the
    /// correct-as-heard words that occur in it, in list order. One `PhraseMatcher` pass.
    func relevant(to text: String) -> RelevantKnownWords {
        let matcher = PhraseMatcher(words.flatMap(Self.phrases) + correctAsHeard)
        let found = Set(matcher.matches(in: text).map(\.phrase.tokens))
        return RelevantKnownWords(
            words: words.filter { Self.phrases(of: $0).contains { found.contains($0.tokens) } },
            correctAsHeard: correctAsHeard.filter { found.contains($0.tokens) }.map(\.text))
    }

    /// The whole text with one line for `addition` inserted, or nil when the list already says it,
    /// so an answer saved twice writes once. Every line of the list stays as it is, except that a
    /// last line without a line ending gets one when a line goes after it. New lines use the ending
    /// of the first line that has one. An empty list starts with `newFileHeader`.
    func adding(_ addition: KnownWordAddition, on date: Date) -> String? {
        if lines.isEmpty { return KnownWordsList(markdown: Self.newFileHeader).adding(addition, on: date) }
        guard !says(addition) else { return nil }
        let (index, headingLines) = place(of: addition)
        let ending = lines.first { !$0.ending.isEmpty }?.ending ?? "\n"
        var text = lines[..<index].map { $0.text + $0.ending }.joined()
        if index == lines.count, lines[index - 1].ending.isEmpty { text += ending }
        text += (headingLines + [addition.line(on: date)]).map { $0 + ending }.joined()
        return text + lines[index...].map { $0.text + $0.ending }.joined()
    }

    /// True when the list already has `addition`. A provisional answer adds nothing to a form the
    /// list has in any state. A confirmed one adds nothing only to a confirmed form.
    func says(_ addition: KnownWordAddition) -> Bool {
        switch addition.kind {
        case .replacement(let heard, let right, let confirmed):
            return words.first { $0.right == right }?.heard.contains {
                $0.phrase.tokens == heard.tokens && ($0.isConfirmed || !confirmed)
            } ?? false
        case .correctAsHeard(let word):
            return correctAsHeard.contains { $0.tokens == word.tokens }
        }
    }

    private static let addedSection = "Added by Ku-Ka"
    private static let correctAsHeardSection = "Correct as heard"

    /// A replacement goes after the last line with the same right form, or else at the end of
    /// "Added by Ku-Ka". A correct-as-heard word goes at the end of "Correct as heard".
    /// `headingLines` start a section that the list does not have yet.
    private func place(of addition: KnownWordAddition) -> (index: Int, headingLines: [String]) {
        switch addition.kind {
        case .replacement(_, let right, _):
            guard let last = lines.lastIndex(where: { $0.names(right) }) else { return endOfSection(Self.addedSection) }
            return (Self.endOfBullet(at: last, in: lines), [])
        case .correctAsHeard:
            return endOfSection(Self.correctAsHeardSection)
        }
    }

    /// After the last line of the section `title` that is not empty. Without the section, at the
    /// end of the file, with an empty line before and after its new heading.
    private func endOfSection(_ title: String) -> (index: Int, headingLines: [String]) {
        guard let start = lines.lastIndex(where: { $0.isHeading(title) }) else {
            let gap = lines.last?.isBlank == false ? [""] : []
            return (lines.count, gap + ["## \(title)", ""])
        }
        let next = lines.indices.dropFirst(start + 1).first { lines[$0].isHeading() } ?? lines.count
        return ((lines[start..<next].lastIndex { !$0.isBlank } ?? start) + 1, [])
    }

    /// The index after the bullet at `index` and the lines indented deeper below it. Empty lines
    /// between those lines belong to the bullet, and empty lines after the last one do not.
    private static func endOfBullet(at index: Int, in lines: [Line]) -> Int {
        var end = index + 1
        for next in lines.indices.dropFirst(index + 1) where !lines[next].isBlank {
            guard lines[next].indent > lines[index].indent else { break }
            end = next + 1
        }
        return end
    }

    private static func phrases(of word: KnownWord) -> [Phrase] {
        [Phrase(word.right)].compactMap { $0 } + word.heard.map(\.phrase)
    }

    private static func lines(of markdown: String) -> [Line] {
        var split: [(text: Substring, ending: Substring)] = []
        var start = markdown.startIndex
        while start < markdown.endIndex {
            let end = markdown[start...].firstIndex(where: \.isNewline) ?? markdown.endIndex
            let next = end < markdown.endIndex ? markdown.index(after: end) : end
            split.append((markdown[start..<end], markdown[end..<next]))
            start = next
        }
        let frontMatter = frontMatterCount(split.map(\.text))
        var fence: Character?
        var underCorrectAsHeard = false
        return split.indices.map { index in
            let meaning = index < frontMatter
                ? .notUnderstood
                : meaning(of: split[index].text, fence: &fence, underCorrectAsHeard: &underCorrectAsHeard)
            return Line(text: split[index].text, ending: split[index].ending, meaning: meaning)
        }
    }

    /// What one line outside the front matter says. `fence` and `underCorrectAsHeard` carry the
    /// state of the lines above it.
    private static func meaning(of line: Substring, fence: inout Character?, underCorrectAsHeard: inout Bool) -> Line.Meaning {
        if let open = fence {
            if closes(line, fence: open) { fence = nil }
            return .notUnderstood
        }
        if let open = openingFence(line) {
            fence = open
            return .notUnderstood
        }
        if let heading = heading(line) {
            underCorrectAsHeard = heading.caseInsensitiveCompare(correctAsHeardSection) == .orderedSame
            return .heading(heading)
        }
        guard let bullet = bulletText(line) else { return .notUnderstood }
        if underCorrectAsHeard {
            return correctAsHeardWord(bullet).map(Line.Meaning.correctAsHeard) ?? .notUnderstood
        }
        let segments = split(bullet, atEach: " · ").map(entry)
        guard segments.allSatisfy({ $0 != nil }) else { return .notUnderstood }
        return .replacements(segments.compactMap { $0 })
    }

    private static func frontMatterCount(_ lines: [Substring]) -> Int {
        guard lines.first == "---" else { return 0 }
        return lines.dropFirst().firstIndex(of: "---").map { $0 + 1 } ?? lines.count
    }

    private static func openingFence(_ line: Substring) -> Character? {
        let text = line.drop { $0 == " " }
        return ["```", "~~~"].first { text.hasPrefix($0) }?.first
    }

    private static func closes(_ line: Substring, fence: Character) -> Bool {
        let text = line.trimmingCharacters(in: .whitespaces)
        return text.count >= 3 && text.allSatisfy { $0 == fence }
    }

    private static func heading(_ line: Substring) -> String? {
        let marks = line.prefix { $0 == "#" }
        guard (1...6).contains(marks.count), line.dropFirst(marks.count).first == " " else { return nil }
        let title = line.dropFirst(marks.count).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    private static func bulletText(_ line: Substring) -> Substring? {
        let marker = line.drop { $0 == " " }
        guard let first = marker.first, "-*+".contains(first), marker.dropFirst().first == " " else { return nil }
        return marker.dropFirst(2)
    }

    private static let arrows = ["→", "->"]
    private static let quotes = CharacterSet(charactersIn: "\"“”'")

    /// `text` split at each `separator` that is outside parentheses.
    private static func split(_ text: Substring, atEach separator: String) -> [Substring] {
        var parts: [Substring] = []
        var depth = 0
        var partStart = text.startIndex
        var index = text.startIndex
        while index < text.endIndex {
            if depth == 0, text[index...].hasPrefix(separator) {
                parts.append(text[partStart..<index])
                index = text.index(index, offsetBy: separator.count)
                partStart = index
                continue
            }
            if text[index] == "(" { depth += 1 }
            if text[index] == ")" { depth = max(0, depth - 1) }
            index = text.index(after: index)
        }
        parts.append(text[partStart...])
        return parts
    }

    /// One segment as an unmerged word. The first arrow splits it, so an arrow in the tail is part of
    /// the tail. An arrow inside parentheses before it would leave a parenthesis in a heard form, which
    /// `form` rejects, so the search needs no parenthesis rule.
    private static func entry(_ segment: Substring) -> KnownWord? {
        guard let arrow = arrows.compactMap({ segment.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound })
        else { return nil }
        let rightSide = segment[arrow.upperBound...].drop(while: \.isWhitespace)
        guard rightSide.hasPrefix("**"), let closing = rightSide.dropFirst(2).range(of: "**") else { return nil }
        let right = rightSide.dropFirst(2)[..<closing.lowerBound].trimmingCharacters(in: .whitespaces)
        guard Phrase(right) != nil, !right.contains(" / ") else { return nil }
        let written = segment[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces).components(separatedBy: " / ")
        let forms = written.compactMap(form)
        guard forms.count == written.count else { return nil }
        let confirmed = confirmedTokens(in: rightSide[closing.upperBound...], of: forms)
        let heard = forms.map { HeardForm(phrase: $0, isConfirmed: confirmed.contains($0.tokens)) }
        return KnownWord(right: right, heard: heard)
    }

    /// The tokens of each form that a ✓ or ✔ in `tail` confirms. The text before a mark, back to the
    /// nearest "(", ")", ";", ".", or the start of the tail, names the one form it confirms. A mark
    /// with no text before it confirms every form, and a mark after other text confirms nothing.
    private static func confirmedTokens(in tail: Substring, of forms: [Phrase]) -> Set<[String]> {
        var confirmed: Set<[String]> = []
        for mark in tail.indices where "✓✔".contains(tail[mark]) {
            let before = tail[..<mark]
            let named = before[(before.lastIndex { "();.".contains($0) }.map(before.index(after:)) ?? before.startIndex)...]
            if named.allSatisfy(\.isWhitespace) { return Set(forms.map(\.tokens)) }
            if let phrase = form(named), forms.contains(where: { $0.tokens == phrase.tokens }) {
                confirmed.insert(phrase.tokens)
            }
        }
        return confirmed
    }

    /// The bold text when the bullet starts with bold, otherwise the text before the first " (",
    /// without a final period.
    private static func correctAsHeardWord(_ bullet: Substring) -> Phrase? {
        let word: Substring
        if bullet.hasPrefix("**") {
            let bold = bullet.dropFirst(2)
            guard let closing = bold.range(of: "**") else { return nil }
            word = bold[..<closing.lowerBound]
        } else {
            word = bullet.range(of: " (").map { bullet[..<$0.lowerBound] } ?? bullet
        }
        let text = word.trimmingCharacters(in: .whitespaces)
        return form(text.hasSuffix(".") ? text.dropLast() : text[...])
    }

    /// A form as the list writes it, without its `**` marks and the quotes around it. Nil when it has
    /// no token, or has a parenthesis or an arrow: then it is a note or prose, not a form.
    private static func form(_ text: some StringProtocol) -> Phrase? {
        let form = text.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: quotes)
        guard !form.contains(where: { "()".contains($0) }), !arrows.contains(where: { form.contains($0) }) else { return nil }
        return Phrase(form)
    }

    private static func merged(_ entries: [KnownWord]) -> [KnownWord] {
        var rights: [String] = []
        var entriesByRight: [String: [KnownWord]] = [:]
        for entry in entries {
            if entriesByRight[entry.right] == nil { rights.append(entry.right) }
            entriesByRight[entry.right, default: []].append(entry)
        }
        return rights.map { right in
            KnownWord(right: right, heard: uniqueForms(entriesByRight[right]!.flatMap(\.heard)))
        }
    }

    private static func uniqueForms(_ forms: [HeardForm]) -> [HeardForm] {
        var unique: [HeardForm] = []
        for form in forms {
            if let index = unique.firstIndex(where: { $0.phrase.tokens == form.phrase.tokens }) {
                if form.isConfirmed { unique[index] = HeardForm(phrase: unique[index].phrase, isConfirmed: true) }
            } else {
                unique.append(form)
            }
        }
        return unique
    }
}

/// One line of the list and what it says. The lines, put back together with their endings, give
/// the list's text byte for byte.
private struct Line: Equatable, Sendable {
    let text: Substring
    /// A newline character ("\r\n" is one), or "" on a last line without one.
    let ending: Substring
    let meaning: Meaning

    enum Meaning: Equatable, Sendable {
        case heading(String)
        /// One entry for each segment of a bullet. Only when every segment reads.
        case replacements([KnownWord])
        case correctAsHeard(Phrase)
        /// Front matter, prose, code, or a bullet that Ku-Ka cannot read.
        case notUnderstood
    }

    var isBlank: Bool { text.allSatisfy(\.isWhitespace) }

    var indent: Int { text.prefix { $0 == " " || $0 == "\t" }.count }

    func isHeading(_ title: String? = nil) -> Bool {
        guard case .heading(let text) = meaning else { return false }
        return title.map { text.caseInsensitiveCompare($0) == .orderedSame } ?? true
    }

    func names(_ right: String) -> Bool {
        guard case .replacements(let entries) = meaning else { return false }
        return entries.contains { $0.right == right }
    }
}

/// One answer, ready to become one line of the list. Only the two factories make one, and they
/// reject text that the list would read back as something else.
struct KnownWordAddition: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// `confirmed` false writes a provisional line, for a heard form that is ordinary words.
        case replacement(heard: Phrase, right: String, confirmed: Bool)
        case correctAsHeard(Phrase)
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    static func replacement(heard: String, right: String, confirmed: Bool) throws -> KnownWordAddition {
        let heard = try phrase(heard, isForm: true)
        let right = try phrase(right, isForm: false)
        return KnownWordAddition(kind: .replacement(heard: heard, right: right.text, confirmed: confirmed))
    }

    static func correctAsHeard(_ word: String) throws -> KnownWordAddition {
        KnownWordAddition(kind: .correctAsHeard(try phrase(word, isForm: true)))
    }

    /// `text` trimmed, when the list reads it back as written. A "*" next to the bold marks of a
    /// right form would move them. A heard form or a correct-as-heard word with a parenthesis reads
    /// as a note.
    private static func phrase(_ text: String, isForm: Bool) throws -> Phrase {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let phrase = Phrase(text) else { throw KnownWordAdditionError.empty }
        guard !text.contains(where: \.isNewline) else { throw KnownWordAdditionError.lineBreak }
        let unsupported = ["*", "→", "->", " · ", " / "] + (isForm ? ["(", ")"] : [])
        if let found = unsupported.first(where: { text.contains($0) }) { throw KnownWordAdditionError.unsupported(found) }
        return phrase
    }

    fileprivate func line(on date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        switch kind {
        case .replacement(let heard, let right, confirmed: true):
            return "- \(heard.text) → **\(right)** ✓ confirmed \(day) by Ku-Ka"
        case .replacement(let heard, let right, confirmed: false):
            return "- \(heard.text) → **\(right)** (provisional: ordinary words, so only the summary checks it; added by Ku-Ka \(day))"
        case .correctAsHeard(let word):
            return "- **\(word.text)** (correct as heard; added by Ku-Ka \(day))"
        }
    }
}

enum KnownWordAdditionError: LocalizedError, Equatable {
    /// No letter or digit.
    case empty
    case lineBreak
    /// The text that Ku-Ka cannot write, for example " / ".
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .empty: return "Type the right word first."
        case .lineBreak: return "Ku-Ka cannot save a word with a line break in it."
        case .unsupported(let text): return "Ku-Ka cannot save a word with “\(text)” in it."
        }
    }
}
