import AVFAudio
import CoreMedia
import ScreenCaptureKit
import os

protocol MeetingAudioCapturing {
    /// The caller reads the host clock just before this call to set the recording's origin.
    /// A buffer can start before the origin; `RecordingClock` clips those frames.
    @MainActor
    func start(into meeting: MeetingFolder, clock: RecordingClock,
               onInterrupted: @escaping @MainActor (_ reason: String) -> Void) async throws -> ActiveRecording
}

protocol ActiveRecording: AnyObject {
    /// Set on the main actor just before `onInterrupted` runs. The capture can
    /// end before `start` returns, while the caller cannot yet match the
    /// callback to this recording, so the caller checks this afterwards.
    var endReason: String? { get }
    /// Converted buffers with file positions, for the live view. Omits inserted silence and
    /// converter drain output. Bounded and lossy (see `LiveAudioFeed`), with one reader per
    /// stream. Finishes when the recording stops or is interrupted.
    var writtenAudio: [MeetingTrack: AsyncStream<WrittenAudio>] { get }
    @MainActor func audioLevels() -> RecordingAudioLevels
    /// Every buffer the sample queue takes after this call is cut by `clock`. The caller reads
    /// the click time and calls this in one main-actor step. A buffer reaches the queue only
    /// after its audio was captured, so no buffer already written holds audio from after it.
    @MainActor func apply(_ clock: RecordingClock)
    func stop()
}

final class ScreenCaptureMeetingAudio: MeetingAudioCapturing {
    @MainActor
    func start(into meeting: MeetingFolder, clock: RecordingClock,
               onInterrupted: @escaping @MainActor (String) -> Void) async throws -> ActiveRecording {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch SCStreamError.userDeclined {
            throw MeetingCaptureError.screenRecordingDeclined
        }
        // The stream is bound to a display. The built-in one is the least
        // likely to be unplugged in the middle of a call.
        guard let display = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 })
                ?? content.displays.first else { throw MeetingCaptureError.noDisplay }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 1
        config.captureMicrophone = true
        // No .screen output is added (audio arrives without one, measured),
        // but the stream still captures the display, so keep that tiny.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let recording = try ScreenCaptureRecording(meeting: meeting, clock: clock, onInterrupted: onInterrupted)
        let stream = SCStream(filter: filter, configuration: config, delegate: recording)
        do {
            for type in [SCStreamOutputType.audio, .microphone] {
                try stream.addStreamOutput(recording, type: type, sampleHandlerQueue: recording.queue)
            }
            recording.stream = stream
            try await stream.startCapture()
        } catch {
            recording.stop()
            throw error
        }
        return recording
    }
}

enum MeetingCaptureError: LocalizedError {
    case noDisplay
    case screenRecordingDeclined
    case unsupportedAudioFormat

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display is available to capture audio from."
        case .screenRecordingDeclined: return "Ku-Ka needs Screen Recording permission to record a meeting."
        case .unsupportedAudioFormat: return "Ku-Ka cannot convert the audio format of this device."
        }
    }
}

extension MeetingTrack {
    init?(_ type: SCStreamOutputType) {
        switch type {
        case .audio: self = .system
        case .microphone: self = .microphone
        default: return nil
        }
    }
}

final class ScreenCaptureRecording:NSObject, ActiveRecording, SCStreamOutput, SCStreamDelegate {
    /// Where the recording's first buffer, of either track, may start, in seconds after the
    /// clock's origin. The origin is read just before the capture starts, so a first buffer
    /// outside this range means the presentation times are not on the host clock, and padding
    /// to them would write the wrong amount of silence. The other track's first buffer is not
    /// checked: ScreenCaptureKit can send no system audio while the Mac is silent, as in a
    /// waiting room, so it can come much later.
    private static let firstBufferOffsets: ClosedRange<TimeInterval> = -1...60

    let queue = DispatchQueue(label: "ku-ka.meeting-audio")
    var stream: SCStream?
    private(set) var endReason: String?
    private let onInterrupted: @MainActor (String) -> Void
    private let writers: [MeetingTrack: AudioTrackWriter]
    private let feeds: [MeetingTrack: LiveAudioFeed]
    /// The latest clock from the controller. Both outputs stamp buffers on the host clock
    /// (measured), so one clock cuts both tracks on one timeline. The queue copies it once
    /// per buffer and never changes it.
    private let clock: OSAllocatedUnfairLock<RecordingClock>
    private var startedTracks: Set<MeetingTrack> = []
    private var isClosed = false
    private let meter = OSAllocatedUnfairLock(initialState: RecordingAudioMeter())

    var writtenAudio: [MeetingTrack: AsyncStream<WrittenAudio>] { feeds.mapValues(\.audio) }

    @MainActor
    func audioLevels() -> RecordingAudioLevels {
        let snapshot = meter.withLock { $0 }
        return snapshot.levels(at: ProcessInfo.processInfo.systemUptime)
    }

