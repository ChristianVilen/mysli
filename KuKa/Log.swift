/// Ku-Ka's logging: one subsystem, one category for each area of the app.
struct Log: Sendable {
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

    static var categories: [String] {
        [app, capture, tiling, hotkeys, permissions, keepAwake, clipboard, meeting, teams].map(\.category)
    }

    let category: String
    private let output: LogOutput

    init(category: String, output: LogOutput = .shared) {
        self.category = category
        self.output = output
    }

    func info(_ message: LogMessage) { output.write(message, level: .info, category: category) }
    func notice(_ message: LogMessage) { output.write(message, level: .notice, category: category) }
    func error(_ message: LogMessage) { output.write(message, level: .error, category: category) }
}

enum LogPrivacy {
    case `public`, `private`
}

/// A value whose text never holds meeting content, so a log shows it by default.
protocol PublicLogValue: CustomStringConvertible {}

/// Numbers, Booleans, and PublicLogValue default to public. Other values are private unless
/// marked public. Composed LogMessages preserve their original privacy choices.
struct LogMessage: ExpressibleByStringInterpolation, Sendable {
    let text: String

    init(stringLiteral value: String) { text = value }
    init(stringInterpolation: StringInterpolation) { text = stringInterpolation.text }

    struct StringInterpolation: StringInterpolationProtocol {
        fileprivate var text = ""

        init(literalCapacity: Int, interpolationCount: Int) { text.reserveCapacity(literalCapacity) }

        mutating func appendLiteral(_ literal: String) { text += literal }
        mutating func appendInterpolation(_ message: LogMessage) { text += message.text }
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
