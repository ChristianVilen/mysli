import Foundation

struct LogRow: Sendable {
    enum ID: Hashable, Sendable {
        case file(LogFileIdentity, line: Int)
        case memory(UUID)
    }

    let id: ID
    let text: String
    let day: Date
    let line: LogLine?

    init(text: String, day: Date, id: ID = .memory(UUID())) {
        self.id = id
        self.text = text
        self.day = day
        line = LogLine(parsing: text)
    }
}

enum LogRange: CaseIterable, Sendable {
    case thisLaunch, today, lastSevenDays, everything

    func interval(now: Date, launchDate: Date, calendar: Calendar = .current) -> DateInterval? {
        let today = calendar.startOfDay(for: now)
        let start: Date
        switch self {
        case .thisLaunch: start = min(calendar.startOfDay(for: launchDate), today)
        case .today: start = today
        case .lastSevenDays: start = calendar.date(byAdding: .day, value: -6, to: today)!
        case .everything: return nil
        }
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: today)!)
    }
}

struct LogFilter: Sendable {
    var range: LogRange = .thisLaunch
    var category: String?
    var errorsOnly = false
    var rowLimit = LogFilter.defaultRowLimit

    static let defaultRowLimit = 5000

    func rows(_ rows: [LogRow], now: Date, launchDate: Date, processID: Int32,
              calendar: Calendar = .current) -> [LogRow] {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let firstDay = calendar.date(byAdding: .day, value: -6, to: today)!
        let matching = rows.filter { row in
            if let category, row.line?.category != category { return false }
            if errorsOnly && row.line?.level != .error { return false }
            let date = row.line?.date ?? row.day
            switch range {
            case .thisLaunch:
                guard let line = row.line else { return false }
                return line.processID == processID && line.date >= launchDate
            case .today: return date >= today && date < tomorrow
            case .lastSevenDays: return date >= firstDay && date < tomorrow
            case .everything: return true
            }
        }
        let dated = matching.enumerated().compactMap { index, row -> (Int, Date, LogRow)? in
            row.line.map { (index, $0.date, row) }
        }.sorted { first, second in
            first.1 == second.1 ? first.0 < second.0 : first.1 < second.1
        }
        var ordered = dated.makeIterator()
        let result = matching.map { row in row.line == nil ? row : ordered.next()!.2 }
        return Array(result.suffix(rowLimit))
    }
}