    @MainActor
    func apply(_ clock: RecordingClock) {
        self.clock.withLock {
            assert($0.origin == clock.origin, "A clock only gains boundaries; its origin never changes.")
            $0 = clock
        }
    }

    init(meeting: MeetingFolder, clock: RecordingClock, onInterrupted: @escaping @MainActor (String) -> Void) throws {
        self.onInterrupted = onInterrupted
        var writers: [MeetingTrack: AudioTrackWriter] = [:]
        for track in MeetingTrack.allCases {
            writers[track] = try AudioTrackWriter(url: meeting.audioURL(track))
        }
        self.writers = writers
        feeds = Dictionary(uniqueKeysWithValues: MeetingTrack.allCases.map { ($0, LiveAudioFeed()) })
        self.clock = OSAllocatedUnfairLock(initialState: clock)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !isClosed, let track = MeetingTrack(type), sampleBuffer.isValid else { return }
        let clock = self.clock.withLock { $0 }
        let isRecordingStart = startedTracks.isEmpty
        if startedTracks.insert(track).inserted {
            let offset = HostTime(sampleBuffer.presentationTimeStamp) - clock.origin
            NSLog("Ku-Ka: first %@ buffer starts %.3f s after the clock origin", "\(track)", offset)
            guard !isRecordingStart || Self.firstBufferOffsets.contains(offset) else {
                interrupt(reason: "Ku-Ka could not match the audio clock (offset \(Int(offset.rounded())) s).")
                return
            }
        }
        do {
            for audio in try writers[track]?.append(sampleBuffer, clock: clock) ?? [] {
                let receivedAt = ProcessInfo.processInfo.systemUptime
                meter.withLock { $0.record(rms: audio.rms, for: track, at: receivedAt) }
                feeds[track]?.offer(audio)
            }
        } catch {
            interrupt(reason: "Ku-Ka could not write the audio file (\(error.localizedDescription)).")
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Async: the SDK does not say which thread calls this, and a sync
        // hop from `queue` onto itself would deadlock.
        queue.async { self.interrupt(reason: error.localizedDescription) }
    }

    func stop() {
        stopStream()
        queue.sync { closeFiles() }
    }

    private func interrupt(reason: String) {
        guard !isClosed else { return }
        closeFiles()
        Task { @MainActor in
            stopStream()
            endReason = reason
            onInterrupted(reason)
        }
    }

    private func closeFiles() {
        guard !isClosed else { return }
        isClosed = true
        for writer in writers.values { writer.close() }
        for feed in feeds.values { feed.finish() }
        meter.withLock { $0 = RecordingAudioMeter() }
    }

    private func stopStream() {
        stream?.stopCapture { _ in }
        stream = nil
    }
}

/// One converted buffer, exactly as it went into a track's file: 16 kHz mono Int16.
/// `@unchecked Sendable`: the writer makes a new output buffer for each conversion and never
/// touches it after returning it.
struct WrittenAudio: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    /// File position, in seconds, of the first frame.
    let filePosition: TimeInterval
    let rms: Double
}

/// The hand-off from the sample queue to one live analyzer. When `capacity` buffers wait, the
/// oldest is dropped, so `offer` never waits and a slow analyzer cannot slow the recording.
/// The analyzer sees the hole through the next buffer's file position.
final class LiveAudioFeed: Sendable {
    /// About 5 s of ScreenCaptureKit's roughly 20 ms buffers.
    static let capacity = 256

    let audio: AsyncStream<WrittenAudio>
    private let continuation: AsyncStream<WrittenAudio>.Continuation

    init(capacity: Int = LiveAudioFeed.capacity) {
        (audio, continuation) = AsyncStream.makeStream(of: WrittenAudio.self,
                                                       bufferingPolicy: .bufferingNewest(capacity))
    }

    func offer(_ audio: WrittenAudio) {
        continuation.yield(audio)
    }

    func finish() {
        continuation.finish()
    }
}

