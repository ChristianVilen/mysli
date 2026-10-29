import Foundation

/// A suspect validated by `WordQuestions.select`, unless loaded from a hand-edited `review.json`.
struct WordQuestion: Codable, Equatable, Sendable {
    /// As the quote writes it, so typing it back means "correct as heard".
    let heard: String
    let suggestion: String?
    let kind: WordKind
    let quote: String
    let reason: String?
    /// "Them at 00:12:31". Nil when no transcript line has the whole quote.
    let place: String?

    var key: String { Self.key(of: heard) }

    /// The tokens of the heard text, as the list compares forms, so "Convio", "convio", and
    /// "Convio," are one word. The review files store the heard text, not this key, so a file from
    /// any version gets the same keys. A heard text without a token, which only a hand-written
    /// `review.json` can have, keeps its folded text.
    static func key(of heard: String) -> String {
        Phrase(heard)?.tokens.joined(separator: " ") ?? Phrase.fold(heard)
    }

    fileprivate init(_ suspect: SuspectWord, heard: String, place: String?) {
        self.heard = heard
        suggestion = suspect.suggestion
        kind = suspect.kind
        quote = suspect.quote
        reason = suspect.reason
        self.place = place
    }
}

enum WordQuestions {
    static let limit = 5
    static let maximumTokens = 4

    /// Keeps a suspect when its heard text has at most `maximumTokens` tokens and is whole tokens of
    /// its quote, the quote is in `transcript` (both folded with `Phrase.fold`), the list does not
    /// know the heard text, and no suspect kept before it has the same `WordQuestion.key`. Then the
    /// suspects whose suggestion is a right form of the list come first, then people, then the
    /// rest, each in the CLI's order, and the first `limit` stay. A question's heard text is the
    /// first match in its quote, with one space for each run of whitespace: the quote's spelling
    /// and case, without the punctuation that the CLI may have kept around the word.
    static func select(_ suspects: [SuspectWord], in transcript: String, knownWords: KnownWordsList) -> [WordQuestion] {
        let content = Phrase.fold(transcript)
        let rightForms = Set(knownWords.words.compactMap { Phrase($0.right)?.tokens })
        var keys: Set<String> = []
        let kept = suspects.compactMap { suspect -> (suspect: SuspectWord, heard: String)? in
            guard let heard = Phrase(suspect.heard), heard.tokens.count <= maximumTokens,
                  let match = PhraseMatcher([heard]).matches(in: suspect.quote).first,
                  content.contains(Phrase.fold(suspect.quote)),
                  !knownWords.knows(suspect.heard),
                  keys.insert(WordQuestion.key(of: suspect.heard)).inserted
            else { return nil }
            return (suspect, suspect.quote[match.range].split(whereSeparator: \.isWhitespace).joined(separator: " "))
        }
        func group(_ suspect: SuspectWord) -> Int {
            if let suggestion = suspect.suggestion.flatMap(Phrase.init), rightForms.contains(suggestion.tokens) { return 0 }
            return suspect.kind == .person ? 1 : 2
        }
        return kept.enumerated()
            .sorted { (group($0.element.suspect), $0.offset) < (group($1.element.suspect), $1.offset) }
            .prefix(limit)
            .map { WordQuestion($0.element.suspect, heard: $0.element.heard,
                                place: Transcript.place(of: $0.element.suspect.quote, in: transcript)) }
    }
}

/// One meeting's questions from `review.json` with the skips from `review-skipped.json`. It is read
/// from disk each time and never stored.
struct WordReview: Equatable {
    let meeting: MeetingFolder
    /// Never empty: a meeting without questions has no review.
    let questions: [WordQuestion]
    /// By `WordQuestion.key`: the questions that the user skipped in this meeting.
    let skipped: Set<String>
    /// By `WordQuestion.key`: the questions whose heard form the list knows now. The list did not
    /// know it when Ku-Ka asked, so it learned it since: from an answer in any meeting, or by hand.
    let known: Set<String>

    var openQuestions: [WordQuestion] { questions.filter { !skipped.contains($0.key) && !known.contains($0.key) } }
    var isFinished: Bool { openQuestions.isEmpty }
    /// The list learned a word of this meeting since Ku-Ka asked, so Update Notes can change something.
    var hasLearnedWords: Bool { !known.isEmpty }

    /// Done meetings whose review has open questions, oldest first.
    static func unfinished(in root: URL, knownWords: KnownWordsList) -> [WordReview] {
        MeetingFolder.all(in: root)
            .compactMap { meeting, stage in stage == .done ? meeting.wordReview(knownWords: knownWords) : nil }
            .filter { !$0.isFinished }
    }

    /// The open questions of `meeting`, or with nil, of every done meeting in `root`: the number
    /// that the menu's Check Words and the notes notification show.
    static func openQuestionCount(of meeting: MeetingFolder?, in root: URL, knownWords: KnownWordsList) -> Int {
        guard let meeting else {
            return unfinished(in: root, knownWords: knownWords).reduce(0) { $0 + $1.openQuestions.count }
        }
        return meeting.wordReview(knownWords: knownWords)?.openQuestions.count ?? 0
    }
}

extension MeetingFolder {
    /// Nil when the meeting has no questions, or `review.json` cannot be read. A skip file that
    /// cannot be read counts as no skips, and a skip without its question is left out. What
    /// `knownWords` knows is read here and never written, so a list line removed later opens its
    /// questions again, also in the meeting that answered them.
    func wordReview(knownWords: KnownWordsList) -> WordReview? {
        guard let data = try? Data(contentsOf: url(for: .questions)),
              let questions = try? JSONDecoder().decode(StoredQuestions.self, from: data).questions,
              !questions.isEmpty
        else { return nil }
        return WordReview(meeting: self, questions: questions,
                          skipped: Set(questions.map(\.key)).intersection(storedSkips().map(WordQuestion.key(of:))),
                          known: Set(questions.filter { knownWords.knows($0.heard) }.map(\.key)))
    }

    /// For the summarize step only, before `summary.md`. Without questions it removes `review.json`,
    /// so a run never leaves the questions of an earlier run.
    func saveQuestions(_ questions: [WordQuestion]) throws {
        guard !questions.isEmpty else {
            let file = url(for: .questions)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            return
        }
        try write(Self.json(StoredQuestions(questions: questions)), to: .questions)
    }

    /// For the review window only, after `summary.md`. Keeps the earlier skips that read, and writes
    /// nothing for a question that is already skipped.
    func saveSkip(_ question: WordQuestion) throws {
        let skipped = storedSkips()
        guard !skipped.contains(where: { WordQuestion.key(of: $0) == question.key }) else { return }
        try write(Self.json(StoredSkips(skipped: skipped + [question.heard])), to: .skipped)
    }

    private func storedSkips() -> [String] {
        guard let data = try? Data(contentsOf: url(for: .skipped)) else { return [] }
        return (try? JSONDecoder().decode(StoredSkips.self, from: data).skipped) ?? []
    }

    private static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self) + "\n"
    }
}

private struct StoredQuestions: Codable {
    let questions: [WordQuestion]
}

/// {"skipped": ["QX"]}: the heard texts of the skipped questions.
private struct StoredSkips: Codable {
    let skipped: [String]
}
