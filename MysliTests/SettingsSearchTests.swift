import XCTest
@testable import Mysli

final class SettingsSearchTests: XCTestCase {
    func testExactLabelsRankBeforeDescriptionsAndPageContext() {
        let items = [
            SettingsSearchItem(page: .meetings, title: "Background file", detail: "Calendar reminders use this page."),
            SettingsSearchItem(page: .meetings, title: "Calendar reminders"),
            SettingsSearchItem(page: .permissions, title: "Calendar access", keywords: ["reminders"])
        ]
        XCTAssertEqual(SettingsSearch.matches("calendar reminders", in: items), [1, 2, 0])
    }

    func testAllWordsCanMatchLabelsAliasesAndPageNamesInAnyOrder() {
        let items = [
            SettingsSearchItem(page: .meetings, title: "Teams speaker names", keywords: ["people"]),
            SettingsSearchItem(page: .dictation, title: "Hold to dictate", keywords: ["voice speech"])
        ]
        XCTAssertEqual(SettingsSearch.matches("names meet", in: items), [0])
        XCTAssertEqual(SettingsSearch.matches("voice dict", in: items), [1])
        XCTAssertEqual(SettingsSearch.matches("people calendar", in: items), [])
    }

    func testNormalizesCaseAccentsPunctuationAndWhitespace() {
        let items = [SettingsSearchItem(page: .general, title: "Café at login")]
        XCTAssertEqual(SettingsSearch.matches("  CAFE\nLOGIN! ", in: items), [0])
        XCTAssertEqual(SettingsSearch.matches(" \n ", in: items), [])
        XCTAssertEqual(SettingsSearch.matches("?!", in: items), [])
    }

    func testOneTypingErrorMatchesLongWordsButExactWordsRankFirst() {
        let items = [
            SettingsSearchItem(page: .meetings, title: "Calendar reminders"),
            SettingsSearchItem(page: .help, title: "Calender help"),
            SettingsSearchItem(page: .meetings, title: "Teams speaker names")
        ]
        XCTAssertEqual(SettingsSearch.matches("calender", in: items), [1, 0])
        XCTAssertEqual(SettingsSearch.matches("spekaer", in: items), [2])
        XCTAssertEqual(SettingsSearch.matches("calndar", in: items), [0])
        XCTAssertEqual(SettingsSearch.matches("caalendar", in: items), [0])
        XCTAssertEqual(SettingsSearch.matches("tem", in: items), [])
    }

    func testEqualScoresKeepFormOrder() {
        let items = [
            SettingsSearchItem(page: .meetings, title: "Calendar reminders"),
            SettingsSearchItem(page: .meetings, title: "Calendar events")
        ]
        XCTAssertEqual(SettingsSearch.matches("calendar", in: items), [0, 1])
    }
}
