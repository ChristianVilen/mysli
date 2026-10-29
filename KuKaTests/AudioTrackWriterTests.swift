import AVFAudio
import CoreMedia
import ScreenCaptureKit
import XCTest
@testable import KuKa

final class AudioTrackWriterTests: XCTestCase {
    @MainActor
    func testRecordingPublishesIndependentTrackLevelsAndIgnoresBuffersAfterStop() throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: Date())
        let recording = try makeRecording(into: meeting, clock: RecordingClock(origin: HostTime(seconds: 0)))
        defer { recording.stop() }
        let microphone = try buffer([16_384, -16_384, 16_384, -16_384], at: 0)
        let system = try buffer([8_192, -8_192, 8_192, -8_192], at: 0)

        recording.queue.sync {
            recording.stream(stream, didOutputSampleBuffer: microphone, of: .microphone)
            recording.stream(stream, didOutputSampleBuffer: system, of: .audio)
        }

        let levels = recording.audioLevels()
        XCTAssertEqual(levels.microphone, 0.899656668, accuracy: 0.000001)
        XCTAssertEqual(levels.system, 0.799313336, accuracy: 0.000001)

        recording.stop()
        XCTAssertEqual(recording.audioLevels(), RecordingAudioLevels(microphone: 0, system: 0))

        let afterStop = try buffer([.min, .min, .min, .min], at: 0.00025)
        recording.queue.sync {
            recording.stream(stream, didOutputSampleBuffer: afterStop, of: .microphone)
            recording.stream(stream, didOutputSampleBuffer: afterStop, of: .audio)
        }
        XCTAssertEqual(recording.audioLevels(), RecordingAudioLevels(microphone: 0, system: 0))
    }

    @MainActor
    func testARecordingWritesBothTracksFromTheOriginOfItsClock() throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: Date())
        let recording = try makeRecording(into: meeting, clock: RecordingClock(origin: HostTime(seconds: 100)))
        let microphone = try buffer([1_000, 1_000, 1_000, 1_000], at: 101)
        let system = try buffer([1_000, 1_000, 1_000, 1_000], at: 101)

        recording.queue.sync {
            recording.stream(stream, didOutputSampleBuffer: microphone, of: .microphone)
            recording.stream(stream, didOutputSampleBuffer: system, of: .audio)
        }
        recording.stop()

        for track in MeetingTrack.allCases {
            XCTAssertEqual(try runLengths(in: meeting.audioURL(track)), [SampleRun(0, 16_000), SampleRun(1_000, 4)], "\(track)")
        }
    }

    @MainActor
    func testAFirstBufferOfTheRecordingNinetySecondsAfterTheOriginStopsItAndWritesNoSilence() async throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: Date())
        let interrupted = expectation(description: "the recording stopped")
        let recording = try ScreenCaptureRecording(meeting: meeting, clock: RecordingClock(origin: HostTime(seconds: 100))) { _ in
            interrupted.fulfill()
        }
        defer { recording.stop() }
        let late = try buffer([1_000, 1_000, 1_000, 1_000], at: 190)

        recording.queue.sync {
            recording.stream(stream, didOutputSampleBuffer: late, of: .microphone)
        }

        await fulfillment(of: [interrupted], timeout: 1)
        XCTAssertEqual(recording.endReason, "Ku-Ka could not match the audio clock (offset 90 s).")
        for track in MeetingTrack.allCases {
            XCTAssertEqual(try frameCount(in: meeting.audioURL(track)), 0, "\(track)")
        }
    }

    @MainActor
    func testAFirstBufferOfTheRecordingMoreThanASecondBeforeTheOriginStopsIt() async throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: Date())
        let interrupted = expectation(description: "the recording stopped")
        let recording = try ScreenCaptureRecording(meeting: meeting, clock: RecordingClock(origin: HostTime(seconds: 100))) { _ in
            interrupted.fulfill()
        }
        defer { recording.stop() }
        let system = try buffer([1_000, 1_000, 1_000, 1_000], at: 98)

        recording.queue.sync {
            recording.stream(stream, didOutputSampleBuffer: system, of: .audio)
        }

        await fulfillment(of: [interrupted], timeout: 1)
        XCTAssertEqual(recording.endReason, "Ku-Ka could not match the audio clock (offset -2 s).")
    }

    /// ScreenCaptureKit can send no system audio while the Mac is silent, as in a waiting room.
    @MainActor
    func testAMuchLaterFirstBufferOfTheOtherTrackKeepsRecordingAndIsWrittenAfterItsSilence() throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: Date())
        let recording = try makeRecording(into: meeting, clock: RecordingClock(origin: HostTime(seconds: 100)))
        let microphone = try buffer([1_000, 1_000, 1_000, 1_000], at: 100.2)
        let system = try buffer([1_000, 1_000, 1_000, 1_000], at: 145)

        recording.queue.sync {
            recording.stream(stream, didOutputSampleBuffer: microphone, of: .microphone)
            recording.stream(stream, didOutputSampleBuffer: system, of: .audio)
        }
        XCTAssertGreaterThan(recording.audioLevels().microphone, 0, "still recording")
        XCTAssertGreaterThan(recording.audioLevels().system, 0, "still recording")
        recording.stop()

        XCTAssertEqual(try runLengths(in: meeting.audioURL(.microphone)), [SampleRun(0, 3_200), SampleRun(1_000, 4)])
        XCTAssertEqual(try runLengths(in: meeting.audioURL(.system)), [SampleRun(0, 720_000), SampleRun(1_000, 4)])
    }

    @MainActor
    func testAfterAPausedClockIsAppliedLaterBuffersGiveNoReadingAndNoWrittenAudio() async throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: Date())
        let recording = try makeRecording(into: meeting, clock: RecordingClock(origin: HostTime(seconds: 0)))
        var paused = RecordingClock(origin: HostTime(seconds: 0))
        paused.pause(at: HostTime(seconds: 0.5))
        let afterPause = try buffer([8_192, -8_192, 8_192, -8_192], at: 1)
        let beforePause = try buffer([8_192, -8_192, 8_192, -8_192], at: 0)

        recording.apply(paused)
        // The buffers after the pause go first, so no reading can be left over from earlier ones.
        recording.queue.sync {
            recording.stream(stream, didOutputSampleBuffer: afterPause, of: .microphone)
            recording.stream(stream, didOutputSampleBuffer: afterPause, of: .audio)
        }
        XCTAssertEqual(recording.audioLevels(), .silent, "after the pause")
        recording.queue.sync {
            recording.stream(stream, didOutputSampleBuffer: beforePause, of: .microphone)
            recording.stream(stream, didOutputSampleBuffer: beforePause, of: .audio)
        }
        let levels = recording.audioLevels()
        XCTAssertGreaterThan(levels.microphone, 0, "before the pause")
        XCTAssertGreaterThan(levels.system, 0, "before the pause")
        recording.stop()

        for (track, audio) in recording.writtenAudio {
            var positions: [TimeInterval] = []
            for await written in audio { positions.append(written.filePosition) }
            XCTAssertEqual(positions, [0], "\(track): only the buffer before the pause")
        }
    }

    @MainActor
    func testTheWrittenAudioOfEachTrackCarriesItsFilePosition() async throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: Date())
        var clock = RecordingClock(origin: HostTime(seconds: 0))
        clock.pause(at: HostTime(seconds: 0.01))
        clock.resume(at: HostTime(seconds: 5))
        let recording = try makeRecording(into: meeting, clock: clock)
        let sampleBuffers = try [buffer(Array(repeating: 1_000, count: 160), at: 0),
                                 buffer(Array(repeating: 1_000, count: 160), at: 5)]

        recording.queue.sync {
            for sampleBuffer in sampleBuffers {
                recording.stream(stream, didOutputSampleBuffer: sampleBuffer, of: .microphone)
                recording.stream(stream, didOutputSampleBuffer: sampleBuffer, of: .audio)
            }
        }
        recording.stop()

        for (track, audio) in recording.writtenAudio {
            var positions: [TimeInterval] = []
            for await written in audio { positions.append(written.filePosition) }
            XCTAssertEqual(positions, [0, 3.01], "\(track): the pause's recorded time plus the resume gap")
        }
    }

    @MainActor
    func testStopFinishesTheWrittenAudioOfBothTracks() async throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: Date())
        let recording = try makeRecording(into: meeting, clock: RecordingClock(origin: HostTime(seconds: 0)))
        let finished = expectation(description: "both streams finished")
        finished.expectedFulfillmentCount = 2
        for audio in recording.writtenAudio.values {
            Task {
                for await _ in audio {}
                finished.fulfill()
            }
        }

        recording.stop()

        await fulfillment(of: [finished], timeout: 1)
    }

    func testAFeedNobodyReadsKeepsTheNewestBuffersAndDropsTheOldest() async throws {
        let feed = LiveAudioFeed(capacity: 2)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: AudioTrackWriter.fileFormat, frameCapacity: 1))

        for position in [0.0, 1, 2] {
            feed.offer(WrittenAudio(buffer: buffer, filePosition: position, rms: 0))
        }
        feed.finish()

        var kept: [TimeInterval] = []
        for await audio in feed.audio { kept.append(audio.filePosition) }
        XCTAssertEqual(kept, [1, 2])
    }

    func testRMSUsesWrittenSamplesWithoutCountingTimelinePadding() throws {
        let url = try makeTemporaryDirectory().appendingPathComponent("track.caf")
        let writer = try AudioTrackWriter(url: url)
        let samples: [Int16] = [16_384, -16_384, 16_384, -16_384]

        let written = try writer.append(buffer(samples, at: 1), clock: RecordingClock(origin: HostTime(seconds: 0)))
        writer.close()

        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(try XCTUnwrap(written.first).rms, 0.5, accuracy: 0.000001)
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
        XCTAssertEqual(file.processingFormat.sampleRate, 16_000)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        XCTAssertEqual(file.length, 16_004)
        let recorded = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_004))
        try file.read(into: recorded)
        let data = try XCTUnwrap(recorded.int16ChannelData)[0]
        XCTAssertEqual(Array(UnsafeBufferPointer(start: data, count: 16_000)), Array(repeating: Int16(0), count: 16_000))
        XCTAssertEqual(Array(UnsafeBufferPointer(start: data + 16_000, count: 4)), [16_384, -16_384, 16_384, -16_384])
    }

    func testSilenceAndNegativeFullScaleHaveFiniteRMS() throws {
        let url = try makeTemporaryDirectory().appendingPathComponent("track.caf")
        let writer = try AudioTrackWriter(url: url)
        let clock = RecordingClock(origin: HostTime(seconds: 0))

        XCTAssertEqual(try writer.append(buffer([0, 0, 0, 0], at: 0), clock: clock).map(\.rms), [0])
        XCTAssertEqual(try writer.append(buffer([.min, .min, .min, .min], at: 0.00025), clock: clock).map(\.rms), [1])
        writer.close()
    }

    func testPauseAndResumeLeaveTheResumeGapAndNoPausedAudio() throws {
        let url = try makeTemporaryDirectory().appendingPathComponent("track.caf")
        let writer = try AudioTrackWriter(url: url)
        var clock = RecordingClock(origin: HostTime(seconds: 0))

        _ = try writer.append(buffer(Array(repeating: 1_000, count: 160), at: 0), clock: clock)
        clock.pause(at: HostTime(seconds: 0.01))
        _ = try writer.append(buffer(Array(repeating: .min, count: 160), at: 0.01), clock: clock)
        _ = try writer.append(buffer(Array(repeating: .min, count: 160), at: 0.02), clock: clock)
        clock.resume(at: HostTime(seconds: 0.03))
        _ = try writer.append(buffer(Array(repeating: 2_000, count: 160), at: 0.03), clock: clock)
        writer.close()

        XCTAssertEqual(try runLengths(in: url), [SampleRun(1_000, 160), SampleRun(0, 48_000), SampleRun(2_000, 160)])
    }

    func testABufferThatCrossesThePauseWritesOnlyTheFramesBeforeIt() throws {
        let url = try makeTemporaryDirectory().appendingPathComponent("track.caf")
        let writer = try AudioTrackWriter(url: url)
        var clock = RecordingClock(origin: HostTime(seconds: 0))
        clock.pause(at: HostTime(seconds: 0.005))
        let ramp = (0..<160).map { Int16($0) }

        let written = try writer.append(buffer(ramp, at: 0), clock: clock)
        writer.close()

        XCTAssertEqual(written.map(\.buffer.frameLength), [80])
        XCTAssertEqual(try samples(in: url), Array(ramp[..<80]))
    }

    func testABufferInsideThePauseWritesNothingAndReturnsNoAudio() throws {
        let url = try makeTemporaryDirectory().appendingPathComponent("track.caf")
        let writer = try AudioTrackWriter(url: url)
        var clock = RecordingClock(origin: HostTime(seconds: 0))
        _ = try writer.append(buffer(Array(repeating: 1_000, count: 160), at: 0), clock: clock)
        clock.pause(at: HostTime(seconds: 0.01))

        let written = try writer.append(buffer(Array(repeating: .min, count: 160), at: 0.02), clock: clock)
        writer.close()

        XCTAssertTrue(written.isEmpty)
        XCTAssertEqual(try runLengths(in: url), [SampleRun(1_000, 160)])
    }

    func testTheFirstAudioAfterAResumeStartsAtThePausePlusTheResumeGap() throws {
        let url = try makeTemporaryDirectory().appendingPathComponent("track.caf")
        let writer = try AudioTrackWriter(url: url)
        var clock = RecordingClock(origin: HostTime(seconds: 0))
        _ = try writer.append(buffer(Array(repeating: 1_000, count: 160), at: 0), clock: clock)
        clock.pause(at: HostTime(seconds: 0.01))
        clock.resume(at: HostTime(seconds: 5))

        let written = try writer.append(buffer(Array(repeating: 2_000, count: 160), at: 5), clock: clock)
        writer.close()

        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(try XCTUnwrap(written.first).filePosition, 3.01, accuracy: 0.5 / 16_000)
    }

    func testTheDrainAtThePauseKeepsPrePauseSamplesOutOfTheAudioAfterTheGap() throws {
        let url = try makeTemporaryDirectory().appendingPathComponent("track.caf")
        let writer = try AudioTrackWriter(url: url)
        var clock = RecordingClock(origin: HostTime(seconds: 0))
        let rate = 48_000.0
        let pauseFrame = 48_480, resumeFrame = 96_240
        let signal: [Int16] = (0..<144_000).map { frame in
            frame < pauseFrame ? -8_192 : frame < resumeFrame ? .min : 8_192
        }

        for start in stride(from: 0, to: signal.count, by: 960) {
            if start == 48_000 { clock.pause(at: HostTime(seconds: Double(pauseFrame) / rate)) }
            if start == 96_000 { clock.resume(at: HostTime(seconds: Double(resumeFrame) / rate)) }
            _ = try writer.append(buffer(Array(signal[start..<start + 960]), at: Double(start) / rate,
                                         sampleRate: rate), clock: clock)
        }
        writer.close()

        let samples = try samples(in: url)
        let runZero = try converted(Array(signal[..<pauseFrame]), sampleRate: rate)
        let gapEnd = 64_160 // 1.01 s of run 0, then the 3 s gap, at 16 kHz
        XCTAssertNil(firstDifference(Array(samples.prefix(runZero.count)), runZero), "run 0 before the gap")
        XCTAssertEqual(Set(samples[runZero.count..<gapEnd]), [0], "the gap")
        XCTAssertGreaterThan(samples.count, gapEnd)
        XCTAssertEqual(samples[gapEnd...].indices.filter { samples[$0] < 0 }, [], "pre-pause frames after the gap")
    }

    func testStopWhilePausedKeepsEveryFrameBeforeThePause() throws {
        let url = try makeTemporaryDirectory().appendingPathComponent("track.caf")
        let writer = try AudioTrackWriter(url: url)
        var clock = RecordingClock(origin: HostTime(seconds: 0))
        let rate = 48_000.0
        let pauseFrame = 48_480
        let signal: [Int16] = (0..<72_000).map { $0 < pauseFrame ? -8_192 : .min }

        for start in stride(from: 0, to: signal.count, by: 960) {
            if start == 48_000 { clock.pause(at: HostTime(seconds: Double(pauseFrame) / rate)) }
            _ = try writer.append(buffer(Array(signal[start..<start + 960]), at: Double(start) / rate,
                                         sampleRate: rate), clock: clock)
        }
        writer.close()

        let runZero = try converted(Array(signal[..<pauseFrame]), sampleRate: rate)
        XCTAssertNil(firstDifference(try samples(in: url), runZero))
    }

    /// Never started: tests call the recording's sample callback on its queue themselves.
    private lazy var stream = SCStream(filter: SCContentFilter(), configuration: SCStreamConfiguration(), delegate: nil)

    @MainActor
    private func makeRecording(into meeting: MeetingFolder, clock: RecordingClock) throws -> ScreenCaptureRecording {
        try ScreenCaptureRecording(meeting: meeting, clock: clock) { reason in
            XCTFail("Synthetic audio interrupted the recording: \(reason)")
        }
    }

    /// The whole input through a new converter, ended with `.endOfStream`.
    private func converted(_ samples: [Int16], sampleRate: Double) throws -> [Int16] {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate,
                                                 channels: 1, interleaved: true))
        let converter = try XCTUnwrap(AVAudioConverter(from: format, to: AudioTrackWriter.fileFormat))
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { input.int16ChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: AudioTrackWriter.fileFormat,
                                                    frameCapacity: AVAudioFrameCount(samples.count)))
        var given = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if given {
                inputStatus.pointee = .endOfStream
                return nil
            }
            given = true
            inputStatus.pointee = .haveData
            return input
        }
        XCTAssertNotEqual(status, .error, "\(String(describing: error))")
        return Array(UnsafeBufferPointer(start: output.int16ChannelData![0], count: Int(output.frameLength)))
    }

    private func firstDifference(_ actual: [Int16], _ expected: [Int16]) -> String? {
        guard actual != expected else { return nil }
        let index = zip(actual, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset
            ?? min(actual.count, expected.count)
        return "frame \(index) of \(expected.count): \(actual.count > index ? "\(actual[index])" : "none")"
            + " instead of \(expected.count > index ? "\(expected[index])" : "none")"
    }

    private struct SampleRun: Equatable, CustomStringConvertible {
        let value: Int16
        let count: Int
        init(_ value: Int16, _ count: Int) { self.value = value; self.count = count }
        var description: String { "\(value) × \(count)" }
    }

    private func runLengths(in url: URL) throws -> [SampleRun] {
        try samples(in: url).reduce(into: []) { runs, sample in
            if let last = runs.last, last.value == sample {
                runs[runs.count - 1] = SampleRun(sample, last.count + 1)
            } else {
                runs.append(SampleRun(sample, 1))
            }
        }
    }

    private func frameCount(in url: URL) throws -> AVAudioFramePosition {
        try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true).length
    }

    /// Reads in a loop: one `read(into:)` of a 48 320-frame file returned only 47 104 frames.
    private func samples(in url: URL) throws -> [Int16] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
        XCTAssertEqual(file.processingFormat.sampleRate, 16_000)
        let chunk = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_000))
        var samples: [Int16] = []
        while file.framePosition < file.length {
            try file.read(into: chunk)
            guard chunk.frameLength > 0 else { break }
            samples += UnsafeBufferPointer(start: try XCTUnwrap(chunk.int16ChannelData)[0], count: Int(chunk.frameLength))
        }
        XCTAssertEqual(samples.count, Int(file.length), "frames read")
        return samples
    }

    private func buffer(_ samples: [Int16], at seconds: Double, sampleRate: Double = 16_000) throws -> CMSampleBuffer {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate,
                                                 channels: 1, interleaved: true))
        var description: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
            asbd: format.streamDescription, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description), noErr)
        var block: CMBlockBuffer?
        let byteCount = samples.count * MemoryLayout<Int16>.size
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: byteCount, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: byteCount, flags: 0, blockBufferOut: &block), kCMBlockBufferNoErr)
        let data = try XCTUnwrap(block)
        try samples.withUnsafeBytes {
            XCTAssertEqual(CMBlockBufferReplaceDataBytes(with: try XCTUnwrap($0.baseAddress),
                blockBuffer: data, offsetIntoDestination: 0, dataLength: byteCount), kCMBlockBufferNoErr)
        }
        let timescale = CMTimeScale(sampleRate)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: timescale),
            presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: timescale), decodeTimeStamp: .invalid)
        var result: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: data,
            formatDescription: try XCTUnwrap(description), sampleCount: samples.count, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &result), noErr)
        return try XCTUnwrap(result)
    }
}
