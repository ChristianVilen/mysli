import Foundation

/// One analyzer result in file positions. No Speech types: the Apple adapter maps them here.
struct LiveResult: Equatable, Sendable {
    let track: MeetingTrack
    let start: TimeInterval
    let end: TimeInterval
    /// The text in the order spoken, each phrase with its own times.
    let phrases: [TranscriptSegment]
    let isFinal: Bool
    /// The analyzer will not change results before this file position
    /// (`resultsFinalizationTime`).
    let finalizedThrough: TimeInterval
}

enum LiveUpdate: Equatable, Sendable {
    case started
    /// No live text for this meeting, with the reason to show. Never followed by a download.
    case unavailable(String)
    case result(LiveResult)
    /// The engine stopped. The recording goes on.
    case failed(String)
}

struct LiveRow: Equatable {
    enum Content: Equatable {
        case speech(Speaker, text: String, isFinal: Bool)
        /// A pause in the recording. `duration` is nil while it lasts.
        case pause(duration: TimeInterval?)
    }

    /// Recorded time, the same clock as the pill.
    let at: TimeInterval
    let content: Content
}

/// What the drawer draws. Holds no host time and no file positions.
struct LivePreview: Equatable {
    let status: LiveTranscript.Status
    let rows: [LiveRow]
    /// How far the newest text lags the recording, when at least
    /// `LiveTranscript.behindThreshold`. Nil when it keeps up.
    let behind: TimeInterval?
}

/// In memory only, never on disk.
///
/// Per track: the final phrases and at most one volatile tail, in file positions. The final
/// rows come from `Transcript.merge`, so their order and echo rule are the ones in
/// `transcript.md`. Unlike `transcript.md`, rows never join: one microphone track can carry
/// several people in one room, and a short gap can be a new speaker. Volatile tails are not
/// echo-checked: they change, and the final decides.
struct LiveTranscript: Equatable {
    enum Status: Equatable {
        case preparing
        case live
        case unavailable(String)
        /// Terminal. Rows shown so far stay. Later results are ignored.
        case failed(String)
    }

    static let behindThreshold: TimeInterval = 4

    private(set) var status: Status = .preparing
    private var finals: [MeetingTrack: [TranscriptSegment]] = [:]
    private var tails: [MeetingTrack: Tail] = [:]
    /// `Transcript.merge` of the finals and the settled tails, in file positions. Each change to
    /// those merges again, so the preview on every update and every tick does not.
    private var finalLines: [TranscriptLine] = []
    /// Recorded seconds between the newest result's end and the moment it arrived.
    private var lag: TimeInterval = 0

    /// The newest volatile result of a track, replaced as a whole by the next one.
    private struct Tail: Equatable {
        let start: TimeInterval
        let end: TimeInterval
        let phrases: [TranscriptSegment]
        /// Shows as final. A later result for the same audio still replaces it.
        var isSettled = false
    }

    /// Measures lag on arrival, so silence does not grow it.
    mutating func apply(_ update: LiveUpdate, now: HostTime, clock: RecordingClock) {
        let isRunning = status == .preparing || status == .live
        switch update {
        case .started:
            if status == .preparing { status = .live }
        case .unavailable(let reason):
            if status == .preparing { status = .unavailable(reason) }
        case .failed(let reason):
            if isRunning { status = .failed(reason) }
        case .result(let result):
            guard isRunning else { return }
            status = .live
            lag = clock.recordedTime(at: now) - clock.recordedTime(atFilePosition: result.end)
            add(result)
        }
    }

    private mutating func add(_ result: LiveResult) {
        let track = result.track
        let phrases = result.phrases.compactMap { phrase -> TranscriptSegment? in
            let text = phrase.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : TranscriptSegment(start: phrase.start, end: phrase.end, text: text)
        }
        let oldTail = tails[track]
        if result.isFinal {
            if let oldTail, oldTail.start < result.end { tails[track] = nil }
            // The real final of a tail kept below replaces it.
            finals[track, default: []].removeAll { $0.start < result.end && result.start < $0.end }
            finals[track, default: []].append(contentsOf: phrases)
        } else {
            tails[track] = phrases.isEmpty ? nil : Tail(start: result.start, end: result.end, phrases: phrases)
            // Apple may never send a final for a volatile text that stopped changing. Keep it.
            if let oldTail, oldTail.end <= result.finalizedThrough {
                finals[track, default: []].append(contentsOf: oldTail.phrases)
            } else if oldTail?.isSettled != true {
                // An unsettled tail is not among the final lines, so they did not change.
                return
            }
        }
        mergeFinalLines()
    }

    /// At Pause: a tail gets no more audio until Resume, so it shows as final. It stays the
    /// track's tail, because the analyzer can still hold audio from before the pause and send
    /// a newer result for the same words.
    mutating func settleTails() {
        for track in tails.keys { tails[track]?.isSettled = true }
        mergeFinalLines()
    }

    private mutating func mergeFinalLines() {
        var spoken = finals
        for (track, tail) in tails where tail.isSettled { spoken[track, default: []].append(contentsOf: tail.phrases) }
        finalLines = Transcript.merge(spoken, rooms: .notDiarized, joinGap: nil)
    }

    /// Rows in recorded time through `clock`, with one row per pause of `clock`. Each unsettled
    /// tail goes after the rows that start at or before it, Them's first, as merge orders a tie.
    func preview(on clock: RecordingClock) -> LivePreview {
        var rows = finalLines.map { LiveRow(at: clock.recordedTime(atFilePosition: $0.start),
                                            content: .speech($0.speaker, text: $0.text, isFinal: true)) }
        for track in [MeetingTrack.system, .microphone] {
            guard let tail = tails[track], !tail.isSettled else { continue }
            for phrase in tail.phrases {
                let row = LiveRow(at: clock.recordedTime(atFilePosition: phrase.start),
                                  content: .speech(track.speaker, text: phrase.text, isFinal: false))
                rows.insert(row, at: rows.firstIndex { $0.at > row.at } ?? rows.endIndex)
            }
        }
        // Before speech at the same time: speech in the resume gap maps to the pause's time.
        for pause in clock.pauses {
            rows.insert(LiveRow(at: pause.at, content: .pause(duration: pause.duration)),
                        at: rows.firstIndex { $0.at >= pause.at } ?? rows.endIndex)
        }
        return LivePreview(status: status, rows: rows, behind: lag >= Self.behindThreshold ? lag : nil)
    }
}
