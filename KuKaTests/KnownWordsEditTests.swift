import XCTest
@testable import KuKa

final class KnownWordsEditTests: XCTestCase {
    private let today = localDate(2026, 10, 28, 10, 0)

    private func adding(_ addition: KnownWordAddition, to markdown: String) throws -> String {
        try XCTUnwrap(KnownWordsList(markdown: markdown).adding(addition, on: today))
    }

    func testANewConfirmedFormGoesRightAfterTheLastLineWithTheSameRightForm() throws {
        let markdown = """
        ## Companies
        - Convio → **Konvio** ✓
        - Brightlane → **Brytlane**
        - Q-R-S → **QRS** ✓ · Gonvio → **Konvio** (provisional)
        - Kworix → **Quorix**

        """

        XCTAssertEqual(try adding(.replacement(heard: "Konvya", right: "Konvio", confirmed: true), to: markdown), """
        ## Companies
        - Convio → **Konvio** ✓
        - Brightlane → **Brytlane**
        - Q-R-S → **QRS** ✓ · Gonvio → **Konvio** (provisional)
        - Konvya → **Konvio** ✓ confirmed 2026-10-28 by Ku-Ka
        - Kworix → **Quorix**

        """)
    }

    func testANewFormGoesAfterTheIndentedLinesUnderThatBullet() throws {
        let konvya = try KnownWordAddition.replacement(heard: "Konvya", right: "Konvio", confirmed: true)
        let line = "- Konvya → **Konvio** ✓ confirmed 2026-10-28 by Ku-Ka\n"

        XCTAssertEqual(try adding(konvya, to: """
        - Convio → **Konvio** ✓
          - heard on the vendor call
            more about it

          after an empty line

        - Yuri → **Jyri**

        """), """
        - Convio → **Konvio** ✓
          - heard on the vendor call
            more about it

          after an empty line
        \(line)
        - Yuri → **Jyri**

        """)

        XCTAssertEqual(try adding(konvya, to: """
        - Kworix → **Quorix**
          - Gonvio → **Konvio**
          - a note at the same depth

        """), """
        - Kworix → **Quorix**
          - Gonvio → **Konvio**
        \(line)  - a note at the same depth

        """, "a line at the bullet's own depth is not under it")
    }

    func testAWordWithNoLineYetGoesUnderAddedByKuKaWhichIsAddedOnce() throws {
        let fixture = KnownWordsListTests.fixture

        let first = try adding(.replacement(heard: "Maiki", right: "Maikki", confirmed: true), to: fixture)

        XCTAssertEqual(first, fixture + """

        ## Added by Ku-Ka

        - Maiki → **Maikki** ✓ confirmed 2026-10-28 by Ku-Ka

        """)

        let laterSection = "\n## Notes\n\n- a note\n"
        let second = try adding(.replacement(heard: "Iita", right: "Iida", confirmed: true), to: first + laterSection)

        XCTAssertEqual(second, first + "- Iita → **Iida** ✓ confirmed 2026-10-28 by Ku-Ka\n" + laterSection)
    }

    func testAProvisionalAnswerWritesTheOrdinaryWordsLine() throws {
        XCTAssertEqual(try adding(.replacement(heard: "my key", right: "Maikki", confirmed: false), to: "- Maiki → **Maikki** ✓\n"), """
        - Maiki → **Maikki** ✓
        - my key → **Maikki** (provisional: ordinary words, so only the summary checks it; added by Ku-Ka 2026-10-28)

        """)
    }

    func testCorrectAsHeardGoesAtTheEndOfItsOwnSectionWhichIsAddedOnce() throws {
        let fixture = KnownWordsListTests.fixture

        let first = try adding(.correctAsHeard("Aino"), to: fixture)

        XCTAssertEqual(first, fixture + """

        ## Correct as heard

        - **Aino** (correct as heard; added by Ku-Ka 2026-10-28)

        """)

        let laterSection = "\n## Notes\n\n- a note\n"
        let second = try adding(.correctAsHeard("Iida"), to: first + laterSection)

        XCTAssertEqual(second, first + "- **Iida** (correct as heard; added by Ku-Ka 2026-10-28)\n" + laterSection)
        XCTAssertEqual(try adding(.correctAsHeard("Aino"), to: "### correct AS heard\n- Iida\n\n## People\n"),
                       "### correct AS heard\n- Iida\n- **Aino** (correct as heard; added by Ku-Ka 2026-10-28)\n\n## People\n",
                       "the user's own section, in any case and at any level")
    }

