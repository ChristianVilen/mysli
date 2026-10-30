import CoreMedia

/// A moment on the host clock, in seconds. ScreenCaptureKit stamps audio buffers on this
/// clock, so a click time read here compares directly with a buffer's presentation time.
struct HostTime: Comparable, Hashable, Sendable {
    let seconds: TimeInterval

    init(seconds: TimeInterval) { self.seconds = seconds }

    init(_ time: CMTime) { seconds = time.seconds }

    static func now() -> HostTime { HostTime(CMClockGetTime(CMClockGetHostTimeClock())) }

    static func < (lhs: HostTime, rhs: HostTime) -> Bool { lhs.seconds < rhs.seconds }
    static func - (lhs: HostTime, rhs: HostTime) -> TimeInterval { lhs.seconds - rhs.seconds }
    static func + (lhs: HostTime, rhs: TimeInterval) -> HostTime { HostTime(seconds: lhs.seconds + rhs) }
}

/// The one mapping from host time to recorded time and to the position in the audio files.
/// Both tracks use it. A pure value: no clock reads, no audio.
///
/// - Host time: when audio was captured (buffer presentation times) or when the user clicked.
/// - Recorded time: kept audio since `origin`, without paused spans. What the timer shows.
/// - File position: recorded time plus `resumeGap` for each earlier resume. The CAF files
///   and the transcript use it.
///
/// A change only appends a boundary after the last one, so the mapping of any time before
/// the last boundary never changes. A copy that is one change old was still right for every
/// buffer it already cut.
struct RecordingClock: Equatable, Sendable {
    /// Silence that each resume leaves in both files. More than `Transcript.merge`'s 2 s join
    /// gap, so the final transcript never joins speech across a pause.
    static let resumeGap: TimeInterval = 3

    /// Recorded time 0 and file position 0.
    let origin: HostTime
    /// Pause and resume times in order: [pause, resume, pause, ...]. Each is after the one before.
    private var boundaries: [HostTime] = []

    init(origin: HostTime) { self.origin = origin }

    var isPaused: Bool { boundaries.count % 2 == 1 }

    /// Starts a pause at `time`. Returns false and changes nothing when already paused, or when
    /// `time` is not after the origin and the last boundary.
    @discardableResult
    mutating func pause(at time: HostTime) -> Bool {
        guard !isPaused else { return false }
        return append(time)
    }

    /// Ends the pause at `time`. Returns false and changes nothing when not paused, or when
    /// `time` is not after the pause.
    @discardableResult
    mutating func resume(at time: HostTime) -> Bool {
        guard isPaused else { return false }
        return append(time)
    }

    func recordedTime(at time: HostTime) -> TimeInterval {
        runs.reduce(0) { sum, run in sum + max(0, min(run.end ?? time, time) - run.start) }
    }

    /// Where audio captured at `time` lands in the files. Nil before `origin` or inside a pause.
    func filePosition(at time: HostTime) -> TimeInterval? {
        runs.firstIndex { $0.contains(time) }.map { filePosition(at: time, inRun: $0) }
    }

    struct FileInterval: Equatable, Sendable {
        let start: TimeInterval
        let end: TimeInterval
    }

    func fileIntervalInOneRun(from start: HostTime, to end: HostTime) -> FileInterval? {
        guard origin.seconds.isFinite, start.seconds.isFinite, end.seconds.isFinite, start <= end,
              let index = runs.firstIndex(where: { $0.contains(start) && $0.contains(end) }) else { return nil }
        return FileInterval(start: filePosition(at: start, inRun: index),
                            end: filePosition(at: end, inRun: index))
    }

    func keptFileIntervals(from start: HostTime, to end: HostTime) -> [FileInterval] {
        guard origin.seconds.isFinite, start.seconds.isFinite, end.seconds.isFinite, start <= end else { return [] }
        return runs.enumerated().compactMap { index, run in
            let first = max(start, run.start)
            let last = min(end, run.end ?? end)
            guard first <= last, run.contains(first) else { return nil }
            let position = filePosition(at: first, inRun: index)
            return FileInterval(start: position, end: position + (last - first))
        }
    }

