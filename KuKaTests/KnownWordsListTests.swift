import XCTest
@testable import KuKa

final class KnownWordsListTests: XCTestCase {
    static let fixture = """
    ---
    name: term-corrections
    description: "Terms that speech recognition gets wrong"
    ---

    Speech recognition garbles our terms. **Left = what it may write, Right = the right form.**
    Only lines marked ✓ are fixed without a question.

    ## Companies
    - Convio / Konvia / Gonvio / **Kon Vio** → **Konvio** (Kon Vio ✓ confirmed 2026-09-02)
    - Brightlane / Bright Lane → **Brytlane** (provisional; note: "Brightline" is another company, do NOT rewrite Brightline→Brytlane)
    - **QRX** → **Quorix** (heard on the vendor call; ✓ confirmed 2026-09-10)
    - "zeta hub API" / stray **zeta** prefix → the term is the **Hub API**. Drop the "zeta". ✓ confirmed 2026-09-12.

    ## Terms
    - Q-R-S → **QRS** ✓ · T-U-V → **TUV** (provisional)
    - **Bay1 / Bay2** → **Alpha Bay 1 / Alpha Bay 2** (lab rooms). ✓ confirmed 2026-09-15.
    - **Floxen** → unknown term, not real per the user; **drop it** unless it proves real. (provisional)

    ## People
    - Yuri → **Jyri** (Lahtinen) (provisional)
    - (append name corrections here)

    **Rule:** keep a company name as the company itself writes it.

    """

    private let fixtureList = KnownWordsList(markdown: fixture)

    private func word(_ right: String, in list: KnownWordsList) throws -> KnownWord {
        try XCTUnwrap(list.words.first { $0.right == right }, "no word \(right)")
    }

    private func heardForms(of right: String, in list: KnownWordsList) throws -> [String] {
        try word(right, in: list).heard.map(\.phrase.text)
    }

    private func confirmedForms(of right: String, in list: KnownWordsList) throws -> [String] {
        try word(right, in: list).heard.filter(\.isConfirmed).map(\.phrase.text)
    }

    func testTheFixtureGivesExactlyItsSixWords() {
        XCTAssertEqual(fixtureList.words.map(\.right), ["Konvio", "Brytlane", "Quorix", "QRS", "TUV", "Jyri"])
    }

    func testATailOfOnlyACheckMarkConfirmsEveryFormOfItsSegment() throws {
        let list = KnownWordsList(markdown: "- Kon Vio / Konvia → **Konvio** ✓\n")

        XCTAssertEqual(try confirmedForms(of: "Konvio", in: list), ["Kon Vio", "Konvia"])
        XCTAssertEqual(try confirmedForms(of: "QRS", in: fixtureList), ["Q-R-S"])
    }

    func testACheckMarkAfterASemicolonConfirmsTheWholeSegment() throws {
        let list = KnownWordsList(markdown: "- Quorx / Kworix → **Quorix** (heard on the vendor call; ✓ confirmed 2026-09-10)\n")

        XCTAssertEqual(try confirmedForms(of: "Quorix", in: list), ["Quorx", "Kworix"])
        XCTAssertEqual(try word("Quorix", in: fixtureList).heard.map(\.isConfirmed), [true])
    }

    func testACheckMarkAfterOneHeardFormConfirmsOnlyThatForm() throws {
        let list = KnownWordsList(markdown: """
        - Convio / Konvia / Kon Vio → **Konvio** (Kon Vio ✓ confirmed 2026-09-02)
        - Brightlane / Bright Lane → **Brytlane** (bright lane ✔ confirmed)
        - Yuri / Juri → **Jyri** (the user ✓ said so)
        """)

        XCTAssertEqual(try heardForms(of: "Konvio", in: list), ["Convio", "Konvia", "Kon Vio"])
        XCTAssertEqual(try confirmedForms(of: "Konvio", in: list), ["Kon Vio"])
        XCTAssertEqual(try confirmedForms(of: "Brytlane", in: list), ["Bright Lane"], "✔ counts, and case is ignored")
        XCTAssertEqual(try confirmedForms(of: "Jyri", in: list), [], "other text before the mark")
        XCTAssertEqual(try word("Konvio", in: fixtureList).heard.map(\.isConfirmed), [false, false, false, true])
    }

    func testALineWithoutACheckMarkIsProvisional() throws {
        XCTAssertEqual(try heardForms(of: "Jyri", in: fixtureList), ["Yuri"])
        XCTAssertEqual(try confirmedForms(of: "Jyri", in: fixtureList), [])
    }

