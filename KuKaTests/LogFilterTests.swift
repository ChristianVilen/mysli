import XCTest
@testable import KuKa

final class LogFilterTests: XCTestCase {
    private let now = logDate("2026-10-30T11:00:00Z")
    private let launch = logDate("2026-10-30T10:00:00Z")
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        return calendar
    }

    func testThisLaunchRequiresMatchingPIDAndLaunchTime() {
        let rows = [row("before", date: "2026-10-30T09:59:59Z"),
                    row("at launch", date: "2026-10-30T10:00:00Z"),
                    row("other PID", processID: 99), row("mine"), unknown("unstructured")]
        XCTAssertEqual(messages(rows, filter: LogFilter()), ["at launch", "mine"])
    }

    func testTodayUsesLocalMidnightAndExcludesTomorrow() {
        let rows = [row("yesterday", date: "2026-10-29T21:59:59Z"),
                    row("midnight", date: "2026-10-29T22:00:00Z"), row("today"),
                    row("tomorrow", date: "2026-10-30T22:00:00Z")]
        XCTAssertEqual(messages(rows, filter: LogFilter(range: .today)), ["midnight", "today"])
    }

    func testLastSevenDaysIncludesSixPriorCalendarDaysAcrossDaylightSaving() {
        let rows = [row("too old", date: "2026-10-23T20:59:59Z"),
                    row("first midnight", date: "2026-10-23T21:00:00Z"), row("today"),
                    row("tomorrow", date: "2026-10-30T22:00:00Z")]
        XCTAssertEqual(messages(rows, filter: LogFilter(range: .lastSevenDays)), ["first midnight", "today"])
    }

    func testEverythingKeepsOlderRowsAndAllProcessIDs() {
        let rows = [row("old", date: "2026-10-01T10:00:00Z", processID: 99), row("now")]
        XCTAssertEqual(messages(rows, filter: LogFilter(range: .everything)), ["old", "now"])
    }

    func testCategoryAndErrorFiltersCombine() {
        let rows = [row("app info"), row("meeting info", category: "meeting"),
                    row("app error", level: .error),
                    row("meeting error", category: "meeting", level: .error), unknown("raw")]
        XCTAssertEqual(messages(rows, filter: LogFilter(range: .everything, category: "meeting")),
                       ["meeting info", "meeting error"])
        XCTAssertEqual(messages(rows, filter: LogFilter(range: .everything, errorsOnly: true)),
                       ["app error", "meeting error"])
        XCTAssertEqual(messages(rows, filter: LogFilter(range: .everything, category: "meeting", errorsOnly: true)),
                       ["meeting error"])
    }

    func testUnknownRowsUseTheSourceFileDayAndRemainUnchangedUnderAll() {
        let rows = [unknown("old raw", day: "2026-10-22T21:00:00Z"),
                    unknown("yesterday raw", day: "2026-10-28T22:00:00Z"),
                    unknown("today raw"), row("parsed")]
        XCTAssertEqual(messages(rows, filter: LogFilter(range: .today)), ["today raw", "parsed"])
        XCTAssertEqual(messages(rows, filter: LogFilter(range: .lastSevenDays)),
                       ["yesterday raw", "today raw", "parsed"])
        XCTAssertEqual(messages(rows, filter: LogFilter(range: .everything)),
                       ["old raw", "yesterday raw", "today raw", "parsed"])
    }

    func testSortsAbsoluteTimesAndKeepsInputOrderForTies() {
        let rows = [row("later", date: "2026-10-25T01:15:00Z"),
                    row("earlier", date: "2026-10-25T00:30:00Z"),
                    row("equal time", date: "2026-10-25T01:15:00Z")]
        XCTAssertEqual(messages(rows, filter: LogFilter(range: .everything)), ["earlier", "later", "equal time"])
    }

    func testUnknownRowsKeepTheirInputPositionsWhileKnownRowsAreSorted() {
        let rows = [row("later"), unknown("raw"), row("earlier", date: "2026-10-30T10:00:00Z")]
        XCTAssertEqual(messages(rows, filter: LogFilter(range: .everything)), ["earlier", "raw", "later"])
    }

    func testKeepsNewestFiveThousandMatchingRowsAfterFiltering() {
        let rows = (0..<5002).map { row("error \($0)", level: .error) }
            + (0..<10).map { row("info \($0)") }
        let result = messages(rows, filter: LogFilter(range: .everything, errorsOnly: true))
        XCTAssertEqual(result.count, 5000)
        XCTAssertEqual(result.first, "error 2")
        XCTAssertEqual(result.last, "error 5001")
        XCTAssertEqual(messages([], filter: LogFilter(range: .everything)), [])
    }

    private func messages(_ rows: [LogRow], filter: LogFilter) -> [String] {
        filter.rows(rows, now: now, launchDate: launch, processID: 42, calendar: calendar)
            .map { $0.line?.message ?? $0.text }
    }

    private func row(_ message: String, date: String = "2026-10-30T11:00:00Z", processID: Int32 = 42,
                     category: String = "app", level: LogLevel = .info) -> LogRow {
        let date = logDate(date)
        let line = LogLine(date: date, processID: processID, level: level, category: category,
                           message: message, timeZone: calendar.timeZone)
        return LogRow(text: line.formatted, day: calendar.startOfDay(for: date))
    }

    private func unknown(_ text: String, day: String = "2026-10-29T22:00:00Z") -> LogRow {
        LogRow(text: text, day: logDate(day))
    }
}
