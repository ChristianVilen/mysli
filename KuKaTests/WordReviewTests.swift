import XCTest
@testable import KuKa

final class WordReviewTests: XCTestCase {
    private let content = """
    **[00:12:31] Them:** We should ask Convio about the rollout.

    **[00:12:40] Me:** Yuri has the numbers, and Kworix moved to Idaho.

    **[00:13:05] Them:** Then Brightlane and Floxen can start in March.

    """

    private func suspect(_ heard: String, quote: String, suggestion: String? = nil, kind: WordKind = .other,
                         reason: String? = nil) -> SuspectWord {
        SuspectWord(heard: heard, suggestion: suggestion, kind: kind, quote: quote, reason: reason)
    }

    private func select(_ suspects: [SuspectWord], knownWords: KnownWordsList = .empty) -> [WordQuestion] {
        WordQuestions.select(suspects, in: content, knownWords: knownWords)
    }

    /// A question whose quote is the whole transcript, so it always passes `select`.
    private func question(_ heard: String, quote: String? = nil) throws -> WordQuestion {
        let quote = quote ?? "Then \(heard) can start."
        return try XCTUnwrap(WordQuestions.select([suspect(heard, quote: quote)], in: quote, knownWords: .empty).first)
    }

    private func makeMeeting(in root: URL? = nil, at date: Date = localDate(2026, 10, 23, 14, 2)) throws -> MeetingFolder {
        try MeetingFolder.create(in: root ?? makeTemporaryDirectory(), startingAt: date)
    }

    func testASuspectStaysOnlyWhenItsHeardTextIsWholeTokensOfAQuoteThatIsInTheTranscript() {
        let questions = select([
            suspect("Convio", quote: "We should  ask CONVIO about\nthe rollout."),
            suspect("Brytlane", quote: "We should ask Convio about the rollout."),
            suspect("Quorix", quote: "Quorix is ready."),
            suspect("Yuri", quote: "Yuri has the numbers, and Kworix moved to Idaho"),
        ])

        XCTAssertEqual(questions.map(\.heard), ["CONVIO", "Yuri"], "as the quote writes them")
    }

    func testAHeardTextInsideALongerWordIsDropped() {
        let questions = select([suspect("Ida", quote: "Kworix moved to Idaho."), suspect("Kworix", quote: "Kworix moved to Idaho.")])

        XCTAssertEqual(questions.map(\.heard), ["Kworix"])
    }

    func testAHeardTextOfMoreThanFourTokensIsDropped() {
        let questions = select([
            suspect("ask Convio about the rollout", quote: "We should ask Convio about the rollout."),
            suspect("ask Convio about the", quote: "We should ask Convio about the rollout."),
        ])

        XCTAssertEqual(questions.map(\.heard), ["ask Convio about the"])
    }

    func testWordsTheListKnowsAreNeverAsked() {
        let list = KnownWordsList(markdown: """
        - Convio → **Konvio** ✓
        - Brightlane → **Brytlane**
        - Kworix → **Quorix** ✓
        ## Correct as heard
        - Floxen
        """)
        let questions = select([
            suspect("convio", quote: "We should ask Convio about the rollout."),
            suspect("Brightlane", quote: "Then Brightlane and Floxen can start in March."),
            suspect("Floxen", quote: "Then Brightlane and Floxen can start in March."),
            suspect("Yuri", quote: "Yuri has the numbers"),
        ], knownWords: list)
        let rightForm = WordQuestions.select([suspect("Quorix", quote: "Quorix can start.")], in: "Quorix can start.",
                                             knownWords: list)

        XCTAssertEqual(questions.map(\.heard), ["Yuri"], "a confirmed form, a provisional form, and a correct-as-heard word")
        XCTAssertEqual(rightForm, [], "a right form")
    }

