import AVFAudio
import CoreMedia
import ScreenCaptureKit
import XCTest
@testable import KuKa

final class AudioTrackWriterTests: XCTestCase {
    @MainActor
    func testRecordingPublishesIndependentTrackLevelsAndIgnoresBuffersAfterStop() throws {
        let meeting = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: Date())
        let recording = try ScreenCaptureRecording(meeting: meeting) { reason in
            XCTFail("Synthetic audio interrupted the recording: \(reason)")
        }
        defer { recording.stop() }
        let stream = SCStream(filter: SCContentFilter(), configuration: SCStreamConfiguration(), delegate: nil)
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

    func testRMSUsesWrittenSamplesWithoutCountingTimelinePadding() throws {
        let url = try makeTemporaryDirectory().appendingPathComponent("track.caf")
        let writer = try AudioTrackWriter(url: url)
        let samples: [Int16] = [16_384, -16_384, 16_384, -16_384]

        let rms = try writer.append(buffer(samples, at: 1), timelineStart: .zero)
        writer.close()

        XCTAssertEqual(try XCTUnwrap(rms), 0.5, accuracy: 0.000001)
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

        XCTAssertEqual(try XCTUnwrap(writer.append(buffer([0, 0, 0, 0], at: 0), timelineStart: .zero)), 0)
        XCTAssertEqual(try XCTUnwrap(writer.append(buffer([.min, .min, .min, .min], at: 0.00025),
                                                timelineStart: .zero)), 1)
        writer.close()
    }

    private func buffer(_ samples: [Int16], at seconds: Double) throws -> CMSampleBuffer {
        var description: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
            asbd: AudioTrackWriter.fileFormat.streamDescription, layoutSize: 0, layout: nil,
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
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 16_000),
            presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 16_000), decodeTimeStamp: .invalid)
        var result: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: data,
            formatDescription: try XCTUnwrap(description), sampleCount: samples.count, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &result), noErr)
        return try XCTUnwrap(result)
    }
}
