import Foundation

enum LogLevel: String, CaseIterable, Sendable {
    case info, notice, error
}

struct LogLine: Sendable {
    let date: Date
    let processID: Int32
    let level: LogLevel
    let category: String
    let message: String
    let timeZone: TimeZone

    init(date: Date, processID: Int32, level: LogLevel, category: String,
         message: String, timeZone: TimeZone = .current) {
        self.date = date
        self.processID = processID
        self.level = level
        self.category = category
        self.timeZone = timeZone
        let singleLine = message.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines).joined(separator: "\\n")
        self.message = singleLine.count > 2000 ? String(singleLine.prefix(2000)) + "…" : singleLine
    }

    var formatted: String {
        "\(Self.formatter(timeZone: timeZone).string(from: date)) [\(processID)] \(level.rawValue) \(category): \(message)"
    }

    init?(parsing text: String) {
        guard text.rangeOfCharacter(from: .newlines) == nil else { return nil }
        let pattern = #/^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} ([+-])(\d{2})(\d{2})) \[(\d+)\] (info|notice|error) ([A-Za-z][A-Za-z0-9]*): (.*)$/#
        guard let match = text.wholeMatch(of: pattern),
              let hours = Int(match.3), hours < 24,
              let minutes = Int(match.4), minutes < 60,
              let timeZone = TimeZone(secondsFromGMT: (hours * 3600 + minutes * 60) * (match.2 == "-" ? -1 : 1)),
              let processID = Int32(match.5), processID > 0,
              let level = LogLevel(rawValue: String(match.6)) else { return nil }
        let formatter = Self.formatter(timeZone: timeZone)
        let timestamp = String(match.1)
        guard let date = formatter.date(from: timestamp),
              formatter.string(from: date) == timestamp else { return nil }
        self.date = date
        self.processID = processID
        self.level = level
        category = String(match.7)
        message = String(match.8)
        self.timeZone = timeZone
    }

    private static func formatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS Z"
        formatter.isLenient = false
        return formatter
    }
}
