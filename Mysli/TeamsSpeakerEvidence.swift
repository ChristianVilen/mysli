import Foundation

struct TeamsSpeakerName: Hashable, Sendable {
    let value: String
    init?(_ raw: String) {
        guard !raw.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
        }),
              !raw.unicodeScalars.contains(where: { "*[]\\`<>".unicodeScalars.contains($0) }) else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = value.lowercased()
        guard !value.isEmpty, value.count <= 80, value.utf8.count <= 256,
              folded != "me", folded != "them",
              folded.wholeMatch(of: #/room\s+[0-9]+/#) == nil else { return nil }
        self.value = value
    }
}

struct TeamsSpeakerObservation: Equatable, Sendable {
    let began: HostTime
    let ended: HostTime
    let sequence: Int
    let sourceID: String?
    let result: TeamsScanResult
    let nodes: Int

    var speaker: TeamsSpeakerName? { result.speaker }
    fileprivate var hasFiniteTimes: Bool { began.seconds.isFinite && ended.seconds.isFinite }
}

struct TeamsSpeakerHistory {
    private struct Entry {
        let sample: TeamsSpeakerObservation
        let runID: UUID
    }

    private var entries: [Entry] = []
    private var projectedClock: RecordingClock?
    private var projectedCount = 0
    private var liveProjection = Projection()
    let capacity: Int

    init(capacity: Int = 36_000) {
        self.capacity = capacity
    }

    mutating func append(_ sample: TeamsSpeakerObservation, runID: UUID) -> Bool {
        guard entries.count < capacity else { return false }
        entries.append(Entry(sample: sample, runID: runID))
        return entries.count < capacity
    }

    /// `changedFrom` is the file position from which the evidence differs from the last call's.
    /// Nil when nothing changed, minus infinity after a clock change.
    mutating func evidenceSoFar(clock: RecordingClock) -> (evidence: TeamsSpeakerEvidence, changedFrom: Double?) {
        // A pause or resume can change the mapping of a scan that straddles its boundary.
        let reset = projectedClock != clock
        if reset {
            projectedClock = clock
            projectedCount = 0
            liveProjection = Projection()
        }
        guard clock.origin.seconds.isFinite else { return (.empty, reset ? -Double.infinity : nil) }
        let known = liveProjection.claims.count
        for entry in entries.dropFirst(projectedCount) { liveProjection.add(entry, clock: clock) }
        projectedCount = entries.count
        // New scans only add claims after the old ones.
        let changedFrom = reset ? -Double.infinity : liveProjection.claims.dropFirst(known).first?.start
        return (liveProjection.evidence(scans: .empty), changedFrom)
    }

    func finish(clock: RecordingClock, endingAt stop: HostTime) -> TeamsSpeakerEvidence {
        guard stop.seconds.isFinite, clock.origin.seconds.isFinite else { return .empty }
        var projection = Projection()
        var scans: [TeamsSpeakerObservation] = []
        for entry in entries {
            let sample = entry.sample
            if sample.hasFiniteTimes {
                guard sample.began <= stop, sample.ended <= stop else { continue }
                scans.append(sample)
            }
            projection.add(entry, clock: clock)
        }
        return projection.evidence(scans: TeamsScanSummary(scans))
    }

    private struct Projection {
        /// What valid scans and the time between continuous scans claim. Ordered, without overlaps.
        /// Invalid scans and unknown results claim nothing.
        private(set) var claims: [SpeakerSpan] = []
        private var previous: Entry?
        private var latestEnd = -Double.infinity

