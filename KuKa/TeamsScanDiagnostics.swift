import Foundation

/// What one scan of the Teams meeting window found.
enum TeamsScanResult: Equatable, Sendable {
    case named(TeamsSpeakerName)
    case unnamed(TeamsScanReason)

    var speaker: TeamsSpeakerName? {
        guard case .named(let name) = self else { return nil }
        return name
    }

    /// Never the name, so a log can show it.
    var code: String {
        switch self {
        case .named: return "named"
        case .unnamed(let reason): return reason.code
        }
    }
}

/// Why a scan gave no name. A reader throws the reasons that end a scan early.
enum TeamsScanReason: Error, Hashable, Sendable, PublicLogValue {
    case notTrusted
    case noTeamsApp
    case noMeetingWindow
    case multipleMeetingWindows
    case noHighlightedTile
    case multipleHighlightedTiles
    case unsupportedTile
    case selfTile
    case nameRejected
    case scanLimit
    case deadline
    case axError(Int32)
    case unexpectedAXValue

    var code: String {
        switch self {
        case .notTrusted: return "notTrusted"
        case .noTeamsApp: return "noTeamsApp"
        case .noMeetingWindow: return "noMeetingWindow"
        case .multipleMeetingWindows: return "multipleMeetingWindows"
        case .noHighlightedTile: return "noHighlightedTile"
        case .multipleHighlightedTiles: return "multipleHighlightedTiles"
        case .unsupportedTile: return "unsupportedTile"
        case .selfTile: return "selfTile"
        case .nameRejected: return "nameRejected"
        case .scanLimit: return "scanLimit"
        case .deadline: return "deadline"
        case .axError(let code): return "axError(\(code))"
        case .unexpectedAXValue: return "unexpectedAXValue"
        }
    }

    var description: String { code }

    /// Completes "In N of M scans, …" in transcript.md.
    var clause: String {
        switch self {
        case .notTrusted: return "Ku-Ka had no Accessibility permission"
        case .noTeamsApp: return "the Teams app was not running"
        case .noMeetingWindow: return "no Teams window showed meeting controls with Hang up or Leave"
        case .multipleMeetingWindows: return "more than one Teams window showed meeting controls"
        case .noHighlightedTile: return "no video tile had a speaking border"
        case .multipleHighlightedTiles: return "more than one video tile had a speaking border"
        case .unsupportedTile: return "the highlighted tile did not have the supported structure"
        case .selfTile: return "the highlighted tile was your own video"
        case .nameRejected: return "the name text of the tile was not a usable name"
        case .scanLimit: return "the Teams windows had more elements or text than one scan reads"
        case .deadline: return "the scan took longer than 150 ms"
        case .axError(let code): return "an Accessibility call failed with error \(code)"
        case .unexpectedAXValue: return "Teams returned unexpected Accessibility data"
        }
    }

    /// The order of the table in the design spec. It decides between reasons with equal counts.
    fileprivate var rank: Int {
        switch self {
        case .notTrusted: return 0
        case .noTeamsApp: return 1
        case .noMeetingWindow: return 2
        case .multipleMeetingWindows: return 3
        case .noHighlightedTile: return 4
        case .multipleHighlightedTiles: return 5
        case .unsupportedTile: return 6
        case .selfTile: return 7
        case .nameRejected: return 8
        case .scanLimit: return 9
        case .deadline: return 10
        case .axError: return 11
        case .unexpectedAXValue: return 12
        }
    }
}

/// The name-free counts of one recording's scans, for the Stop log line and the transcript line.
struct TeamsScanSummary: Equatable, Sendable {
    static let empty = TeamsScanSummary([])

    let scans: Int
    let named: Int
    let reasons: [TeamsScanReason: Int]
    let medianScanTime: TimeInterval
    let longestScanTime: TimeInterval
    let largestNodeCount: Int