    func testRemovingTheInsertedLinesGivesTheListBackByteForByte() throws {
        let fixture = KnownWordsListTests.fixture
        let additions: [(KnownWordAddition, inserted: [String])] = [
            (try .replacement(heard: "Konvya", right: "Konvio", confirmed: true),
             ["- Konvya → **Konvio** ✓ confirmed 2026-10-28 by Ku-Ka"]),
            (try .replacement(heard: "Maiki", right: "Maikki", confirmed: true),
             ["", "## Added by Ku-Ka", "", "- Maiki → **Maikki** ✓ confirmed 2026-10-28 by Ku-Ka"]),
            (try .replacement(heard: "my key", right: "Jyri", confirmed: false),
             ["- my key → **Jyri** (provisional: ordinary words, so only the summary checks it; added by Ku-Ka 2026-10-28)"]),
            (try .correctAsHeard("Aino"),
             ["", "## Correct as heard", "", "- **Aino** (correct as heard; added by Ku-Ka 2026-10-28)"]),
        ]

        for (addition, inserted) in additions {
            XCTAssertEqual(try removing(inserted, from: adding(addition, to: fixture)), fixture, "\(inserted)")
        }
    }

    func testEveryLineThatAddingWritesReadsBackAsTheEntryItMeant() throws {
        let fixture = KnownWordsListTests.fixture
        let before = KnownWordsList(markdown: fixture)

        let confirmed = KnownWordsList(markdown: try adding(.replacement(heard: "Konvya", right: "Konvio", confirmed: true), to: fixture))
        XCTAssertEqual(confirmed.words.first?.heard.last, HeardForm(phrase: try XCTUnwrap(Phrase("Konvya")), isConfirmed: true))
        XCTAssertEqual(confirmed.corrector.correct("Ask Konvya").text, "Ask Konvio")
        XCTAssertEqual(Array(confirmed.words.dropFirst()), Array(before.words.dropFirst()))

        let new = KnownWordsList(markdown: try adding(.replacement(heard: "Maiki", right: "Maikki", confirmed: true), to: fixture))
        XCTAssertEqual(new.words, before.words + [
            KnownWord(right: "Maikki", heard: [HeardForm(phrase: try XCTUnwrap(Phrase("Maiki")), isConfirmed: true)]),
        ])

        let provisional = KnownWordsList(markdown: try adding(.replacement(heard: "my key", right: "Maikki", confirmed: false), to: fixture))
        XCTAssertEqual(provisional.words, before.words + [
            KnownWord(right: "Maikki", heard: [HeardForm(phrase: try XCTUnwrap(Phrase("my key")), isConfirmed: false)]),
        ])
        XCTAssertEqual(provisional.corrector.correct("my key point").text, "my key point")

        let heard = KnownWordsList(markdown: try adding(.correctAsHeard("Aino"), to: fixture))
        XCTAssertEqual(heard.correctAsHeard.map(\.text), ["Aino"])
        XCTAssertEqual(heard.words, before.words)
    }

    func testAnAnswerTheListAlreadyHasAddsNothing() throws {
        let list = KnownWordsList(markdown: KnownWordsListTests.fixture + "\n## Correct as heard\n- Aino\n")

        XCTAssertNil(list.adding(try .replacement(heard: "kon vio", right: "Konvio", confirmed: true), on: today),
                     "the same confirmed pair, case ignored")
        XCTAssertNil(list.adding(try .replacement(heard: "Q-R-S", right: "QRS", confirmed: true), on: today))
        XCTAssertNil(list.adding(try .replacement(heard: "Yuri", right: "Jyri", confirmed: false), on: today),
                     "a provisional answer for a form that the list has")
        XCTAssertNil(list.adding(try .correctAsHeard("AINO"), on: today))
        XCTAssertNotNil(list.adding(try .replacement(heard: "Kon Vio", right: "Konvia", confirmed: true), on: today),
                        "the same form for another right form")

        let saved = try adding(.replacement(heard: "Maiki", right: "Maikki", confirmed: true), to: KnownWordsListTests.fixture)
        XCTAssertNil(KnownWordsList(markdown: saved).adding(try .replacement(heard: "Maiki", right: "Maikki", confirmed: true), on: today),
                     "an answer saved twice writes once")
    }