    func testABulletSplitsIntoEntriesAtAMiddleDot() throws {
        XCTAssertEqual(try confirmedForms(of: "QRS", in: fixtureList), ["Q-R-S"])
        XCTAssertEqual(try heardForms(of: "TUV", in: fixtureList), ["T-U-V"])
        XCTAssertEqual(try confirmedForms(of: "TUV", in: fixtureList), [])

        let list = KnownWordsList(markdown: """
        - Q-R-S → **QRS** ✓ · and some prose
        - T-U-V → **TUV** (one · two)
        """)
        XCTAssertEqual(list.words.map(\.right), ["TUV"], "a bullet counts only when every segment is understood")
    }

    func testTheFirstArrowSplitsASegmentAndAnArrowInTheTailIsNot() throws {
        XCTAssertEqual(try heardForms(of: "Brytlane", in: fixtureList), ["Brightlane", "Bright Lane"])
        XCTAssertEqual(try confirmedForms(of: "Brytlane", in: fixtureList), [])

        let list = KnownWordsList(markdown: "- Konvya -> **Konvio** (not Konvio->Konvia)\n")
        XCTAssertEqual(try heardForms(of: "Konvio", in: list), ["Konvya"])
    }

    func testBoldAndQuotesAroundHeardFormsAreRemoved() throws {
        XCTAssertEqual(try heardForms(of: "Konvio", in: fixtureList), ["Convio", "Konvia", "Gonvio", "Kon Vio"])
        XCTAssertEqual(try heardForms(of: "Quorix", in: fixtureList), ["QRX"])

        let list = KnownWordsList(markdown: """
        - "Konvya" / “Kon-Vio” / 'Konvi' / **"Gonvia"** → **Konvio**
        - **Bay One / Bay Two** → **Alpha Bay**
        """)
        XCTAssertEqual(try heardForms(of: "Konvio", in: list), ["Konvya", "Kon-Vio", "Konvi", "Gonvia"])
        XCTAssertEqual(try heardForms(of: "Alpha Bay", in: list), ["Bay One", "Bay Two"], "the whole heard side in bold")
    }

    func testABulletWithAFormKuKaCannotReadHasNoEffect() {
        let list = KnownWordsList(markdown: """
        - → **Konvio**
        - Convio /  / Konvia → **Konvio**
        - Convio (old) / Konvia → **Konvio**
        - Convio → ****
        - Convio → **--**
        - Convio → **Konvio**
        """)

        XCTAssertEqual(list.words, [
            KnownWord(right: "Konvio", heard: [HeardForm(phrase: Phrase("Convio")!, isConfirmed: false)]),
        ])
    }

    func testFrontMatterAndCodeBlocksAreNeverRead() {
        let list = KnownWordsList(markdown: """
        ---
        name: term-corrections
        aliases:
          - Konvya → **Front**
        ---
        - Convio → **Konvio**
        ```markdown
        - Kworix → **Backticks**
        ```
        ~~~
        - Kworix → **Tildes**
        ```
        - Kworix → **Still Tildes**
        ~~~
        ---
        - Yuri → **Jyri**
        """)

        XCTAssertEqual(list.words.map(\.right), ["Konvio", "Jyri"])
    }

    func testAnUnclosedFrontMatterMeansNoEntries() {
        XCTAssertEqual(KnownWordsList(markdown: "---\nname: list\n- Convio → **Konvio**\n").words, [])
    }

    func testABulletMayBeIndentedAndUseAnyMarker() {
        let list = KnownWordsList(markdown: """
          - Yuri → **Jyri**
        * Convio → **Konvio**
        + Kworix → **Quorix**
        -Gonvio → **Not A Bullet**
        **Rule:** Konvya → **Not A Bullet Either**
        """)

        XCTAssertEqual(list.words.map(\.right), ["Jyri", "Konvio", "Quorix"])
    }

    func testOnlyAHeadingOfOneToSixMarksAndASpaceStartsOrEndsCorrectAsHeard() {
        let list = KnownWordsList(markdown: """
        - Convio → **Konvio**
        ###### correct as heard
        - Aino
        #NoSpace
        - Iida
        ####### Seven
        - Maikki
        ### Names
        - Yuri → **Jyri**
        - Pekka
        """)

        XCTAssertEqual(list.correctAsHeard.map(\.text), ["Aino", "Iida", "Maikki"])
        XCTAssertEqual(list.words.map(\.right), ["Konvio", "Jyri"])
    }

    func testBulletsUnderCorrectAsHeardAreCorrectAsHeardWords() {
        let list = KnownWordsList(markdown: """
        ## Correct As Heard
        - **Aino** (correct as heard; added by Ku-Ka 2026-10-28)
        - Iida
        - "Maikki".
        - Ravi Indra (a colleague in the lab)
        - (add words here)
        - Konvya → **Konvio**
        - iida (twice, so listed once)
        ## People
        - Yuri → **Jyri**
        - Pekka
        """)

        XCTAssertEqual(list.correctAsHeard.map(\.text), ["Aino", "Iida", "Maikki", "Ravi Indra"])
        XCTAssertEqual(list.words.map(\.right), ["Jyri"])
    }