    init(_ observations: [TeamsSpeakerObservation]) {
        scans = observations.count
        named = observations.filter { $0.speaker != nil }.count
        var reasons: [TeamsScanReason: Int] = [:]
        for case .unnamed(let reason) in observations.map(\.result) { reasons[reason, default: 0] += 1 }
        self.reasons = reasons
        let times = observations.map { $0.ended - $0.began }.sorted()
        medianScanTime = times.isEmpty ? 0 : (times[(times.count - 1) / 2] + times[times.count / 2]) / 2
        longestScanTime = times.last ?? 0
        largestNodeCount = observations.map(\.nodes).max() ?? 0
    }

    /// Most frequent first, then the table order, then the code, so two AX errors with equal counts
    /// do not come out in dictionary order, which changes between launches.
    private var rankedReasons: [(reason: TeamsScanReason, count: Int)] {
        reasons.map { (reason: $0.key, count: $0.value) }.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            if $0.reason.rank != $1.reason.rank { return $0.reason.rank < $1.reason.rank }
            return $0.reason.code < $1.reason.code
        }
    }

    var stopLine: LogMessage {
        let reasons = rankedReasons.isEmpty
            ? "none" : rankedReasons.map { "\($0.reason.code) \($0.count)" }.joined(separator: ", ")
        let median = String(format: "%.3f", medianScanTime)
        let longest = String(format: "%.3f", longestScanTime)
        return """
            Teams speaker names at Stop. Scans: \(scans), named: \(named). Reasons: \(reasons, privacy: .public). \
            Scan time: median \(median, privacy: .public) s, longest \(longest, privacy: .public) s. \
            Largest node count: \(largestNodeCount).
            """
    }

    /// Nil when the feature did not scan, as for a recovered or retried meeting.
    func mergeLine(for lines: [TranscriptLine]) -> LogMessage? {
        guard scans > 0 else { return nil }
        let remote = Self.remote(lines)
        return "Teams speaker names: \(remote.named) of \(remote.all) remote lines named."
    }

    /// The line that says why no remote line got a name, or nil when it has nothing to say.
    func transcriptNote(for lines: [TranscriptLine]) -> String? {
        let remote = Self.remote(lines)
        guard scans > 0, remote.all > 0, remote.named == 0 else { return nil }
        let why: String
        if named > 0 {
            why = "In \(named) of \(scans) scans, Teams showed a name, but no remote line had enough matching evidence."
        } else {
            // Nobody speaking also gives noHighlightedTile, so another reason says more.
            let ranked = rankedReasons
            guard let top = ranked.first(where: { $0.reason != .noHighlightedTile }) ?? ranked.first else { return nil }
            why = "In \(top.count) of \(scans) scans, \(top.reason.clause)."
        }
        return "Teams speaker names were on, but no remote line got a name. \(why)"
    }

    private static func remote(_ lines: [TranscriptLine]) -> (all: Int, named: Int) {
        let remote = lines.filter { $0.speaker.track == .system }
        let named = remote.filter { line in
            if case .teams = line.speaker { return true }
            return false
        }
        return (remote.count, named.count)
    }
}

/// Decides which changes of the scan result go to the log: at most one line every `lineGap`.
struct TeamsScanTally {
    static let lineGap: TimeInterval = 2

    private var current: String?
    private var lastLine: (code: String, at: HostTime)?
    private var unloggedChanges = 0

    /// The line to log for this scan, or nil.
    mutating func line(for scan: TeamsSpeakerObservation) -> LogMessage? {
        let code = scan.result.code
        if code != current { unloggedChanges += 1 }
        current = code
        guard unloggedChanges > 0 else { return nil }
        if let lastLine, scan.began < lastLine.at + Self.lineGap { return nil }
        let line: LogMessage
        if let lastLine, unloggedChanges == 1 {
            line = "Teams scan result: \(lastLine.code, privacy: .public) → \(code, privacy: .public)."
        } else if lastLine == nil {
            line = "Teams scan result: \(code, privacy: .public) (first scan)."
        } else {
            line = "Teams scan result: \(code, privacy: .public), after \(unloggedChanges) changes since the last line."
        }
        lastLine = (code, scan.began)
        unloggedChanges = 0
        return line
    }
}
