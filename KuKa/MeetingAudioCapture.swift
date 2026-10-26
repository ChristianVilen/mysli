import AVFAudio
import CoreMedia
import ScreenCaptureKit

protocol MeetingAudioCapturing {
    @MainActor
    func start(into meeting: MeetingFolder,
               onInterrupted: @escaping @MainActor (_ reason: String) -> Void) async throws -> ActiveRecording
}

protocol ActiveRecording: AnyObject {
    /// Set on the main actor just before `onInterrupted` runs. The capture can
    /// end before `start` returns, while the caller cannot yet match the
    /// callback to this recording, so the caller checks this afterwards.
    var endReason: String? { get }
    func stop()
}

final class ScreenCaptureMeetingAudio: MeetingAudioCapturing {
    @MainActor
    func start(into meeting: MeetingFolder,
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

        let recording = try ScreenCaptureRecording(meeting: meeting, onInterrupted: onInterrupted)
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

/// The writers, `timelineStart` and `isClosed` are used only on `queue`.
/// `stream` and `endReason` are used only on the main actor, where `start`,
/// `stop` and the interruption hop run. So nothing needs a lock.
final class ScreenCaptureRecording:NSObject, ActiveRecording, SCStreamOutput, SCStreamDelegate {
    let queue = DispatchQueue(label: "ku-ka.meeting-audio")
    var stream: SCStream?
    private(set) var endReason: String?
    private let onInterrupted: @MainActor (String) -> Void
    private let writers: [MeetingTrack: AudioTrackWriter]
    /// Presentation time of the first buffer of any track. Both outputs use
    /// the host clock (measured), so both writers measure from it and the
    /// tracks share one timeline.
    private var timelineStart: CMTime?
    private var isClosed = false

    init(meeting: MeetingFolder, onInterrupted: @escaping @MainActor (String) -> Void) throws {
        self.onInterrupted = onInterrupted
        var writers: [MeetingTrack: AudioTrackWriter] = [:]
        for track in MeetingTrack.allCases {
            writers[track] = try AudioTrackWriter(url: meeting.audioURL(track))
        }
        self.writers = writers
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !isClosed, let track = MeetingTrack(type), sampleBuffer.isValid else { return }
        let start = timelineStart ?? sampleBuffer.presentationTimeStamp
        timelineStart = start
        do {
            try writers[track]?.append(sampleBuffer, timelineStart: start)
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
    }

    private func stopStream() {
        stream?.stopCapture { _ in }
        stream = nil
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

    init(url: URL) throws {
        file = try AVAudioFile(forWriting: url, settings: Self.fileFormat.settings,
                               commonFormat: .pcmFormatInt16, interleaved: true)
    }

    func append(_ sampleBuffer: CMSampleBuffer, timelineStart: CMTime) throws {
        let frames = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frames > 0 else { return }
        guard var description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
              let inputFormat = AVAudioFormat(streamDescription: &description),
              let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frames) else {
            throw MeetingCaptureError.unsupportedAudioFormat
        }
        input.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: input.mutableAudioBufferList)
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }

        if converter?.inputFormat != inputFormat {
            converter = AVAudioConverter(from: inputFormat, to: Self.fileFormat)
        }
        guard let converter else { throw MeetingCaptureError.unsupportedAudioFormat }

        let bufferStart = CMTimeSubtract(sampleBuffer.presentationTimeStamp, timelineStart).seconds
        try writeSilence(frames: AudioTimeline.silenceFrames(
            written: file.framePosition, bufferStart: bufferStart, sampleRate: Self.fileFormat.sampleRate))

        let capacity = AVAudioFrameCount((Double(frames) * Self.fileFormat.sampleRate / inputFormat.sampleRate).rounded(.up)) + 1
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
        if output.frameLength > 0 { try file.write(from: output) }
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