    func testAConfirmedAnswerForAProvisionalFormAddsALineThatConfirmsIt() throws {
        let fixture = KnownWordsListTests.fixture

        let result = try adding(.replacement(heard: "yuri", right: "Jyri", confirmed: true), to: fixture)

        XCTAssertEqual(result, fixture.replacingOccurrences(
            of: "- Yuri → **Jyri** (Lahtinen) (provisional)\n",
            with: "- Yuri → **Jyri** (Lahtinen) (provisional)\n- yuri → **Jyri** ✓ confirmed 2026-10-28 by Ku-Ka\n"))
        XCTAssertEqual(KnownWordsList(markdown: result).words.last?.heard,
                       [HeardForm(phrase: try XCTUnwrap(Phrase("Yuri")), isConfirmed: true)])
    }

    func testACRLFListKeepsCRLFAndItsNewLinesUseIt() throws {
        let fixture = KnownWordsListTests.fixture
        let crlf = fixture.replacingOccurrences(of: "\n", with: "\r\n")

        for addition in [
            try KnownWordAddition.replacement(heard: "Konvya", right: "Konvio", confirmed: true),
            try .replacement(heard: "Maiki", right: "Maikki", confirmed: true),
            try .correctAsHeard("Aino"),
        ] {
            XCTAssertEqual(try adding(addition, to: crlf),
                           try adding(addition, to: fixture).replacingOccurrences(of: "\n", with: "\r\n"))
        }
        XCTAssertEqual(try adding(.replacement(heard: "Konvya", right: "Konvio", confirmed: true),
                                  to: "- Convio → **Konvio**\r\n- Yuri → **Jyri**\n"),
                       "- Convio → **Konvio**\r\n- Konvya → **Konvio** ✓ confirmed 2026-10-28 by Ku-Ka\r\n- Yuri → **Jyri**\n",
                       "the ending of the first line that has one")
    }

    func testALastLineWithoutALineEndingGetsOneBeforeTheNewLine() throws {
        let konvya = try KnownWordAddition.replacement(heard: "Konvya", right: "Konvio", confirmed: true)

        XCTAssertEqual(try adding(konvya, to: "## Companies\n- Convio → **Konvio** ✓"),
                       "## Companies\n- Convio → **Konvio** ✓\n- Konvya → **Konvio** ✓ confirmed 2026-10-28 by Ku-Ka\n")
        XCTAssertEqual(try adding(.correctAsHeard("Aino"), to: "- Convio → **Konvio**\r\n**Rule:** none"),
                       "- Convio → **Konvio**\r\n**Rule:** none\r\n\r\n## Correct as heard\r\n\r\n"
                           + "- **Aino** (correct as heard; added by Ku-Ka 2026-10-28)\r\n")
        XCTAssertEqual(try adding(konvya, to: "- Convio → **Konvio**\n- Yuri → **Jyri**"),
                       "- Convio → **Konvio**\n- Konvya → **Konvio** ✓ confirmed 2026-10-28 by Ku-Ka\n- Yuri → **Jyri**",
                       "a last line that no line goes after keeps its missing ending")
    }