/// Writes one track as 16 kHz, mono, 16-bit linear PCM in a CAF file, the
/// format SpeechAnalyzer works in, about 115 MB per hour. LPCM in CAF has no
/// index to finalize, so the file stays readable up to the last write after
/// a crash (measured with `kill -9`).
final class AudioTrackWriter {
    static let fileFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                          channels: 1, interleaved: true)!
    private let file: AVAudioFile
    /// Built from each buffer's own format and rebuilt when it changes: the
    /// microphone's format depends on the device (24 kHz for AirPods, 48 kHz
    /// built in), and the device can change in the middle of a call.
    private var converter: AVAudioConverter?
    /// The run the converter last took input for. Nil after a drain.
    private var openRun: Int?

    init(url: URL) throws {
        file = try AVAudioFile(forWriting: url, settings: Self.fileFormat.settings,
                               commonFormat: .pcmFormatInt16, interleaved: true)
    }

    /// Writes the frames of `sampleBuffer` that `clock` keeps, each at its file position, and
    /// pads gaps with silence, so each resume leaves the clock's gap. Returns each converted
    /// buffer it wrote; a buffer inside a pause returns none.
    func append(_ sampleBuffer: CMSampleBuffer, clock: RecordingClock) throws -> [WrittenAudio] {
        let frameCount = sampleBuffer.numSamples
        guard frameCount > 0 else { return [] }
        guard var description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
              let inputFormat = AVAudioFormat(streamDescription: &description) else {
            throw MeetingCaptureError.unsupportedAudioFormat
        }
        let cut = clock.cut(start: HostTime(sampleBuffer.presentationTimeStamp), frameCount: frameCount,
                            sampleRate: inputFormat.sampleRate)
        var written: [WrittenAudio] = []
        for piece in cut.pieces {
            if let openRun, openRun != piece.run { try drain() }
            let input = try copy(piece.frames, of: sampleBuffer, format: inputFormat)
            try writeSilence(frames: AudioTimeline.silenceFrames(
                written: file.framePosition, bufferStart: piece.filePosition, sampleRate: Self.fileFormat.sampleRate))
            if let audio = try convertAndWrite(input) { written.append(audio) }
            openRun = piece.run
        }
        if cut.endsInPause, openRun != nil { try drain() }
        return written
    }

    private func copy(_ frames: Range<Int>, of sampleBuffer: CMSampleBuffer,
                      format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames.count)) else {
            throw MeetingCaptureError.unsupportedAudioFormat
        }
        input.frameLength = AVAudioFrameCount(frames.count)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: Int32(frames.lowerBound), frameCount: Int32(frames.count), into: input.mutableAudioBufferList)
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return input
    }

    private func convertAndWrite(_ input: AVAudioPCMBuffer) throws -> WrittenAudio? {
        if converter?.inputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: Self.fileFormat)
        }
        guard let converter else { throw MeetingCaptureError.unsupportedAudioFormat }

        let capacity = AVAudioFrameCount((Double(input.frameLength) * Self.fileFormat.sampleRate
                                          / input.format.sampleRate).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: Self.fileFormat, frameCapacity: capacity) else {
            throw MeetingCaptureError.unsupportedAudioFormat
        }
        var consumed = false
        var conversionError: NSError?
        // .noDataNow instead of .endOfStream keeps the converter's state, so
        // the next buffer continues the same resampled stream.
        let result = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return input
        }
        if result == .error { throw conversionError ?? NSError(domain: NSOSStatusErrorDomain, code: -1) }
        guard output.frameLength > 0 else { return nil }
        let position = Double(file.framePosition) / Self.fileFormat.sampleRate
        try file.write(from: output)
        return WrittenAudio(buffer: output, filePosition: position, rms: Self.rms(of: output))
    }

    /// Writes the frames the converter still holds back (6 at 48 kHz, measured) and resets
    /// it, so no pre-pause frame comes out after the resume gap. The drained frames go to the
    /// file only, not into a `WrittenAudio`.
    private func drain() throws {
        openRun = nil
        guard let converter else { return }
        defer { converter.reset() }
        // `convert` reports .endOfStream only on a call that returns no frames.
        var status = AVAudioConverterOutputStatus.haveData
        while status == .haveData {
            guard let output = AVAudioPCMBuffer(pcmFormat: Self.fileFormat, frameCapacity: 1_024) else {
                throw MeetingCaptureError.unsupportedAudioFormat
            }
            var conversionError: NSError?
            status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                inputStatus.pointee = .endOfStream
                return nil
            }
            if status == .error { throw conversionError ?? NSError(domain: NSOSStatusErrorDomain, code: -1) }
            guard output.frameLength > 0 else { break }
            try file.write(from: output)
        }
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Double {
        let samples = UnsafeBufferPointer(start: buffer.int16ChannelData![0], count: Int(buffer.frameLength))
        let squares = samples.reduce(0.0) { sum, sample in
            let normalized = Double(sample) / 32_768
            return sum + normalized * normalized
        }
        return sqrt(squares / Double(samples.count))
    }

    func close() {
        file.close()
    }

    private func writeSilence(frames: AVAudioFrameCount) throws {
        var remaining = frames
        while remaining > 0 {
            let chunk = min(remaining, 16_000)
            guard let silence = AVAudioPCMBuffer(pcmFormat: Self.fileFormat, frameCapacity: chunk) else { return }
            silence.frameLength = chunk
            for buffer in UnsafeMutableAudioBufferListPointer(silence.mutableAudioBufferList) {
                memset(buffer.mData, 0, Int(buffer.mDataByteSize))
            }
            try file.write(from: silence)
            remaining -= chunk
        }
    }
}

enum AudioTimeline {
    static func silenceFrames(written: AVAudioFramePosition, bufferStart: TimeInterval,
                              sampleRate: Double, tolerance: TimeInterval = 0.05) -> AVAudioFrameCount {
        let expected = AVAudioFramePosition((bufferStart * sampleRate).rounded())
        let gap = expected - written
        return gap > AVAudioFramePosition(tolerance * sampleRate) ? AVAudioFrameCount(clamping: gap) : 0
    }
}