    func testPunctuationAroundAHeardFormMakesNoSecondQuestionAndASkipOfOneClosesTheOther() throws {
        let questions = select([
            suspect("Convio", quote: "We should ask Convio about the rollout.", reason: "first"),
            suspect("Convio,", quote: "We should ask Convio about the rollout.", reason: "second"),
            suspect("'convio'", quote: "We should ask Convio about the rollout.", reason: "third"),
        ])
        XCTAssertEqual(questions.map(\.reason), ["first"])

        let meeting = try makeMeeting()
        try meeting.saveQuestions([try question("Convio")])
        try meeting.saveSkip(try question("Convio,", quote: "Then Convio, Yuri, and Aino can start."))

        XCTAssertEqual(meeting.wordReview(knownWords: .empty)?.isFinished, true)
    }

    func testAQuestionsHeardTextIsWhatItsQuoteWritesWithoutPunctuationAround() {
        let transcript = "We should ask Convio, about it. Ask Convio now. Then ask Kon\n  Vio's team."
        let questions = WordQuestions.select([
            suspect("Convio,", quote: "We should ask Convio, about it."),
            suspect("yuri", quote: "Ask Yuri now."),
            suspect("Kon Vio", quote: "Then ask Kon\n  Vio's team."),
        ], in: transcript + " Ask Yuri now.", knownWords: .empty)
        let spelledByTheQuote = WordQuestions.select([suspect("convio", quote: "Ask Convio now.")], in: transcript,
                                                     knownWords: .empty)

        XCTAssertEqual(questions.map(\.heard), ["Convio", "Yuri", "Kon Vio"])
        XCTAssertEqual(spelledByTheQuote.map(\.heard), ["Convio"])
    }

    func testSuggestionsThatAreRightFormsComeFirstThenPeopleThenTheRestAndOnlyFiveStay() {
        let list = KnownWordsList(markdown: "- Konvya → **Konvio** ✓\n- Qworks → **Quorix**\n")
        let line = "Yuri has the numbers, and Kworix moved to Idaho."
        let questions = select([
            suspect("numbers", quote: line, kind: .term),
            suspect("Yuri", quote: line, kind: .person),
            suspect("Convio", quote: "We should ask Convio about the rollout.", suggestion: "Konvio"),
            suspect("Idaho", quote: line, kind: .person),
            suspect("Brightlane", quote: "Then Brightlane and Floxen can start in March.", kind: .company),
            suspect("Kworix", quote: line, suggestion: "quorix", kind: .term),
            suspect("Floxen", quote: "Then Brightlane and Floxen can start in March.", kind: .person),
        ], knownWords: list)

        XCTAssertEqual(questions.map(\.heard), ["Convio", "Kworix", "Yuri", "Idaho", "Floxen"])
    }

    func testAQuestionKeepsWhatTheCLISaidWithTheHeardTextOfItsQuoteAndGetsThePlaceOfItsQuote() throws {
        let questions = select([
            suspect("Convio", quote: "ask convio about the rollout", suggestion: "Konvio", kind: .company, reason: "spelled two ways"),
            suspect("Floxen", quote: "Brightlane and Floxen can start"),
        ])

        XCTAssertEqual(questions.count, 2)
        let first = try XCTUnwrap(questions.first)
        XCTAssertEqual(first.heard, "convio", "as the quote writes it")
        XCTAssertEqual(first.suggestion, "Konvio")
        XCTAssertEqual(first.kind, .company)
        XCTAssertEqual(first.quote, "ask convio about the rollout")
        XCTAssertEqual(first.reason, "spelled two ways")
        XCTAssertEqual(first.place, "Them at 00:12:31")
        XCTAssertEqual(questions.last?.place, "Them at 00:13:05")
    }

