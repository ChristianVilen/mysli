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

    /// Audio-file position, the same timeline as the saved transcript and note rows.
    let at: TimeInterval
    let content: Content

    fileprivate static func final(_ speech: Transcript.Speech, using evidence: TeamsSpeakerEvidence) -> LiveRow {
        LiveRow(at: speech.segment.start, content: .speech(speech.speaker(using: evidence),
                                                          text: speech.segment.text, isFinal: true))
    }
}

struct LivePreview: Equatable {
    let status: LiveTranscript.Status
    let rows: [LiveRow]
    /// How far the newest text lags the recording, when at least
    /// `LiveTranscript.behindThreshold`. Nil when it keeps up.
    let behind: TimeInterval?
}

/// In memory only, never on disk.
///
/// Per track: the final phrases and at most one volatile tail, in file positions. Final rows use
/// the same ordering, echo rule, and Teams evidence rule as `transcript.md`. Live rows never join
/// because a short gap on the microphone track can be a new speaker. Volatile tails are not
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
    private(set) var finalRows = FinalRows([], revision: 0)
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

    struct FinalRows: Equatable {
        private struct Candidate: Equatable {
            let row: Int
            let speech: Transcript.Speech
        }

        let revision: Int
        private var candidates: [Candidate] = []
        private(set) var rows: [LiveRow] = []

        fileprivate init(_ speech: [Transcript.Speech], revision: Int) {
            self.revision = revision
            for item in speech {
                let segment = item.segment
                if item.attribution == .teamsCandidate, segment.start.isFinite, segment.end.isFinite,
                   segment.start >= 0, segment.end > segment.start {
                    candidates.append(Candidate(row: rows.count, speech: item))
                }
                rows.append(.final(item, using: .empty))
            }
        }

        /// Remote candidates are ordered and never overlap, so the ones that end after `position`
        /// are the last ones.
        mutating func resolve(endingAfter position: Double, using evidence: TeamsSpeakerEvidence) {
            for candidate in candidates.reversed() {
                guard candidate.speech.segment.end > position else { return }
                rows[candidate.row] = .final(candidate.speech, using: evidence)
            }
        }
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
        orderFinalSpeech()
    }

    /// At Pause: a tail gets no more audio until Resume, so it shows as final. It stays the
    /// track's tail, because the analyzer can still hold audio from before the pause and send
    /// a newer result for the same words.
    mutating func settleTails() {
        for track in tails.keys { tails[track]?.isSettled = true }
        orderFinalSpeech()
    }

    private mutating func orderFinalSpeech() {
        var spoken = finals
        for (track, tail) in tails where tail.isSettled { spoken[track, default: []].append(contentsOf: tail.phrases) }
        finalRows = FinalRows(Transcript.orderedSpeech(spoken, rooms: .notDiarized), revision: finalRows.revision + 1)
    }

    /// Unsettled text stays below committed speech and pause markers until it becomes final.
    func preview(on clock: RecordingClock, resolvedRows: [LiveRow]? = nil) -> LivePreview {
        var rows = resolvedRows ?? finalRows.rows
        for pause in clock.pauses {
            rows.insert(LiveRow(at: pause.filePosition, content: .pause(duration: pause.duration)),
                        at: rows.firstIndex { $0.at >= pause.filePosition } ?? rows.endIndex)
        }
        var drafts: [LiveRow] = []
        for track in [MeetingTrack.system, .microphone] {
            guard let tail = tails[track], !tail.isSettled else { continue }
            for phrase in tail.phrases {
                let row = LiveRow(at: phrase.start,
                                  content: .speech(track.speaker, text: phrase.text, isFinal: false))
                drafts.append(row)
            }
        }
        rows.append(contentsOf: drafts.sorted { $0.at < $1.at })
        return LivePreview(status: status, rows: rows, behind: lag >= Self.behindThreshold ? lag : nil)
    }
}