        mutating func add(_ entry: Entry, clock: RecordingClock) {
            let sample = entry.sample
            guard sample.hasFiniteTimes else {
                previous = nil
                return
            }
            let ordered = sample.began.seconds >= latestEnd
            latestEnd = max(latestEnd, sample.began.seconds, sample.ended.seconds)
            guard ordered, sample.sequence >= 0, sample.sourceID?.isEmpty == false,
                  let scan = clock.fileIntervalInOneRun(from: sample.began, to: sample.ended) else {
                previous = nil
                return
            }
            let claim = Claim(sample.result)
            if let earlier = previous,
               earlier.runID == entry.runID,
               earlier.sample.sourceID == sample.sourceID,
               earlier.sample.sequence < Int.max,
               sample.sequence == earlier.sample.sequence + 1,
               sample.began <= earlier.sample.ended + TeamsNameRule.maxScanGap,
               let gap = clock.fileIntervalInOneRun(from: earlier.sample.ended, to: sample.began) {
                let earlierClaim = Claim(earlier.sample.result)
                if earlierClaim == claim {
                    append(gap.start, gap.end, claim)
                } else {
                    let middle = (gap.start + gap.end) / 2
                    append(gap.start, middle, earlierClaim)
                    append(middle, gap.end, claim)
                }
            }
            append(scan.start, scan.end, claim)
            previous = entry
        }

        func evidence(scans: TeamsScanSummary) -> TeamsSpeakerEvidence {
            TeamsSpeakerEvidence(claims: claims, scans: scans)
        }

        private mutating func append(_ start: Double, _ end: Double, _ claim: Claim?) {
            guard let claim, end > start else { return }
            claims.append(SpeakerSpan(start: start, end: end, claim: claim))
        }
    }
}

/// The limits that decide whether a transcript segment gets a Teams name.
private enum TeamsNameRule {
    /// Silence is not judged, so this share also caps unknown time at the rest of the judged time.
    /// No separate limit for unknown time is needed.
    static let winningShare = 0.70
    static let secondNameShare = 0.15
    /// Of the whole segment, so a segment of nearly all silence does not get a name from one short flash.
    static let minimumNamedShare = 0.25
    static let maxScanGap: TimeInterval = 0.750
}

struct TeamsSpeakerEvidence: Equatable, Sendable {
    static let empty = Self(claims: [], scans: .empty)
    fileprivate let claims: [SpeakerSpan]
    let scans: TeamsScanSummary

    func name(for segment: TranscriptSegment) -> TeamsSpeakerName? {
        guard segment.start.isFinite, segment.end.isFinite, segment.start >= 0,
              segment.end > segment.start else { return nil }
        var names: [TeamsSpeakerName: Double] = [:]
        var silence: Double = 0
        var index = firstEnding(atOrAfter: segment.start)
        while index < claims.count, claims[index].start < segment.end {
            let time = min(claims[index].end, segment.end) - max(claims[index].start, segment.start)
            switch claims[index].claim {
            case .name(let name): names[name, default: 0] += time
            case .silence: silence += time
            }
            index += 1
        }
        let ranked = names.sorted { $0.value > $1.value }
        guard let winner = ranked.first else { return nil }
        let second = ranked.dropFirst().first?.value ?? 0

        let length = segment.end - segment.start
        let named = names.values.reduce(0, +)
        // All time that no name and no silence claims is unknown, also time that no scan claims.
        let unknown = length - named - silence
        let judged = named + unknown
        guard winner.value >= TeamsNameRule.winningShare * judged,
              second <= TeamsNameRule.secondNameShare * judged,
              winner.value >= TeamsNameRule.minimumNamedShare * length else { return nil }
        return winner.key
    }

    private func firstEnding(atOrAfter time: Double) -> Int {
        var low = 0
        var high = claims.count
        while low < high {
            let middle = low + (high - low) / 2
            if claims[middle].end < time { low = middle + 1 } else { high = middle }
        }
        return low
    }
}

fileprivate enum Claim: Equatable, Sendable {
    case name(TeamsSpeakerName)
    case silence

    /// Nil for a result that leaves the speaker unknown.
    init?(_ result: TeamsScanResult) {
        switch result {
        case .named(let name): self = .name(name)
        // Each short stop between sentences gives this result.
        case .unnamed(.noHighlightedTile): self = .silence
        case .unnamed: return nil
        }
    }
}

fileprivate struct SpeakerSpan: Equatable, Sendable {
    let start: Double
    let end: Double
    let claim: Claim
}