    func testSkippedAndKnownQuestionsAreNotOpenAndOnlyKnownOnesCountAsLearned() throws {
        let questions = try ["Convio", "Yuri", "Kworix"].map { try question($0) }
        let meeting = try makeMeeting()
        func review(skipped: [Int] = [], known: [Int] = []) -> WordReview {
            WordReview(meeting: meeting, questions: questions, skipped: Set(skipped.map { questions[$0].key }),
                       known: Set(known.map { questions[$0].key }))
        }

        XCTAssertEqual(review().openQuestions.map(\.heard), ["Convio", "Yuri", "Kworix"])
        XCTAssertFalse(review().isFinished)
        XCTAssertFalse(review().hasLearnedWords)

        let skipped = review(skipped: [1])
        XCTAssertEqual(skipped.openQuestions.map(\.heard), ["Convio", "Kworix"])
        XCTAssertFalse(skipped.hasLearnedWords, "Skip changes nothing")

        let all = review(skipped: [0, 1, 2])
        XCTAssertTrue(all.isFinished)
        XCTAssertFalse(all.hasLearnedWords)

        let learned = review(skipped: [1], known: [0, 2])
        XCTAssertTrue(learned.isFinished)
        XCTAssertTrue(learned.hasLearnedWords)
        XCTAssertTrue(review(skipped: [2], known: [2]).hasLearnedWords, "a skip does not hide a word that the list learned")
    }

    func testQuestionsAndSkipsSurviveAWriteAndARead() throws {
        let meeting = try makeMeeting()
        let questions = try [question("Convio"), question("Yuri"), question("Kworix")]

        try meeting.saveQuestions(questions)
        try meeting.saveSkip(questions[0])
        try meeting.saveSkip(questions[1])

        let review = try XCTUnwrap(meeting.wordReview(knownWords: .empty))
        XCTAssertEqual(review.meeting, meeting)
        XCTAssertEqual(review.questions, questions)
        XCTAssertEqual(review.skipped, [questions[0].key, questions[1].key])
        XCTAssertEqual(review.openQuestions, [questions[2]])
    }

    func testASkipMatchesItsQuestionWhateverTheCaseOfTheHeardForm() throws {
        let meeting = try makeMeeting()
        try meeting.saveQuestions([try question("Convio")])

        try meeting.saveSkip(try question("CONVIO"))

        let review = try XCTUnwrap(meeting.wordReview(knownWords: .empty))
        XCTAssertTrue(review.isFinished)
        XCTAssertEqual(review.skipped, ["convio"])
    }

    func testSaveSkipKeepsTheOtherSkipsAndASecondSkipOfAQuestionWritesNothing() throws {
        let meeting = try makeMeeting()
        let questions = try [question("Convio"), question("Yuri")]
        try meeting.saveQuestions(questions)

        try meeting.saveSkip(questions[0])
        try meeting.saveSkip(questions[1])
        try meeting.saveSkip(try question("CONVIO"))

        XCTAssertEqual(try meeting.read(.skipped), """
        {
          "skipped" : [
            "Convio",
            "Yuri"
          ]
        }

        """)
    }

    func testSavingNoQuestionsRemovesAnOldReviewFile() throws {
        let meeting = try makeMeeting()
        try meeting.saveQuestions([try question("Convio")])
        XCTAssertNotNil(meeting.wordReview(knownWords: .empty))

        try meeting.saveQuestions([])
        try meeting.saveQuestions([])

        XCTAssertFalse(FileManager.default.fileExists(atPath: meeting.url(for: .questions).path))
        XCTAssertNil(meeting.wordReview(knownWords: .empty))
    }