    /// The recorded time of a file position. A position inside a resume gap maps to the pause
    /// the gap marks.
    func recordedTime(atFilePosition position: TimeInterval) -> TimeInterval {
        var gaps: TimeInterval = 0
        for pause in pauses {
            if position < pause.at + gaps { return position - gaps }
            if pause.duration == nil || position < pause.at + gaps + Self.resumeGap { return pause.at }
            gaps += Self.resumeGap
        }
        return position - gaps
    }

    /// Each pause so far, in recorded time. `duration` is host seconds paused, nil while the
    /// pause lasts.
    var pauses: [(at: TimeInterval, duration: TimeInterval?)] {
        stride(from: 0, to: boundaries.count, by: 2).map { index in
            let pause = boundaries[index]
            let resume = index + 1 < boundaries.count ? boundaries[index + 1] : nil
            return (recordedTime(at: pause), resume.map { $0 - pause })
        }
    }

    /// Which frames of one buffer to keep, and where each kept piece goes in the file. Every
    /// track is cut by the same boundaries, so all tracks cut at the same host time, each to
    /// its nearest frame.
    func cut(start: HostTime, frameCount: Int, sampleRate: Double) -> BufferCut {
        let end = start + Double(frameCount) / sampleRate
        func frame(at time: HostTime) -> Int {
            min(max(Int(((time - start) * sampleRate).rounded()), 0), frameCount)
        }
        var pieces: [BufferCut.Piece] = []
        for (index, run) in runs.enumerated() {
            let first = frame(at: max(run.start, start))
            let last = frame(at: min(run.end ?? end, end))
            guard first < last else { continue }
            // Rounding can put the first frame up to half a frame before the run starts.
            let firstTime = max(run.start, start + Double(first) / sampleRate)
            pieces.append(BufferCut.Piece(run: index, frames: first..<last,
                                          filePosition: filePosition(at: firstTime, inRun: index)))
        }
        return BufferCut(pieces: pieces, endsInPause: !runs.contains { $0.contains(end) })
    }

    private mutating func append(_ boundary: HostTime) -> Bool {
        guard boundary > boundaries.last ?? origin else { return false }
        boundaries.append(boundary)
        return true
    }

    private func filePosition(at time: HostTime, inRun run: Int) -> TimeInterval {
        recordedTime(at: time) + Double(run) * Self.resumeGap
    }

    /// Kept host intervals: run 0 is [origin, first pause), run i is [i-th resume, next pause).
    /// The last run is open (end nil) unless paused; while paused no run follows the last pause.
    private var runs: [Run] {
        let starts = [origin] + stride(from: 1, to: boundaries.count, by: 2).map { boundaries[$0] }
        return starts.enumerated().map { index, start in
            let pause = 2 * index
            return Run(start: start, end: pause < boundaries.count ? boundaries[pause] : nil)
        }
    }

    private struct Run {
        let start: HostTime
        let end: HostTime?

        func contains(_ time: HostTime) -> Bool {
            start <= time && end.map { time < $0 } ?? true
        }
    }
}

enum RecordedTime {
    static func format(_ interval: TimeInterval) -> String {
        let seconds = Int(max(0, interval))
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds % 60)
            : String(format: "%d:%02d", minutes, seconds % 60)
    }
}

/// Only `RecordingClock` can decide which frames to keep.
struct BufferCut: Equatable {
    struct Piece: Equatable {
        /// 0 before the first pause, one more after each resume.
        let run: Int
        /// Frames of the source buffer, at the source sample rate.
        let frames: Range<Int>
        /// File position, in seconds, of `frames.lowerBound`.
        let filePosition: TimeInterval

        fileprivate init(run: Int, frames: Range<Int>, filePosition: TimeInterval) {
            self.run = run
            self.frames = frames
            self.filePosition = filePosition
        }
    }

    let pieces: [Piece]
    /// The buffer's end is in no run: it reaches into a pause, or ends exactly at one.
    let endsInPause: Bool

    fileprivate init(pieces: [Piece], endsInPause: Bool) {
        self.pieces = pieces
        self.endsInPause = endsInPause
    }
}
