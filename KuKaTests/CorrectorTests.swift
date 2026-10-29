import XCTest
@testable import KuKa

final class CorrectorTests: XCTestCase {
    private func corrector(_ pairs: KeyValuePairs<String, String>) throws -> Corrector {
        Corrector(replacements: try pairs.map { heard, right in
            Replacement(heard: try XCTUnwrap(Phrase(heard)), right: right)
        })
    }

    private func corrected(_ text: String, _ pairs: KeyValuePairs<String, String>) throws -> String {
        try corrector(pairs).correct(text).text
    }

    func testAConfirmedFormIsReplacedWithTheListsSpellingWhateverItsCase() throws {
        XCTAssertEqual(try corrected("convio, CONVIO, and Convio", ["Convio": "Konvio"]), "Konvio, Konvio, and Konvio")
    }

    func testOnlyWholeTokensMatch() throws {
        XCTAssertEqual(try corrected("Ida flew to Idaho.", ["Ida": "Iida"]), "Iida flew to Idaho.")
        XCTAssertEqual(try corrected("The errors and the error states", ["error": "arrow"]),
                       "The errors and the arrow states")
    }

    func testHyphensBelongToTheToken() throws {
        let pairs: KeyValuePairs = ["acme-opsdocks": "acme-ops-docs"]

        XCTAssertEqual(try corrected("Open acme-opsdocks now", pairs), "Open acme-ops-docs now")
        XCTAssertEqual(try corrected("Open acme-opsdocks-v2 now", pairs), "Open acme-opsdocks-v2 now")
    }

    func testApostrophesInsideAWordBelongToTheToken() throws {
        XCTAssertEqual(try corrected("I don't know, Don.", ["Don": "Donn"]), "I don't know, Donn.")
        XCTAssertEqual(try corrected("I don’t know, Don.", ["Don": "Donn"]), "I don’t know, Donn.")
    }

    func testAFormOfSeveralWordsMatchesAnyWhitespaceBetweenItsTokensButNotPunctuation() throws {
        let pairs: KeyValuePairs = ["Kon Vio": "Konvio"]

        XCTAssertEqual(try corrected("Ask Kon  Vio.", pairs), "Ask Konvio.")
        XCTAssertEqual(try corrected("Ask Kon\nVio.", pairs), "Ask Konvio.")
        XCTAssertEqual(try corrected("Ask Kon, Vio.", pairs), "Ask Kon, Vio.")
    }

    func testAPossessiveStays() throws {
        let pairs: KeyValuePairs = ["Convio": "Konvio", "Kon Vio": "Konvio"]

        XCTAssertEqual(try corrected("Convio's plan", pairs), "Konvio's plan")
        XCTAssertEqual(try corrected("Convio’s plan", pairs), "Konvio’s plan")
        XCTAssertEqual(try corrected("Kon Vio's plan", pairs), "Konvio's plan")
    }

    func testQuotesAndApostrophesAtATokensEndsDoNotBlockAMatch() throws {
        let pairs: KeyValuePairs = ["Convio": "Konvio"]

        XCTAssertEqual(try corrected("They said 'Convio' twice", pairs), "They said 'Konvio' twice")
        XCTAssertEqual(try corrected("They said ‘Convio’ twice", pairs), "They said ‘Konvio’ twice")
        XCTAssertEqual(try corrected("Convio- or not", pairs), "Konvio- or not")
    }

    func testTheFormWithTheMostTokensWinsAtAPlace() throws {
        XCTAssertEqual(try corrected("Kon Vio and Kon", ["Kon": "Konn", "Kon Vio": "Konvio"]), "Konvio and Konn")
    }

    func testOnEqualTokensTheLongestFormWins() throws {
        XCTAssertEqual(try corrected("Yuri's notes", ["Yuri": "Jyri", "Yuri's": "Jyri's own"]), "Jyri's own notes")
    }

    func testReplacedTextIsNeverMatchedAgain() throws {
        XCTAssertEqual(try corrected("Aaro Bertta", ["Aaro": "Bertta", "Bertta": "Cecilia"]), "Bertta Cecilia")
    }

    func testTextIsComparedInNFCButDiacriticsMustMatch() throws {
        let composed = "M\u{E4}ki"
        let decomposed = "Ma\u{308}ki"

        XCTAssertEqual(try corrected("Ask \(decomposed) today", [composed: "Mäkinen"]), "Ask Mäkinen today")
        XCTAssertEqual(try corrected("Ask \(composed) today", [decomposed: "Mäkinen"]), "Ask Mäkinen today")
        XCTAssertEqual(try corrected("Ask Maki today", [composed: "Mäkinen"]), "Ask Maki today")
    }

    func testAppliedListsEachHeardFormOnceWithItsCountInTheOrderOfFirstMatch() throws {
        let corrector = try corrector(["Convio": "Konvio", "Yuri": "Jyri", "Kon Vio": "Konvio"])

        let result = corrector.correct("Yuri met convio. CONVIO and Kon Vio called Yuri. Convio's turn.")

        XCTAssertEqual(result.text, "Jyri met Konvio. Konvio and Konvio called Jyri. Konvio's turn.")
        XCTAssertEqual(result.applied, [
            AppliedCorrection(heard: "Yuri", right: "Jyri", count: 2),
            AppliedCorrection(heard: "Convio", right: "Konvio", count: 3),
            AppliedCorrection(heard: "Kon Vio", right: "Konvio", count: 1),
        ])
    }

    func testTextWithoutAMatchComesBackByteForByte() throws {
        let text = "Ma\u{308}ki said:\r\n  \u{201C}Hello\u{201D}\t \n"

        let result = try corrector(["Convio": "Konvio"]).correct(text)

        XCTAssertEqual(Array(result.text.utf8), Array(text.utf8))
        XCTAssertEqual(result.applied, [])
    }

    func testTextThatIsAlreadyTheRightFormStaysByteForByteAndIsNotCounted() throws {
        let corrector = try corrector(["chatgpt": "ChatGPT", "mäki": "M\u{E4}ki"])

        let result = corrector.correct("Ask ChatGPT, then chatgpt and CHATGPT.")
        let decomposed = "Ask Ma\u{308}ki and ChatGPT's team."
        let unchanged = corrector.correct(decomposed)

        XCTAssertEqual(result.text, "Ask ChatGPT, then ChatGPT and ChatGPT.")
        XCTAssertEqual(result.applied, [AppliedCorrection(heard: "chatgpt", right: "ChatGPT", count: 2)])
        XCTAssertEqual(Array(unchanged.text.utf8), Array(decomposed.utf8))
        XCTAssertEqual(unchanged.applied, [])
    }

    func testAPhraseWithoutATokenCannotExist() {
        XCTAssertNil(Phrase(""))
        XCTAssertNil(Phrase(" -- "))
        XCTAssertNil(Phrase("' ’ -"))
    }

    func testFoldIgnoresCaseTheCurlyApostropheRunsOfWhitespaceAndComposition() {
        XCTAssertEqual(Phrase.fold("  Konvio’s\t PLAN\n\nis  Ma\u{0308}ki's "), "konvio's plan is mäki's")
        XCTAssertEqual(Array(Phrase.fold("Ma\u{0308}ki").unicodeScalars), Array("mäki".precomposedStringWithCanonicalMapping.unicodeScalars))
    }
}
