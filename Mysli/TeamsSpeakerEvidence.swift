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
        private var positive: [SpeakerSpan] = []
        private var uncertain: [SpeakerSpan] = []
        private var observed: [SpeakerSpan] = []
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
            let mappedScan = clock.fileIntervalInOneRun(from: sample.began, to: sample.ended)
            let valid = ordered && sample.ended >= sample.began
                && sample.sequence >= 0
                && sample.ended <= sample.began + 0.150
                && sample.sourceID?.isEmpty == false
                && mappedScan != nil

            if !valid || sample.speaker == nil {
                for span in clock.keptFileIntervals(from: min(sample.began, sample.ended),
                                                    to: max(sample.began, sample.ended)) {
                    addUncertainty(SpeakerSpan(start: span.start, end: span.end, name: nil))
                    changed(span.start...span.end)
                }
            }
            guard valid else {
                previous = nil
                return
            }
            if let name = sample.speaker, let span = mappedScan {
                observed.append(SpeakerSpan(start: span.start, end: span.end, name: name))
                changed(span.start...span.end)
            }
            if let earlier = previous, let name = sample.speaker,
               earlier.sample.speaker == name,
               earlier.runID == entry.runID,
               earlier.sample.sourceID == sample.sourceID,
               earlier.sample.sequence < Int.max,
               sample.sequence == earlier.sample.sequence + 1,
               sample.began <= earlier.sample.ended + 0.750,
               let span = clock.fileIntervalInOneRun(from: earlier.sample.ended, to: sample.began), span.end > span.start {
                positive.append(SpeakerSpan(start: span.start, end: span.end, name: name))
                changed(span.start...span.end)
            }
            previous = entry
        }

        func evidence(scans: TeamsScanSummary) -> TeamsSpeakerEvidence {
            TeamsSpeakerEvidence(positive: positive, uncertain: uncertain, observed: observed, scans: scans)
        }

        private mutating func addUncertainty(_ span: SpeakerSpan) {
            // Scans normally arrive in order. Out-of-order scans can still veto earlier evidence.
            let first = uncertain.lastIndex { $0.end < span.start }.map { $0 + 1 } ?? 0
            var end = first
            while end < uncertain.count, uncertain[end].start <= span.end { end += 1 }
            guard first < end else {
                uncertain.insert(span, at: first)
                return
            }
            let merged = SpeakerSpan(start: min(span.start, uncertain[first].start),
                                     end: max(span.end, uncertain[end - 1].end), name: nil)
            uncertain.replaceSubrange(first..<end, with: CollectionOfOne(merged))
        }
    }
}

struct TeamsSpeakerEvidence: Equatable, Sendable {
    static let empty = Self(positive: [], uncertain: [], observed: [], scans: .empty)
    fileprivate let positive: [SpeakerSpan]
    fileprivate let uncertain: [SpeakerSpan]
    fileprivate let observed: [SpeakerSpan]
    let scans: TeamsScanSummary

    func name(for segment: TranscriptSegment) -> TeamsSpeakerName? {
        guard !positive.isEmpty, segment.start.isFinite, segment.end.isFinite, segment.start >= 0,
              segment.end > segment.start else { return nil }
        let unknown = firstEnding(atOrAfter: segment.start, in: uncertain)
        if unknown < uncertain.count, uncertain[unknown].start < segment.end { return nil }

        var index = firstEnding(atOrAfter: segment.start, in: positive)
        var candidate: TeamsSpeakerName?
        var coverage: Double = 0
        var cursor = segment.start
        while index < positive.count {
            let span = positive[index]
            guard span.start < segment.end else { break }
            let start = max(span.start, segment.start)
            let end = min(span.end, segment.end)
            if end > start {
                guard start - cursor <= 0.750 else { return nil }
                if let candidate, candidate != span.name { return nil }
                candidate = span.name
                coverage += end - start
                cursor = end
            }
            index += 1
        }
        guard segment.end - cursor <= 0.750,
              coverage >= 0.9 * (segment.end - segment.start) else { return nil }
        var scan = firstEnding(atOrAfter: segment.start, in: observed)
        while scan < observed.count, observed[scan].start < segment.end {
            guard observed[scan].name == candidate else { return nil }
            scan += 1
        }
        return candidate
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

fileprivate struct SpeakerSpan: Equatable, Sendable {
    let start: Double
    let end: Double
    let name: TeamsSpeakerName?
}
