import Foundation

/// One stretch of one voice on the microphone track, in seconds from the start of the file.
/// `voice` is the diarizer's cluster id. It means something only inside one diarization, so
/// `Transcript.merge` turns it into a room number and it never reaches `transcript.md`.
struct VoiceTurn: Equatable, Sendable {
    let voice: Int
    let start: TimeInterval
    let end: TimeInterval
}

/// The voices on the microphone track of one meeting. Never empty, so every segment has a voice.
struct RoomVoices: Equatable, Sendable {
    private let turns: [VoiceTurn]
    /// `latestEnds[i]` is the latest end among `turns[0...i]`. Turns can overlap, so the ends alone
    /// are not sorted, but these are, and a binary search can skip every turn that ends too early.
    private let latestEnds: [TimeInterval]

    /// Nil when no turn is longer than zero: the diarizer found no voice. Sorts by start, because
    /// SpeakerKit lists its turns speaker by speaker.
    init?(_ turns: [VoiceTurn]) {
        let kept = turns.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard !kept.isEmpty else { return nil }
        self.turns = kept
        var latest = -TimeInterval.infinity
        latestEnds = kept.map { turn in
            latest = max(latest, turn.end)
            return latest
        }
    }

    /// Only the turns of `voices`. Nil when none of them has a turn.
    func keeping(_ voices: Set<Int>) -> RoomVoices? {
        RoomVoices(turns.filter { voices.contains($0.voice) })
    }

    /// The voice of one whole segment, which is never split: Ku-Ka keeps no word times. The voice
    /// with the most time inside the segment, summed over its turns; on equal time, the voice whose
    /// turn starts first. A segment inside no turn gets the nearest turn's voice, the earlier turn
    /// on equal gaps.
    func voice(for segment: TranscriptSegment) -> Int {
        let startsBefore = firstIndex { turns[$0].start >= segment.end }
        let endsAfter = firstIndex { latestEnds[$0] > segment.start }
        // In the order of each voice's first overlapping turn, so `first` below breaks a tie.
        var shares: [(voice: Int, time: TimeInterval)] = []
        for turn in turns[min(endsAfter, startsBefore)..<startsBefore] {
            let shared = min(turn.end, segment.end) - max(turn.start, segment.start)
            guard shared > 0 else { continue }
            if let index = shares.firstIndex(where: { $0.voice == turn.voice }) {
                shares[index].time += shared
            } else {
                shares.append((turn.voice, shared))
            }
        }
        if let most = shares.map(\.time).max() {
            return shares.first { $0.time == most }!.voice
        }
        return nearestTurn(to: segment, startsBefore: startsBefore).voice
    }

    /// Of the turns that start before the segment ends, the nearest is the first one to reach the
    /// segment's start, or else the first with the latest end. Of the others, the first is nearest.
    private func nearestTurn(to segment: TranscriptSegment, startsBefore: Int) -> VoiceTurn {
        var candidates: [VoiceTurn] = []
        if startsBefore > 0 {
            let reach = min(latestEnds[startsBefore - 1], segment.start)
            candidates.append(turns[firstIndex { latestEnds[$0] >= reach }])
        }
        if startsBefore < turns.count { candidates.append(turns[startsBefore]) }
        return candidates.min { (gap($0, segment), $0.start) < (gap($1, segment), $1.start) }!
    }

    private func gap(_ turn: VoiceTurn, _ segment: TranscriptSegment) -> TimeInterval {
        max(turn.start - segment.end, segment.start - turn.end, 0)
    }

    /// The first index in `0...turns.count` where `isPast` is true. `isPast` must be false before
    /// that index and true from it on.
    private func firstIndex(where isPast: (Int) -> Bool) -> Int {
        var low = 0
        var high = turns.count
        while low < high {
            let middle = (low + high) / 2
            if isPast(middle) { high = middle } else { low = middle + 1 }
        }
        return low
    }
}

enum RoomLabels: Equatable, Sendable {
    /// Nothing was diarized: the live view, or a microphone track without speech.
    case notDiarized
    case voices(RoomVoices)
    /// Labelling failed. The microphone lines say "Me", and the meeting still finishes.
    case failed(RoomLabelFailure)
}

protocol RoomLabelling {
    var needsDownload: Bool { get }
    /// `onStart` runs only once this Ku-Ka holds the download lock and the model is still
    /// missing, right before the download starts. When another Ku-Ka holds the lock, waits for it.
    func download(onStart: @MainActor () -> Void) async throws
    /// Never throws: every problem comes back as `.failed`, so labels never fail a meeting. After
    /// a cancel the value means nothing, so the caller checks cancellation before it uses the value.
    func label(_ microphone: URL) async -> RoomLabels
}

enum RoomLabelFailure: Equatable, Sendable, CustomStringConvertible {
    /// Also when another Ku-Ka holds the download lock.
    case download(String)
    case load(String)
    case diarize(String)
    /// SpeakerKit drops an embedder error without telling the caller, so no voice on a track with
    /// speech is the only sign of one.
    case noVoices
    case tooLong
    /// An earlier attempt did not finish labelling. A crash there would repeat at every launch,
    /// so it was not tried again.
    case earlierAttemptStopped

    /// SpeakerKit holds the whole track in memory as 16 kHz samples, about 230 MB an hour.
    static let longestTrack: TimeInterval = 3 * 60 * 60

    var description: String {
        switch self {
        case .download(let message): return "SpeakerKit could not download its model: \(message)"
        case .load(let message): return "SpeakerKit could not load its model: \(message)"
        case .diarize(let message): return "SpeakerKit could not tell the voices apart: \(message)"
        case .noVoices: return "SpeakerKit found no voices on the microphone track."
        case .tooLong:
            return "Ku-Ka skipped them, because the microphone track is longer than \(Int(Self.longestTrack / 3600)) hours."
        case .earlierAttemptStopped:
            return "Ku-Ka skipped them, because an earlier attempt stopped while it told the voices apart, for example in a crash."
        }
    }
}
