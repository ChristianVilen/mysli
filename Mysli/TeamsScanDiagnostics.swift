import Foundation

/// What one scan of the Teams meeting window found.
enum TeamsScanResult: Hashable, Sendable {
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
    case scanLimit(TeamsScanLimit)
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
        case .scanLimit(let limit): return "scanLimit(\(limit.rawValue))"
        case .deadline: return "deadline"
        case .axError(let code): return "axError(\(code))"
        case .unexpectedAXValue: return "unexpectedAXValue"
        }
    }

    var description: String { code }

    /// No remote speaker has a speaking border.
    var isSilence: Bool { self == .noHighlightedTile || self == .selfTile }

    /// Completes "In N of M scans, …" in transcript.md.
    var clause: String {
        switch self {
        case .notTrusted: return "Mysli had no Accessibility permission"
        case .noTeamsApp: return "the Teams app was not running"
        case .noMeetingWindow: return "no Teams window showed meeting controls with Hang up or Leave"
        case .multipleMeetingWindows: return "more than one Teams window showed meeting controls"
        case .noHighlightedTile: return "no video tile had a speaking border"
        case .multipleHighlightedTiles: return "more than one video tile had a speaking border"
        case .unsupportedTile: return "the highlighted tile did not have the supported structure"
        case .selfTile: return "the highlighted tile was your own video"
        case .nameRejected: return "the name text of the tile was not a usable name"
        case .scanLimit: return "the Teams windows had more elements or text than one scan reads"
        case .deadline: return "the scan took longer than \(Int((TeamsScanLimit.deadline * 1000).rounded())) ms"
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

    private var rankedReasons: [(reason: TeamsScanReason, count: Int)] {
        Self.ranked(reasons.map { (reason: $0.key, count: $0.value) })
    }

    /// Most frequent first, then the table order, then the code, so two AX errors with equal counts
    /// do not come out in dictionary order, which changes between launches.
    private static func ranked(_ counts: [(reason: TeamsScanReason, count: Int)])
        -> [(reason: TeamsScanReason, count: Int)] {
        counts.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            if $0.reason.rank != $1.reason.rank { return $0.reason.rank < $1.reason.rank }
            return $0.reason.code < $1.reason.code
        }
    }

    var stopLine: LogMessage { line(after: "Teams speaker names at Stop.") }

    var soFarLine: LogMessage { line(after: "Teams speaker names so far.") }

    private func line(after heading: LogMessage) -> LogMessage {
        let reasons = rankedReasons.isEmpty
            ? "none" : rankedReasons.map { "\($0.reason.code) \($0.count)" }.joined(separator: ", ")
        let median = String(format: "%.3f", medianScanTime)
        let longest = String(format: "%.3f", longestScanTime)
        return """
            \(heading) Scans: \(scans), named: \(named). Reasons: \(reasons, privacy: .public). \
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

    /// Under this share of named remote lines, transcript.md gets a note.
    private static let lowNamedShare = 0.25

    /// The line that says why few or no remote lines got a name, or nil when it has nothing to say.
    func transcriptNote(for lines: [TranscriptLine]) -> String? {
        let remote = Self.remote(lines)
        guard scans > 0, remote.all > 0,
              Double(remote.named) < Self.lowNamedShare * Double(remote.all) else { return nil }
        let problem = mainProblem.map { "In \($0.count) of \(scans) scans, \($0.reason.clause)." }
        if remote.named > 0 {
            let note = "Teams speaker names were on, but only \(remote.named) of \(remote.all) remote lines got a name."
            return problem.map { "\(note) \($0)" } ?? note
        }
        let why = named > 0
            ? "In \(named) of \(scans) scans, Teams showed a name, but no remote line had enough matching evidence."
            : problem
        return why.map { "Teams speaker names were on, but no remote line got a name. \($0)" }
    }

    /// Silence is normal when nobody speaks, so another reason says more. Reasons with the same clause, as the kinds
    /// of scan limit, count as one problem.
    private var mainProblem: (reason: TeamsScanReason, count: Int)? {
        let problems = Self.ranked(Dictionary(grouping: rankedReasons, by: { $0.reason.clause }).values.map { group in
            (reason: group[0].reason, count: group.reduce(0) { $0 + $1.count })
        })
        return problems.first { !$0.reason.isSilence } ?? problems.first
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

/// Decides which lines about the scans go to the log: a change of the scan result at most once every `lineGap`,
/// and the counts so far about once every `countGap`.
struct TeamsScanTally {
    static let lineGap: TimeInterval = 2
    static let countGap: TimeInterval = 300

    private var current: String?
    private var lastLine: (code: String, at: HostTime)?
    private var unloggedChanges = 0
    private var nextCounts: HostTime?

    /// Measured from the first scan or the last count line, so the first scan after a long pause is due.
    mutating func countsDue(after scan: TeamsSpeakerObservation) -> Bool {
        guard let next = nextCounts else {
            nextCounts = scan.began + Self.countGap
            return false
        }
        guard scan.began >= next else { return false }
        nextCounts = scan.began + Self.countGap
        return true
    }

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
