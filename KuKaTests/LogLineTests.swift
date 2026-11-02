import XCTest
@testable import KuKa

final class LogLineTests: XCTestCase {
    func testFormatsLocalTimeOffsetPIDLevelAndCategory() {
        let line = LogLine(date: logDate("2026-10-30T11:08:07Z").addingTimeInterval(0.195),
                           processID: 21621, level: .notice, category: "teams", message: "Scan changed",
                           timeZone: TimeZone(secondsFromGMT: 7200)!)
        XCTAssertEqual(line.formatted, "2026-10-30 13:08:07.195 +0200 [21621] notice teams: Scan changed")
    }

    func testParsesAllLevelsAndKeepsMessageColons() throws {
        for level in ["info", "notice", "error"] {
            let text = "2026-10-30 13:08:07.000 +0200 [42] \(level) meeting: Failed: <private>"
            let line = try XCTUnwrap(LogLine(parsing: text))
            XCTAssertEqual(line.date, logDate("2026-10-30T11:08:07Z"))
            XCTAssertEqual(line.processID, 42)
            XCTAssertEqual(line.category, "meeting")
            XCTAssertEqual(line.level.rawValue, level)
            XCTAssertEqual(line.message, "Failed: <private>")
            XCTAssertEqual(line.formatted, text)
        }
    }

    func testOffsetsDistinguishTheRepeatedHourAtDaylightSavingEnd() throws {
        let first = try XCTUnwrap(LogLine(parsing: "2026-10-25 03:30:00.000 +0300 [1] info app: first"))
        let second = try XCTUnwrap(LogLine(parsing: "2026-10-25 03:15:00.000 +0200 [1] info app: second"))
        XCTAssertEqual(second.date.timeIntervalSince(first.date), 2700)
    }

    func testEachKindOfLineBreakBecomesLiteralBackslashN() {
        let line = makeLine("a\nb\r\nc\rd\u{2028}e\u{0085}f\u{2029}g\u{000B}h\u{000C}i")
        XCTAssertEqual(line.message, "a\\nb\\nc\\nd\\ne\\nf\\ng\\nh\\ni")
        XCTAssertFalse(line.formatted.contains("\n"))
        XCTAssertEqual(LogLine(parsing: line.formatted)?.message, "a\\nb\\nc\\nd\\ne\\nf\\ng\\nh\\ni")
    }

    func testTruncatesAfterNormalizationWithoutSplittingUnicodeCharacters() {
        let character = "👩🏽‍💻"
        XCTAssertEqual(makeLine(String(repeating: character, count: 2000)).message.count, 2000)
        XCTAssertEqual(makeLine(String(repeating: character, count: 2001)).message,
                       String(repeating: character, count: 2000) + "…")
        XCTAssertEqual(makeLine(String(repeating: "a", count: 1999) + "\nend").message,
                       String(repeating: "a", count: 1999) + "\\…")
    }

    func testRejectsMalformedDatesHeadersLevelsAndMultilineInput() {
        for text in [
            "unstructured message",
            "2026-02-30 12:00:00.000 +0200 [1] info app: bad date",
            "2026-10-30 12:00:00.000 +2500 [1] info app: bad offset",
            "2026-10-30 12:00:00.000 +0200 [-1] info app: bad PID",
            "2026-10-30 12:00:00.000 +0200 [1] debug app: bad level",
            "2026-10-30 12:00:00.000 +0200 [1] info app: one\ntwo"
        ] { XCTAssertNil(LogLine(parsing: text), text) }
    }

    private func makeLine(_ message: String) -> LogLine {
        LogLine(date: logDate("2026-10-30T11:08:07Z"), processID: 42,
                level: .info, category: "app", message: message, timeZone: .gmt)
    }
}

func logDate(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}