    func testAnEmptyListStartsWithTheNewFileHeader() throws {
        XCTAssertEqual(KnownWordsList.newFileHeader, """
        # Known words

        Ku-Ka reads this list before it writes meeting notes, and adds to it when you answer Check Words. You can edit it in any text editor.

        Each line is: what speech recognition wrote → **the right form**. Separate several wrong forms with " / ". Ku-Ka replaces a wrong form in the transcript only when the line has ✓. Lines without ✓ only help the summary. Words under "Correct as heard" are right as written.

        """)
        XCTAssertEqual(try adding(.replacement(heard: "Konvya", right: "Konvio", confirmed: true), to: ""),
                       KnownWordsList.newFileHeader + "\n## Added by Ku-Ka\n\n- Konvya → **Konvio** ✓ confirmed 2026-10-28 by Ku-Ka\n")
        XCTAssertEqual(try adding(.correctAsHeard("Aino"), to: ""),
                       KnownWordsList.newFileHeader + "\n## Correct as heard\n\n- **Aino** (correct as heard; added by Ku-Ka 2026-10-28)\n")
        XCTAssertTrue(KnownWordsList(markdown: KnownWordsList.newFileHeader).words.isEmpty, "the header itself has no entry")
    }

    func testTheFactoriesRejectTextThatTheListWouldReadDifferently() throws {
        let rejected: [(text: String, error: KnownWordAdditionError)] = [
            ("", .empty), ("  ", .empty), (" -- ", .empty),
            ("Kon\nVio", .lineBreak), ("Kon\r\nVio", .lineBreak),
            ("Kon**vio", .unsupported("*")), ("Konvio*", .unsupported("*")),
            ("Kon→vio", .unsupported("→")), ("Kon->vio", .unsupported("->")),
            ("Kon · Vio", .unsupported(" · ")), ("Kon / Vio", .unsupported(" / ")),
        ]

        for (text, error) in rejected {
            XCTAssertThrowsError(try KnownWordAddition.replacement(heard: text, right: "Konvio", confirmed: true)) {
                XCTAssertEqual($0 as? KnownWordAdditionError, error, "heard \(text.debugDescription)")
            }
            XCTAssertThrowsError(try KnownWordAddition.replacement(heard: "Konvya", right: text, confirmed: false)) {
                XCTAssertEqual($0 as? KnownWordAdditionError, error, "right \(text.debugDescription)")
            }
            XCTAssertThrowsError(try KnownWordAddition.correctAsHeard(text)) {
                XCTAssertEqual($0 as? KnownWordAdditionError, error, "correct as heard \(text.debugDescription)")
            }
        }
    }

    func testAHeardFormOrCorrectAsHeardWordCannotHaveAParenthesisButARightFormCan() throws {
        XCTAssertThrowsError(try KnownWordAddition.replacement(heard: "Konvio (Oy)", right: "Konvio", confirmed: true)) {
            XCTAssertEqual($0 as? KnownWordAdditionError, .unsupported("("))
        }
        XCTAssertThrowsError(try KnownWordAddition.correctAsHeard("Aino)")) {
            XCTAssertEqual($0 as? KnownWordAdditionError, .unsupported(")"))
        }

        let addition = try KnownWordAddition.replacement(heard: " Konvya ", right: "Konvio (Oy)\n", confirmed: true)

        XCTAssertEqual(addition.kind, .replacement(heard: try XCTUnwrap(Phrase("Konvya")), right: "Konvio (Oy)", confirmed: true),
                       "both are trimmed")
        XCTAssertEqual(KnownWordsList(markdown: try adding(addition, to: "")).words.map(\.right), ["Konvio (Oy)"])
    }

    func testTheErrorsSayWhatToChange() {
        XCTAssertEqual(KnownWordAdditionError.empty.localizedDescription, "Type the right word first.")
        XCTAssertEqual(KnownWordAdditionError.lineBreak.localizedDescription, "Ku-Ka cannot save a word with a line break in it.")
        XCTAssertEqual(KnownWordAdditionError.unsupported(" / ").localizedDescription, "Ku-Ka cannot save a word with “ / ” in it.")
    }

    /// `text` without `block`, a run of whole lines that must occur in it once.
    private func removing(_ block: [String], from text: String) throws -> String {
        var lines = text.components(separatedBy: "\n")
        let starts = lines.indices.filter { Array(lines[$0...].prefix(block.count)) == block }
        XCTAssertEqual(starts.count, 1, "the inserted lines occur \(starts.count) times")
        let start = try XCTUnwrap(starts.first)
        lines.removeSubrange(start..<start + block.count)
        return lines.joined(separator: "\n")
    }
}
