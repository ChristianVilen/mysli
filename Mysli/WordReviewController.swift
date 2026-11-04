import AppKit

struct WordReviewScreen: Equatable {
    enum Page: Equatable {
        case question(QuestionPage)
        case finished(FinishedPage)
    }

    struct QuestionPage: Equatable {
        let meetingTitle: String
        /// 1-based among all questions of the meeting, so it counts the answered ones too.
        let number: Int
        let count: Int
        /// The quote's matched spelling, for the ordinary-words note and the field's VoiceOver label.
        let heard: String
        let place: String?
        let quote: HighlightedQuote
        let reason: String?
        /// The field's first text: the CLI's suggestion, or empty.
        let suggestion: String
        /// The heard form is ordinary words, so a right word is saved without ✓. The page says so.
        let isOrdinary: Bool
    }

    /// The quote split around the first whole-token match of the heard form, so the view can set
    /// the middle part in bold. `match` is empty when there is no match.
    struct HighlightedQuote: Equatable {
        let before: String
        let match: String
        let after: String
    }

    struct FinishedPage: Equatable {
        let meetingTitle: String
        /// The list learned a word of this meeting, and Update Notes was not asked yet in this window.
        let canUpdateNotes: Bool
        /// Update Notes was asked in this window. The page says that a notification follows.
        let isUpdating: Bool
        /// Meetings with open questions. Next Meeting shows when this is more than 0.
        let otherMeetings: Int
    }

    let page: Page
    /// The last write's error, until the next action.
    let error: String?
}

extension WordReviewScreen.HighlightedQuote {
    init(_ quote: String, around heard: String) {
        guard let phrase = Phrase(heard), let range = PhraseMatcher([phrase]).matches(in: quote).first?.range else {
            self.init(before: quote, match: "", after: "")
            return
        }
        self.init(before: String(quote[..<range.lowerBound]), match: String(quote[range]),
                  after: String(quote[range.upperBound...]))
    }
}

/// Reads questions, skips, and the list from disk for each action and screen.
/// Answers write only the list; skips write only the meeting. A failed write keeps the question open.
@MainActor
final class WordReviewController {
    /// Nil while the window is closed.
    private(set) var screen: WordReviewScreen? {
        didSet { if screen != oldValue { onChange?() } }
    }
    var onChange: (@MainActor () -> Void)?

    private let root: () -> URL
    private let knownWords: KnownWordsFile
    private let isOrdinary: @MainActor (String) -> Bool
    private let requestUpdate: @MainActor (MeetingFolder) -> Void
    private let openURL: (URL) -> Void

    private var meeting: MeetingFolder?
    private var isUpdating = false
    private var error: String?

    init(root: @escaping () -> URL,
         knownWords: KnownWordsFile,
         isOrdinary: @escaping @MainActor (String) -> Bool,
         requestUpdate: @escaping @MainActor (MeetingFolder) -> Void,
         openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.root = root
        self.knownWords = knownWords
        self.isOrdinary = isOrdinary
        self.requestUpdate = requestUpdate
        self.openURL = openURL
    }

    /// Nil: the oldest meeting with open questions, or closes when there is none. A meeting: its
    /// first open question, or its finished page when no question is open.
    func show(_ meeting: MeetingFolder?) {
        let list = knownWords.read()
        self.meeting = meeting ?? WordReview.unfinished(in: root(), knownWords: list).first?.meeting
        isUpdating = false
        error = nil
        render(list)
    }

    /// Text equal to the heard form counts as correct as heard. Other text is saved with ✓, or
    /// without it when the question is not a name and its heard form is ordinary words.
    func save(rightWord text: String) {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        answerOpenQuestion { _, question in
            if word == question.heard {
                try knownWords.add(.correctAsHeard(question.heard))
            } else {
                try knownWords.add(.replacement(heard: question.heard, right: word, confirmed: !isOrdinaryWords(question)))
            }
        }
    }

