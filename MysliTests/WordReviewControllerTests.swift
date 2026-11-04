import AppKit
import XCTest
@testable import Mysli

@MainActor
final class WordReviewControllerTests: XCTestCase {
    private struct Ask {
        var heard: String
        var suggestion: String?
        var kind = "company"
        var quote: String
        var reason: String?
        var place: String?
    }

    private let convio = Ask(heard: "Convio", suggestion: "Konvio", quote: "We should ask CONVIO's team about the rollout.",
                             reason: "spelled three ways", place: "Them at 00:12:31")
    private let yuri = Ask(heard: "Yuri", suggestion: "Jyri", kind: "person", quote: "Yuri has the numbers.", place: "Me at 00:12:40")
    private let myKey = Ask(heard: "my key", suggestion: "Maikki", kind: "person", quote: "Then my key will send them.")
    private let kworix = Ask(heard: "Kworix", quote: "Kworix moved the launch.")

    private var root: URL!
    private var listURL: URL!
    private var lockURL: URL!
    private var ordinary: Set<String> = []
    private var requested: [MeetingFolder] = []
    private var changes = 0
    private var sut: WordReviewController!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let base = try makeTemporaryDirectory()
        root = base.appendingPathComponent("Meetings", isDirectory: true)
        listURL = base.appendingPathComponent("Lists/known-words.md")
        lockURL = base.appendingPathComponent("Support/known-words.lock")
        sut = WordReviewController(
            root: { [unowned self] in root },
            knownWords: KnownWordsFile(url: { [unowned self] in listURL }, lockURL: lockURL,
                                       now: { localDate(2026, 10, 28, 10, 0) }),
            isOrdinary: { [unowned self] in ordinary.contains($0) },
            requestUpdate: { [unowned self] in requested.append($0) },
            openURL: { _ in })
        sut.onChange = { [unowned self] in changes += 1 }
    }

    @discardableResult
    private func reviewedMeeting(at date: Date, asking asks: [Ask], skipped: [String] = []) throws -> MeetingFolder {
        let meeting = try MeetingFolder.create(in: root, startingAt: date)
        try meeting.write("**[00:12:31] Them:** We should ask CONVIO's team about the rollout.\n", to: .transcript)
        try meeting.write("# \(meeting.title)\n\nAsk Convio.\n", to: .summary)
        let questions = asks.map { ask -> [String: Any] in
            var item: [String: Any] = ["heard": ask.heard, "kind": ask.kind, "quote": ask.quote]
            if let suggestion = ask.suggestion { item["suggestion"] = suggestion }
            if let reason = ask.reason { item["reason"] = reason }
            if let place = ask.place { item["place"] = place }
            return item
        }
        let json = try JSONSerialization.data(withJSONObject: ["questions": questions])
        try meeting.write(String(decoding: json, as: UTF8.self), to: .questions)
        for question in try XCTUnwrap(meeting.wordReview(knownWords: .empty)).questions where skipped.contains(question.heard) {
            try meeting.saveSkip(question)
        }
        return meeting
    }

    private var list: String? {
        try? String(contentsOf: listURL, encoding: .utf8)
    }

    private func writeList(_ text: String) throws {
        try FileManager.default.createDirectory(at: listURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: listURL, atomically: true, encoding: .utf8)
    }

    private var questionPage: WordReviewScreen.QuestionPage? {
        guard case .question(let page)? = sut.screen?.page else { return nil }
        return page
    }

    private var finishedPage: WordReviewScreen.FinishedPage? {
        guard case .finished(let page)? = sut.screen?.page else { return nil }
        return page
    }

    private func skipped(in meeting: MeetingFolder) -> Set<String>? {
        meeting.wordReview(knownWords: .empty)?.skipped
    }

    private func hasSkipFile(_ meeting: MeetingFolder) -> Bool {
        FileManager.default.fileExists(atPath: meeting.url(for: .skipped).path)
    }

    func testShowWithoutAMeetingOpensTheOldestUnfinishedReviewAtItsFirstOpenQuestion() throws {
        try reviewedMeeting(at: localDate(2026, 10, 22, 9, 0), asking: [convio], skipped: ["Convio"])
        try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: [convio, yuri], skipped: ["Convio"])
        try reviewedMeeting(at: localDate(2026, 10, 24, 9, 0), asking: [kworix])

        sut.show(nil)

        XCTAssertEqual(questionPage?.meetingTitle, "Meeting on 2026-10-23 at 09:00")
        XCTAssertEqual(questionPage?.suggestion, "Jyri")
        XCTAssertEqual(sut.screen?.error, nil)
    }

    func testShowWithoutAMeetingClosesWhenNoQuestionIsOpen() throws {
        try reviewedMeeting(at: localDate(2026, 10, 22, 9, 0), asking: [convio], skipped: ["Convio"])
        let unfinished = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: [yuri])
        sut.show(unfinished)
        XCTAssertNotNil(sut.screen)

        try unfinished.saveSkip(try XCTUnwrap(unfinished.wordReview(knownWords: .empty)?.questions.first))
        sut.show(nil)

        XCTAssertNil(sut.screen)
    }

    func testShowingAFinishedMeetingShowsItsFinishedPage() throws {
        let meeting = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: [convio, yuri], skipped: ["Yuri"])
        try writeList("- Convio → **Konvio** ✓\n")

        sut.show(meeting)

        XCTAssertEqual(sut.screen, WordReviewScreen(
            page: .finished(.init(meetingTitle: "Meeting on 2026-10-23 at 09:00", canUpdateNotes: true, isUpdating: false,
                                  otherMeetings: 0)),
            error: nil))
    }

    func testAMeetingWithoutQuestionsShowsNothing() throws {
        let meeting = try MeetingFolder.create(in: root, startingAt: localDate(2026, 10, 23, 9, 0))
        try meeting.write("# Summary\n", to: .summary)

        sut.show(meeting)

        XCTAssertNil(sut.screen)
    }

    func testTheQuestionPageNumbersAmongAllQuestionsAndSplitsTheQuoteAroundTheHeardForm() throws {
        let meeting = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: [yuri, convio, kworix], skipped: ["Yuri"])

        sut.show(meeting)

        XCTAssertEqual(sut.screen, WordReviewScreen(
            page: .question(.init(meetingTitle: "Meeting on 2026-10-23 at 09:00", number: 2, count: 3, heard: "Convio",
                                  place: "Them at 00:12:31",
                                  quote: .init(before: "We should ask ", match: "CONVIO", after: "'s team about the rollout."),
                                  reason: "spelled three ways", suggestion: "Konvio", isOrdinary: false)),
            error: nil))
    }

    func testAQuestionWithoutSuggestionPlaceOrReasonHasAnEmptyField() throws {
        let meeting = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: [kworix])

        sut.show(meeting)

        XCTAssertEqual(questionPage, .init(meetingTitle: "Meeting on 2026-10-23 at 09:00", number: 1, count: 1,
                                           heard: "Kworix", place: nil,
                                           quote: .init(before: "", match: "Kworix", after: " moved the launch."),
                                           reason: nil, suggestion: "", isOrdinary: false))
    }

    func testSavingARightWordAddsAConfirmedLineAndWritesNothingElseAndMovesOn() throws {
        let meeting = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: [convio, yuri])
        sut.show(meeting)

        sut.save(rightWord: " Konvio ")

        XCTAssertEqual(list?.hasSuffix("## Added from word review\n\n- Convio → **Konvio** ✓ confirmed 2026-10-28\n"), true, list ?? "no list")
        XCTAssertFalse(hasSkipFile(meeting))
        XCTAssertEqual(questionPage?.suggestion, "Jyri")
        XCTAssertEqual(questionPage?.number, 2)
    }

    func testAnOrdinaryHeardFormOfATermSaysSoAndIsSavedWithoutACheckMark() throws {
        ordinary = ["my key"]
        var term = myKey
        term.kind = "term"
        let meeting = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: [term])
        sut.show(meeting)
        XCTAssertEqual(questionPage?.isOrdinary, true)

        sut.save(rightWord: "Maikki")

        XCTAssertEqual(list?.hasSuffix("- my key → **Maikki** (provisional: ordinary words, so only the summary checks it; added 2026-10-28)\n"),
                       true, list ?? "no list")
        XCTAssertEqual(finishedPage?.canUpdateNotes, true, "the list knows a provisional form too")
        XCTAssertFalse(hasSkipFile(meeting))
    }

    func testOnlyTermsAndOtherWordsGoThroughTheOrdinaryWordsCheck() throws {
        ordinary = ["my key"]
        var isOrdinaryByKind: [String: Bool] = [:]

        for (day, kind) in zip(20..., ["person", "company", "product", "term", "other"]) {
            var ask = myKey
            ask.kind = kind
            sut.show(try reviewedMeeting(at: localDate(2026, 10, day, 9, 0), asking: [ask]))
            isOrdinaryByKind[kind] = questionPage?.isOrdinary
        }

        XCTAssertEqual(isOrdinaryByKind, ["person": false, "company": false, "product": false, "term": true, "other": true])
    }

    func testSavingTheHeardFormItselfCountsAsCorrectAsHeard() throws {
        let meeting = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: [convio])
        sut.show(meeting)

        sut.save(rightWord: "Convio ")

        XCTAssertEqual(list?.hasSuffix("## Correct as heard\n\n- **Convio** (correct as heard; added 2026-10-28)\n"), true,
                       list ?? "no list")
        XCTAssertFalse(hasSkipFile(meeting))
    }

    func testARightWordThatDiffersFromTheHeardFormOnlyInCaseIsAReplacement() throws {
        let meeting = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0),
                                          asking: [Ask(heard: "chatgpt", kind: "product", quote: "Then chatgpt can start.")])
        sut.show(meeting)

        sut.save(rightWord: "ChatGPT")

        XCTAssertEqual(list?.hasSuffix("## Added from word review\n\n- chatgpt → **ChatGPT** ✓ confirmed 2026-10-28\n"), true,
                       list ?? "no list")
        XCTAssertNotNil(finishedPage, "the list closes the question")
    }

    func testCorrectAsHeardAddsTheWordToItsSectionOfTheList() throws {
        let meeting = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: [yuri, convio])
        sut.show(meeting)

        sut.keepAsHeard()

        XCTAssertEqual(list?.hasSuffix("## Correct as heard\n\n- **Yuri** (correct as heard; added 2026-10-28)\n"), true,
                       list ?? "no list")
        XCTAssertFalse(hasSkipFile(meeting))
        XCTAssertEqual(questionPage?.suggestion, "Konvio")
    }

    func testSkipLeavesTheListAloneAndMovesOn() throws {
        let meeting = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: [convio, yuri])
        sut.show(meeting)

        sut.skip()

        XCTAssertNil(list, "no list file")
        XCTAssertEqual(skipped(in: meeting), ["convio"])
        XCTAssertEqual(questionPage?.suggestion, "Jyri")
    }

    func testABusyListShowsWhySavesNoAnswerAndTheNextActionClearsTheError() throws {
        let meeting = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: [convio, yuri])
        sut.show(meeting)
        try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let otherMysli = try FileLock.acquire(at: lockURL)

        sut.save(rightWord: "Konvio")

        XCTAssertEqual(sut.screen?.error, KnownWordsFileError.busy.localizedDescription)
        XCTAssertNil(list)
        XCTAssertFalse(hasSkipFile(meeting))
        XCTAssertEqual(questionPage?.suggestion, "Konvio", "the question stays open")
        otherMysli.release()

        sut.save(rightWord: "Konvio")

        XCTAssertNil(sut.screen?.error)
        XCTAssertEqual(list?.hasSuffix("- Convio → **Konvio** ✓ confirmed 2026-10-28\n"), true, list ?? "no list")
        XCTAssertEqual(questionPage?.heard, "Yuri")
    }

    func testAWordTheListCannotHoldShowsWhyAndSavesNothing() throws {
        let meeting = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: [convio])
        sut.show(meeting)

        sut.save(rightWord: "Kon / Vio")
        XCTAssertEqual(sut.screen?.error, KnownWordAdditionError.unsupported(" / ").localizedDescription)
        sut.save(rightWord: "  ")
        XCTAssertEqual(sut.screen?.error, KnownWordAdditionError.empty.localizedDescription)

        XCTAssertNil(list)
        XCTAssertFalse(hasSkipFile(meeting))
        XCTAssertEqual(questionPage?.heard, "Convio", "the question stays open")
        sut.skip()
        XCTAssertNil(sut.screen?.error)
    }

    func testASkipWriteThatFailsShowsWhyAndKeepsTheQuestionOpen() throws {
        let meeting = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: [convio, yuri])
        sut.show(meeting)
        // A folder where the skip file goes, so its write fails.
        try FileManager.default.createDirectory(at: meeting.url(for: .skipped).appendingPathComponent("blocked"),
                                                withIntermediateDirectories: true)

        sut.skip()

        XCTAssertNotNil(sut.screen?.error)
        XCTAssertEqual(questionPage?.heard, "Convio")
        XCTAssertNil(list)
    }

    func testTheFinishedPageCountsTheOtherMeetingsWithOpenQuestions() throws {
        let meeting = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: [convio])
        try reviewedMeeting(at: localDate(2026, 10, 22, 9, 0), asking: [yuri])
        try reviewedMeeting(at: localDate(2026, 10, 24, 9, 0), asking: [kworix])
        try reviewedMeeting(at: localDate(2026, 10, 25, 9, 0), asking: [myKey], skipped: ["my key"])

        sut.show(meeting)
        sut.skip()

        XCTAssertEqual(finishedPage?.otherMeetings, 2)
    }

    func testUpdateNotesAsksOnceAndThenSaysTheNotesAreBeingUpdated() throws {
        let meeting = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: [convio])
        sut.show(meeting)
        sut.save(rightWord: "Konvio")

        sut.updateNotes()
        sut.updateNotes()

        XCTAssertEqual(requested, [meeting])
        XCTAssertEqual(finishedPage, .init(meetingTitle: "Meeting on 2026-10-23 at 09:00", canUpdateNotes: false,
                                           isUpdating: true, otherMeetings: 0))
    }

    func testUpdateNotesAsksNothingWhileAQuestionIsOpenOrEveryAnswerIsSkip() throws {
        let meeting = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: [convio])
        sut.show(meeting)

        sut.updateNotes()
        sut.skip()
        sut.updateNotes()

        XCTAssertEqual(requested, [])
    }

    func testAnAnswerInOneMeetingClosesTheSameQuestionInAnother() throws {
        let first = try reviewedMeeting(at: localDate(2026, 10, 22, 9, 0), asking: [convio])
        let second = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: [convio, yuri])
        sut.show(first)

        sut.save(rightWord: "Konvio")
        XCTAssertEqual(finishedPage?.otherMeetings, 1)
        sut.showNextMeeting()

        XCTAssertEqual(questionPage?.meetingTitle, "Meeting on 2026-10-23 at 09:00")
        XCTAssertEqual(questionPage?.heard, "Yuri")
        XCTAssertEqual(questionPage?.number, 2)
        sut.skip()
        XCTAssertEqual(finishedPage, .init(meetingTitle: "Meeting on 2026-10-23 at 09:00", canUpdateNotes: true,
                                           isUpdating: false, otherMeetings: 0),
                       "the list learned Convio")
        XCTAssertEqual(skipped(in: second), ["yuri"])
        XCTAssertEqual(list?.components(separatedBy: "**Konvio**").count, 2, "one line for Convio: \(list ?? "no list")")
    }

    func testNextMeetingShowsTheOldestOtherMeetingWithOpenQuestions() throws {
        let meeting = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: [convio])
        try reviewedMeeting(at: localDate(2026, 10, 24, 9, 0), asking: [kworix])
        try reviewedMeeting(at: localDate(2026, 10, 22, 9, 0), asking: [yuri])
        sut.show(meeting)
        sut.skip()

        sut.showNextMeeting()

        XCTAssertEqual(questionPage?.meetingTitle, "Meeting on 2026-10-22 at 09:00")
    }

    func testCloseClearsTheScreenAndEveryChangeTellsTheWindowOnce() throws {
        let meeting = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: [convio, yuri])

        sut.show(meeting)
        XCTAssertEqual(changes, 1)
        sut.skip()
        XCTAssertEqual(changes, 2)
        sut.close()
        XCTAssertNil(sut.screen)
        XCTAssertEqual(changes, 3)
        sut.close()
        XCTAssertEqual(changes, 3, "closing a closed window changes nothing")
        sut.skip()
        XCTAssertEqual(skipped(in: meeting), ["convio"], "no answer without an open window")
    }

    func testTheSpellCheckerFindsOrdinaryEnglishWordsButNotAName() throws {
        guard NSSpellChecker.shared.availableLanguages.contains(where: { $0 == "en" || $0.hasPrefix("en_") }) else {
            throw XCTSkip("This Mac has no English spelling dictionary.")
        }
        let isOrdinary = OrdinaryWords.spellChecker(language: { Locale(identifier: "en-US") })

        for word in ["my key", "compass", "convio", "ida"] {
            print("OrdinaryWords en-US: \(word) -> \(isOrdinary(word))")
        }
        XCTAssertTrue(isOrdinary("my key"))
        XCTAssertTrue(isOrdinary("My Key"), "lower-cased first")
        XCTAssertFalse(isOrdinary("convio"))
        XCTAssertFalse(isOrdinary("my convio"), "every word must be spelled right")
    }
}
