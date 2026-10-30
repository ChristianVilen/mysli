import OSLog

/// Ku-Ka's logging: one subsystem, one category for each area of the app.
struct Log {
    static let subsystem = "com.kuka.screenshot"

    static let app = Log(category: "app")
    static let capture = Log(category: "capture")
    static let tiling = Log(category: "tiling")
    static let hotkeys = Log(category: "hotkeys")
    static let permissions = Log(category: "permissions")
    static let keepAwake = Log(category: "keepAwake")
    static let clipboard = Log(category: "clipboard")
    static let meeting = Log(category: "meeting")
    static let teams = Log(category: "teams")

    let category: String
    private let logger: Logger

    private init(category: String) {
        self.category = category
        logger = Logger(subsystem: Self.subsystem, category: category)
    }

    // The message already holds <private> in place of each private value, so the whole text is public.
    func info(_ message: LogMessage) { logger.info("\(message.text, privacy: .public)") }
    func notice(_ message: LogMessage) { logger.notice("\(message.text, privacy: .public)") }
    func error(_ message: LogMessage) { logger.error("\(message.text, privacy: .public)") }
}

enum LogPrivacy {
    case `public`, `private`
}

/// A value whose text never holds meeting content, so a log shows it by default.
protocol PublicLogValue: CustomStringConvertible {}

/// The text of one log line. Like `os.Logger`, numbers, Booleans, and `PublicLogValue`s are public,
/// and any other value is `<private>` unless the call says `privacy: .public`.
struct LogMessage: ExpressibleByStringInterpolation {
    let text: String

    init(stringLiteral value: String) { text = value }
    init(stringInterpolation: StringInterpolation) { text = stringInterpolation.text }

    struct StringInterpolation: StringInterpolationProtocol {
        fileprivate var text = ""

        init(literalCapacity: Int, interpolationCount: Int) { text.reserveCapacity(literalCapacity) }

        mutating func appendLiteral(_ literal: String) { text += literal }
        mutating func appendInterpolation(_ value: some BinaryInteger) { text += String(value) }
        mutating func appendInterpolation(_ value: some BinaryFloatingPoint & CustomStringConvertible) {
            text += value.description
        }
        mutating func appendInterpolation(_ value: Bool) { text += String(value) }
        mutating func appendInterpolation(_ value: some PublicLogValue, privacy: LogPrivacy = .public) {
            append(value, privacy: privacy)
        }
        mutating func appendInterpolation(_ value: some CustomStringConvertible, privacy: LogPrivacy = .private) {
            append(value, privacy: privacy)
        }

        private mutating func append(_ value: some CustomStringConvertible, privacy: LogPrivacy) {
            text += privacy == .public ? value.description : "<private>"
        }
    }
}