    func keepAsHeard() {
        answerOpenQuestion { _, question in try knownWords.add(.correctAsHeard(question.heard)) }
    }

    func skip() {
        answerOpenQuestion { meeting, question in try meeting.saveSkip(question) }
    }

    /// Asks for Update Notes once, on the finished page of a meeting whose words the list learned.
    func updateNotes() {
        error = nil
        let list = knownWords.read()
        if let meeting, !isUpdating, let review = meeting.wordReview(knownWords: list), review.isFinished, review.hasLearnedWords {
            isUpdating = true
            requestUpdate(meeting)
        }
        render(list)
    }

    func openSummary() {
        error = nil
        if let meeting { openURL(meeting.url(for: .summary)) }
        render(knownWords.read())
    }

    func showNextMeeting() {
        let list = knownWords.read()
        guard let next = WordReview.unfinished(in: root(), knownWords: list).first?.meeting else {
            error = nil
            render(list)
            return
        }
        show(next)
    }

    func close() {
        meeting = nil
        isUpdating = false
        error = nil
        screen = nil
    }

    private func answerOpenQuestion(_ write: (MeetingFolder, WordQuestion) throws -> Void) {
        error = nil
        if let meeting, let question = meeting.wordReview(knownWords: knownWords.read())?.openQuestions.first {
            do {
                try write(meeting, question)
            } catch {
                self.error = error.localizedDescription
            }
        }
        // Read again: the answer can close questions of other meetings too.
        render(knownWords.read())
    }

    private func render(_ list: KnownWordsList) {
        guard let meeting, let review = meeting.wordReview(knownWords: list) else {
            screen = nil
            return
        }
        guard let question = review.openQuestions.first else {
            screen = WordReviewScreen(
                page: .finished(.init(meetingTitle: meeting.title, canUpdateNotes: review.hasLearnedWords && !isUpdating,
                                      isUpdating: isUpdating,
                                      otherMeetings: WordReview.unfinished(in: root(), knownWords: list).count)),
                error: error)
            return
        }
        screen = WordReviewScreen(
            page: .question(.init(meetingTitle: meeting.title,
                                  number: (review.questions.firstIndex { $0.key == question.key } ?? 0) + 1,
                                  count: review.questions.count,
                                  heard: question.heard,
                                  place: question.place,
                                  quote: .init(question.quote, around: question.heard),
                                  reason: question.reason,
                                  suggestion: question.suggestion ?? "",
                                  isOrdinary: isOrdinaryWords(question))),
            error: error)
    }

    /// A name skips the dictionary check, because a lower-cased short name can be a dictionary word.
    private func isOrdinaryWords(_ question: WordQuestion) -> Bool {
        switch question.kind {
        case .person, .company, .product: return false
        case .term, .other: return isOrdinary(question.heard)
        }
    }
}

enum OrdinaryWords {
    /// True when every word of the lower-cased phrase is spelled right in the language of the meeting
    /// locale. False when this Mac has no spelling dictionary for the language, so the answer keeps
    /// its ✓.
    static func spellChecker(language: @escaping () -> Locale) -> @MainActor (String) -> Bool {
        { phrase in
            let checker = NSSpellChecker.shared
            guard let dictionary = dictionary(for: language(), among: checker.availableLanguages) else { return false }
            let misspelled = checker.checkSpelling(of: phrase.lowercased(), startingAt: 0, language: dictionary, wrap: false,
                                                   inSpellDocumentWithTag: 0, wordCount: nil)
            return misspelled.location == NSNotFound
        }
    }

    /// "en_US" for en-US when this Mac has it, else "en".
    private static func dictionary(for locale: Locale, among available: [String]) -> String? {
        guard let language = locale.language.languageCode?.identifier else { return nil }
        let regional = locale.region.map { "\(language)_\($0.identifier)" }
        return [regional, language].compactMap { $0 }.first { available.contains($0) }
    }
}
