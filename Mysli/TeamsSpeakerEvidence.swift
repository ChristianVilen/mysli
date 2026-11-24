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

    mutating func evidenceSoFar(clock: RecordingClock, changed: (ClosedRange<Double>) -> Void) -> TeamsSpeakerEvidence {
        // A pause or resume can change the mapping of a scan that straddles its boundary.
        let reset = projectedClock != clock
        if reset {
            projectedClock = clock
            projectedCount = 0
            liveProjection = Projection()
            changed(-.infinity ... .infinity)
        }
        guard clock.origin.seconds.isFinite else { return .empty }
        for entry in entries.dropFirst(projectedCount) {
            liveProjection.add(entry, clock: clock) { span in
                if !reset { changed(span) }
            }
        }
        projectedCount = entries.count
        return liveProjection.evidence(scans: .empty)
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
        private var claims: [SpeakerSpan] = []
        /// What invalid scans claim, merged. An invalid scan can be out of order, so these can lie over `claims`.
        private var uncertain: [SpeakerSpan] = []
        private var previous: Entry?
        private var latestEnd = -Double.infinity

        mutating func add(_ entry: Entry, clock: RecordingClock, changed: (ClosedRange<Double>) -> Void = { _ in }) {
            let sample = entry.sample
            guard sample.hasFiniteTimes else {
                previous = nil
                return
            }
            let ordered = sample.began.seconds >= latestEnd
            latestEnd = max(latestEnd, sample.began.seconds, sample.ended.seconds)
            guard ordered, sample.ended >= sample.began, sample.sequence >= 0, sample.sourceID?.isEmpty == false,
                  let scan = clock.fileIntervalInOneRun(from: sample.began, to: sample.ended) else {
                for span in clock.keptFileIntervals(from: min(sample.began, sample.ended),
                                                    to: max(sample.began, sample.ended)) where span.end > span.start {
                    addUncertainty(SpeakerSpan(start: span.start, end: span.end, claim: .unknown))
                    changed(span.start...span.end)
                }
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
                    append(SpeakerSpan(start: gap.start, end: gap.end, claim: claim), changed: changed)
                } else {
                    let middle = (gap.start + gap.end) / 2
                    append(SpeakerSpan(start: gap.start, end: middle, claim: earlierClaim), changed: changed)
                    append(SpeakerSpan(start: middle, end: gap.end, claim: claim), changed: changed)
                }
            }
            append(SpeakerSpan(start: scan.start, end: scan.end, claim: claim), changed: changed)
            previous = entry
        }

        func evidence(scans: TeamsScanSummary) -> TeamsSpeakerEvidence {
            TeamsSpeakerEvidence(claims: claims, uncertain: uncertain, scans: scans)
        }

        private mutating func append(_ span: SpeakerSpan, changed: (ClosedRange<Double>) -> Void) {
            guard span.end > span.start else { return }
            claims.append(span)
            changed(span.start...span.end)
        }

        private mutating func addUncertainty(_ span: SpeakerSpan) {
            let first = uncertain.lastIndex { $0.end < span.start }.map { $0 + 1 } ?? 0
            var end = first
            while end < uncertain.count, uncertain[end].start <= span.end { end += 1 }
            guard first < end else {
                uncertain.insert(span, at: first)
                return
            }
            let merged = SpeakerSpan(start: min(span.start, uncertain[first].start),
                                     end: max(span.end, uncertain[end - 1].end), claim: .unknown)
            uncertain.replaceSubrange(first..<end, with: CollectionOfOne(merged))
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
    static let empty = Self(claims: [], uncertain: [], scans: .empty)
    fileprivate let claims: [SpeakerSpan]
    fileprivate let uncertain: [SpeakerSpan]
    let scans: TeamsScanSummary

    func name(for segment: TranscriptSegment) -> TeamsSpeakerName? {
        guard segment.start.isFinite, segment.end.isFinite, segment.start >= 0,
              segment.end > segment.start else { return nil }
        var names: [TeamsSpeakerName: Double] = [:]
        var silence: Double = 0
        var index = firstEnding(atOrAfter: segment.start, in: claims)
        while index < claims.count, claims[index].start < segment.end {
            let time = min(claims[index].end, segment.end) - max(claims[index].start, segment.start)
            switch claims[index].claim {
            case .name(let name): names[name, default: 0] += time
            case .silence: silence += time
            case .unknown: break
            }
            index += 1
        }
        var winner: (name: TeamsSpeakerName, time: Double)?
        var second: Double = 0
        for (name, time) in names {
            if time > winner?.time ?? 0 {
                second = winner?.time ?? 0
                winner = (name, time)
            } else {
                second = max(second, time)
            }
        }
        guard let winner else { return nil }

        let length = segment.end - segment.start
        let named = names.values.reduce(0, +)
        // All time that no name and no silence claims is unknown, also time that no scan claims.
        let unknown = length - named - silence + doubleCounted(in: segment)
        let judged = named + unknown
        guard winner.time >= TeamsNameRule.winningShare * judged,
              second <= TeamsNameRule.secondNameShare * judged,
              winner.time >= TeamsNameRule.minimumNamedShare * length else { return nil }
        return winner.name
    }

    /// Time in the segment where an invalid scan lies over a claim. It counts again, as unknown,
    /// which only makes the rule more careful.
    private func doubleCounted(in segment: TranscriptSegment) -> Double {
        var claim = firstEnding(atOrAfter: segment.start, in: claims)
        var bad = firstEnding(atOrAfter: segment.start, in: uncertain)
        var time: Double = 0
        while claim < claims.count, bad < uncertain.count,
              claims[claim].start < segment.end, uncertain[bad].start < segment.end {
            let start = max(segment.start, claims[claim].start, uncertain[bad].start)
            let end = min(segment.end, claims[claim].end, uncertain[bad].end)
            time += max(0, end - start)
            if claims[claim].end < uncertain[bad].end { claim += 1 } else { bad += 1 }
        }
        return time
    }

    private func firstEnding(atOrAfter time: Double, in spans: [SpeakerSpan]) -> Int {
        var low = 0
        var high = spans.count
        while low < high {
            let middle = low + (high - low) / 2
            if spans[middle].end < time { low = middle + 1 } else { high = middle }
        }
        return low
    }
}

fileprivate enum Claim: Equatable, Sendable {
    case name(TeamsSpeakerName)
    case silence
    case unknown

    init(_ result: TeamsScanResult) {
        switch result {
        case .named(let name): self = .name(name)
        // Each short stop between sentences gives this result.
        case .unnamed(.noHighlightedTile): self = .silence
        case .unnamed: self = .unknown
        }
    }
}

fileprivate struct SpeakerSpan: Equatable, Sendable {
    let start: Double
    let end: Double
    let claim: Claim
}
