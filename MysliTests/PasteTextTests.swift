import XCTest
@testable import Mysli

final class PasteTextTests: XCTestCase {
    func testRejectsUnsafeControlsAndPreservesPrintableUnicode() {
        for scalar in ["\u{0000}", "\u{0001}", "\u{001B}", "\u{007F}", "\u{0080}", "\u{009F}"] {
            XCTAssertNil(PasteText("I am" + scalar + " ready."))
        }
        XCTAssertEqual(PasteText("  Café 👩‍💻 ❤️ 中文\tready\r\nnow\u{000B}yes\u{000C}ok\u{0085}done  ")?.value,
                       "Café 👩‍💻 ❤️ 中文 ready now yes ok done")
        XCTAssertEqual(PasteText("Keep\u{00A0}together")?.value, "Keep\u{00A0}together")
        XCTAssertEqual(PasteText(#"printf 'hello\n'"#)?.value, #"printf 'hello\n'"#)
    }

    func testRejectsEmptyAndProducesTrimmedSingleLineText() {
        XCTAssertNil(PasteText("\n\r\n"))
        XCTAssertNil(PasteText("   \n"))
        XCTAssertEqual(PasteText("line one\nline two\r\n")?.value, "line one line two")
        XCTAssertEqual(PasteText(" word ")?.value, "word")
        XCTAssertEqual(PasteText("git push\n ")?.value, "git push")
        XCTAssertEqual(PasteText("one\r\ntwo\nthree\rfour")?.value, "one two three four")
        XCTAssertNil(PasteText("\n \t"))
    }
}
