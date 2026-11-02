import Foundation
import OSLog
import os

final class LogOutput: Sendable {
    static let shared = LogOutput()

    private let files = OSAllocatedUnfairLock<LogFiles?>(initialState: nil)
    private let clock: @Sendable () -> Date
    private let processID: Int32
    private let timeZone: @Sendable () -> TimeZone
    private let unified: @Sendable (LogLine) -> Void

    init(clock: @escaping @Sendable () -> Date = { Date() },
         processID: Int32 = ProcessInfo.processInfo.processIdentifier,
         timeZone: @escaping @Sendable () -> TimeZone = { .current },
         unified: @escaping @Sendable (LogLine) -> Void = { LogOutput.writeUnified($0) }) {
        self.clock = clock
        self.processID = processID
        self.timeZone = timeZone
        self.unified = unified
    }

    func enableFiles(_ files: LogFiles) {
        self.files.withLock { $0 = files }
    }

    func write(_ message: LogMessage, level: LogLevel, category: String) {
        let fileOutput = files.withLock { $0 }
        let line = LogLine(date: clock(), processID: processID, level: level,
                           category: category, message: message.text, timeZone: timeZone())
        unified(line)
        fileOutput?.append(line)
    }

    func reportFileFailure(_ error: Error) {
        let message: LogMessage = "Could not write log file (code \((error as NSError).code)): \(error.localizedDescription)"
        unified(LogLine(date: clock(), processID: processID, level: .error,
                        category: "app", message: message.text, timeZone: timeZone()))
    }

    private static func writeUnified(_ line: LogLine) {
        let logger = Logger(subsystem: Log.subsystem, category: line.category)
        switch line.level {
        case .info: logger.info("\(line.message, privacy: .public)")
        case .notice: logger.notice("\(line.message, privacy: .public)")
        case .error: logger.error("\(line.message, privacy: .public)")
        }
    }
}
