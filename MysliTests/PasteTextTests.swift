import XCTest
@testable import Mysli

final class PasteTextTests: XCTestCase {
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