    func testLinesWithTheSameRightFormMerge() throws {
        let list = KnownWordsList(markdown: """
        ## Companies
        - Convio / Konvia → **Konvio**
        ## Terms
        - konvia / Kon Vio → **Konvio** (konvia ✓ confirmed)
        - Q-R-S → **QRS**
        - Gonvio / GONVIO / Convio → **Konvio**
        """)

        XCTAssertEqual(list.words.map(\.right), ["Konvio", "QRS"])
        XCTAssertEqual(try heardForms(of: "Konvio", in: list), ["Convio", "Konvia", "Kon Vio", "Gonvio"])
        XCTAssertEqual(try confirmedForms(of: "Konvio", in: list), ["Konvia"])
    }

    func testEmptyTextLineBreaksAndCRLFReadWithoutACrash() {
        XCTAssertEqual(KnownWordsList(markdown: "").words, [])
        XCTAssertEqual(KnownWordsList(markdown: "\n\n\r\n\r\n").words, [])

        let markdown = Self.fixture + "\n## Correct as heard\n- Aino\n"
        let crlf = KnownWordsList(markdown: markdown.replacingOccurrences(of: "\n", with: "\r\n"))
        XCTAssertEqual(crlf, KnownWordsList(markdown: markdown))
        XCTAssertEqual(crlf.words.count, 6)
    }

    func testTheCorrectorReplacesOnlyConfirmedFormsThatNothingElseClaims() {
        let list = KnownWordsList(markdown: """
        - Convio / Konvia → **Konvio** (Convio ✓)
        - Kworix / Quorx → **Quorix** ✓
        - Quorx → **Kworks** ✓
        - Konvio / jyri → **Konvio Group** ✓
        - Yuri → **Jyri** ✓
        - Aino → **Aina** ✓
        ## Correct as heard
        - Aino
        """)

        let result = list.corrector.correct("Convio Konvia Kworix Quorx Konvio jyri Yuri Aino")

        XCTAssertEqual(result.text, "Konvio Konvia Quorix Quorx Konvio jyri Jyri Aino")
        XCTAssertEqual(result.applied, [
            AppliedCorrection(heard: "Convio", right: "Konvio", count: 1),
            AppliedCorrection(heard: "Kworix", right: "Quorix", count: 1),
            AppliedCorrection(heard: "Yuri", right: "Jyri", count: 1),
        ])
    }

    func testAConfirmedFormThatDiffersFromItsOwnRightFormOnlyInCaseIsReplaced() {
        let list = KnownWordsList(markdown: """
        - chatgpt → **ChatGPT** ✓ confirmed 2026-10-28 by Ku-Ka
        - quorix → **Quorix AI** ✓
        - Qworks → **Quorix** ✓
        - aino → **AINO** ✓
        ## Correct as heard
        - Aino
        """)

        let result = list.corrector.correct("Ask chatgpt and ChatGPT about quorix and aino.")

        XCTAssertEqual(result.text, "Ask ChatGPT and ChatGPT about quorix and aino.",
                       "not a form that is the right form of another word, or correct as heard")
        XCTAssertEqual(result.applied, [AppliedCorrection(heard: "chatgpt", right: "ChatGPT", count: 1)])
    }

    func testKnowsEveryFormRightFormAndCorrectAsHeardWordWhateverItsCase() {
        let list = KnownWordsList(markdown: Self.fixture + "\n## Correct as heard\n- Aino\n")

        XCTAssertTrue(list.knows("convio"), "a provisional form")
        XCTAssertTrue(list.knows("KON VIO"), "a confirmed form")
        XCTAssertTrue(list.knows("konvio"), "a right form")
        XCTAssertTrue(list.knows("Aino"), "a correct-as-heard word")
        XCTAssertFalse(list.knows("Maikki"))
        XCTAssertFalse(list.knows("Kon"), "part of a form")
        XCTAssertFalse(list.knows(""))
    }

    func testRelevantKeepsTheWordsAndCorrectAsHeardWordsThatOccurAsWholeTokensInListOrder() {
        let list = KnownWordsList(markdown: Self.fixture + "\n## Correct as heard\n- Aino\n- Iida\n")

        let relevant = list.relevant(to: "Jyri said Brightlane's plan suits konvio. Aino agreed, but Quorixes and Iidaho did not.")

        XCTAssertEqual(relevant.words.map(\.right), ["Konvio", "Brytlane", "Jyri"])
        XCTAssertEqual(relevant.correctAsHeard, ["Aino"])
    }
}
