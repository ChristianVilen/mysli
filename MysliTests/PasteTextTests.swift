import XCTest
@testable import Mysli

final class PasteTextTests: XCTestCase {
    func testRejectsEmptyAndRemovesOnlyTrailingLineBreaks() {
        XCTAssertNil(PasteText("\n\r\n"))
        XCTAssertNil(PasteText("   \n"))
        XCTAssertEqual(PasteText("line one\nline two\r\n")?.value, "line one\nline two")
        XCTAssertEqual(PasteText(" word ")?.value, " word ")
    }
}