    func testHandWrittenReviewFilesInTheDocumentedFormatRead() throws {
        let meeting = try makeMeeting()
        try meeting.write("""
        {"questions": [
          {"heard": "Convio", "suggestion": "Konvio", "kind": "company", "quote": "Ask Convio.", "reason": "odd", "place": "Them at 00:12:31"},
          {"heard": "Aino", "suggestion": null, "kind": "person", "quote": "Aino agreed."},
          {"heard": "QX", "kind": "term", "quote": "QX is late."}
        ]}
        """, to: .questions)
        try meeting.write(#"{"skipped": ["convio", "Brytlane"]}"#, to: .skipped)

        let review = try XCTUnwrap(meeting.wordReview(knownWords: .empty))

        XCTAssertEqual(review.questions.map(\.heard), ["Convio", "Aino", "QX"])
        XCTAssertEqual(review.questions.map(\.place), ["Them at 00:12:31", nil, nil])
        XCTAssertEqual(review.questions[1].suggestion, nil)
        XCTAssertEqual(review.skipped, ["convio"], "a skip without its question is left out")
        XCTAssertEqual(review.openQuestions.map(\.heard), ["Aino", "QX"])
    }

    func testAMeetingWithoutReadableQuestionsHasNoReview() throws {
        let meeting = try makeMeeting()
        XCTAssertNil(meeting.wordReview(knownWords: .empty), "no review.json")

        try meeting.write("{\"questions\": []}", to: .questions)
        XCTAssertNil(meeting.wordReview(knownWords: .empty), "no questions")

        try meeting.write("not JSON", to: .questions)
        XCTAssertNil(meeting.wordReview(knownWords: .empty), "broken JSON")
    }

    func testAnUnreadableSkipFileMeansNoSkips() throws {
        let meeting = try makeMeeting()
        let convio = try question("Convio")
        try meeting.saveQuestions([convio])
        try meeting.write("not JSON", to: .skipped)

        XCTAssertEqual(meeting.wordReview(knownWords: .empty)?.skipped, [])

        try meeting.saveSkip(convio)
        XCTAssertEqual(meeting.wordReview(knownWords: .empty)?.skipped, [convio.key])
    }

    func testUnfinishedListsOnlyDoneMeetingsWithOpenQuestionsOldestFirst() throws {
        let root = try makeTemporaryDirectory()
        let convio = try question("Convio")
        func meeting(day: Int, done: Bool, questions: [WordQuestion], answered: Bool = false) throws -> MeetingFolder {
            let meeting = try makeMeeting(in: root, at: localDate(2026, 10, day, 10, 0))
            try meeting.write("# Transcript", to: .transcript)
            if done { try meeting.write("# Summary", to: .summary) }
            try meeting.saveQuestions(questions)
            if answered { try meeting.saveSkip(convio) }
            return meeting
        }
        let later = try meeting(day: 24, done: true, questions: [convio])
        _ = try meeting(day: 25, done: true, questions: [convio], answered: true)
        _ = try meeting(day: 26, done: false, questions: [convio])
        _ = try meeting(day: 27, done: true, questions: [])
        let earlier = try meeting(day: 23, done: true, questions: [convio, try question("Yuri")], answered: true)

        let unfinished = WordReview.unfinished(in: root, knownWords: .empty)

        XCTAssertEqual(unfinished.map(\.meeting.name), [earlier.name, later.name])
        XCTAssertEqual(unfinished.first?.openQuestions.map(\.heard), ["Yuri"])
        XCTAssertEqual(WordReview.unfinished(in: root.appendingPathComponent("missing"), knownWords: .empty), [])
    }

    func testAQuestionWhoseWordTheListLearnedSinceIsNotOpenAndCountsAsLearned() throws {
        let root = try makeTemporaryDirectory()
        let meeting = try makeMeeting(in: root)
        try meeting.write("# Summary", to: .summary)
        let questions = try [question("Convio"), question("Yuri")]
        try meeting.saveQuestions(questions)
        let list = KnownWordsList(markdown: "- Convio → **Konvio** ✓ confirmed 2026-10-28 by Ku-Ka\n")

        let review = try XCTUnwrap(meeting.wordReview(knownWords: list))
        XCTAssertEqual(review.openQuestions.map(\.heard), ["Yuri"])
        XCTAssertEqual(review.skipped, [])
        XCTAssertTrue(review.hasLearnedWords)
        XCTAssertEqual(WordReview.unfinished(in: root, knownWords: list).map(\.openQuestions.count), [1])

        try meeting.saveSkip(questions[1])

        let finished = try XCTUnwrap(meeting.wordReview(knownWords: list))
        XCTAssertTrue(finished.isFinished)
        XCTAssertTrue(finished.hasLearnedWords, "a word that the list learned elsewhere is a word of this meeting too")
        XCTAssertEqual(WordReview.unfinished(in: root, knownWords: list), [])
        XCTAssertEqual(meeting.wordReview(knownWords: .empty)?.openQuestions.map(\.heard), ["Convio"],
                       "derived when read, so nothing was written")
    }
}
