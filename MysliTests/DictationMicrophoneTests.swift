import AVFAudio
import XCTest
import os
@testable import Mysli

final class DictationMicrophoneTests: XCTestCase {
    @MainActor
    func testSealRetainsTheFinalSignalAtANonIntegralRate() async throws {
        let source = FakeDictationAudioSource()
        let queue = DispatchQueue(label: "dictation.test")
        let microphone = DictationMicrophone(authorized: { true }, makeSource: { source }, queue: queue,
                                             startMeter: { _ in {} })
        let capture = try microphone.begin(level: { _ in }, failed: { _ in XCTFail("Unexpected failure") })
        await source.started.value()
        for index in 0..<10 {
            let buffer = try Self.pcm(frames: 1_024, rate: 44_100, channels: [0])
            if index == 9 {
                for frame in 1_008..<1_024 { buffer.floatChannelData![0][frame] = 0.8 }
            }
            source.receive?(buffer)
        }
        capture.seal()
        let audio = try await capture.audio()
        XCTAssertGreaterThan(audio.samples.suffix(16).map { abs($0) }.max() ?? 0, 0.5)
        XCTAssertGreaterThan(audio.evidence.peak, 0.5)
        XCTAssertGreaterThan(audio.evidence.voicedSeconds, 0)
        let repeated = try await capture.audio()
        XCTAssertEqual(repeated.samples, audio.samples)
        XCTAssertEqual(repeated.evidence.peak, audio.evidence.peak)
    }

    func testResamplingRetainsTheFrameCountAcrossBufferBoundaries() throws {
        let accumulator = DictationPCMAccumulator()
        try accumulator.append(Self.pcm(frames: 480, rate: 48_000, channels: [0.25]))
        try accumulator.append(Self.pcm(frames: 480, rate: 48_000, channels: [0.25]))
        let audio = try accumulator.finish()
        XCTAssertEqual(audio.samples.count, 331)
        XCTAssertEqual(audio.samples[160], 0.25, accuracy: 0.001)
    }

    @MainActor
    func testMeterUsesTheMeetingScaleAndExpiresAfterHalfASecond() async throws {
        let source = FakeDictationAudioSource()
        let queue = DispatchQueue(label: "dictation.test")
        let timer = ManualAudioMeter()
        let values = DictationTestGate<Float>()
        let microphone = DictationMicrophone(authorized: { true }, makeSource: { source }, queue: queue,
                                             now: { timer.now }, startMeter: timer.start)
        let capture = try microphone.begin(level: { values.resume($0) }, failed: { _ in XCTFail("Unexpected failure") })
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
        source.receive?(try Self.pcm(frames: 320, rate: 16_000, channels: [0.01]))
        timer.tick()
        let fresh = await values.value()
        XCTAssertEqual(fresh, 1.0 / 3, accuracy: 0.001)
        timer.now = 0.5
        timer.tick()
        let stale = await values.value()
        XCTAssertEqual(stale, 0)
        capture.cancel()
    }
    func testStereo48kIsConvertedToBoundedMono16kSamples() throws {
        let accumulator = DictationPCMAccumulator(maximumSamples: 320)
        try accumulator.append(Self.pcm(frames: 1_920, rate: 48_000, channels: [0.2, 0.4]))
        let audio = try accumulator.finish()
        XCTAssertEqual(audio.samples.count, 320)
        XCTAssertEqual(audio.samples[160], 0.3, accuracy: 0.001)
        XCTAssertEqual(audio.evidence.voicedSeconds, 0.02, accuracy: 0.0001)
        XCTAssertGreaterThan(audio.evidence.peak, 0.29)
    }

    func testAcousticEvidenceUsesWindowsAndRejectsSilenceAndQuietNoise() throws {
        let silent = DictationPCMAccumulator()
        try silent.append(Self.pcm(frames: 320, rate: 16_000, channels: [0]))
        let silence = try silent.finish()
        XCTAssertEqual(silence.evidence.voicedSeconds, 0)
        XCTAssertEqual(silence.evidence.peak, 0)
        let quiet = DictationPCMAccumulator()
        try quiet.append(Self.pcm(frames: 320, rate: 16_000, channels: [0.0049]))
        XCTAssertEqual(try quiet.finish().evidence.voicedSeconds, 0)
        let speech = DictationPCMAccumulator()
        try speech.append(Self.pcm(frames: 160, rate: 16_000, channels: [0.005]))
        try speech.append(Self.pcm(frames: 160, rate: 16_000, channels: [0.005]))
        let audio = try speech.finish()
        XCTAssertEqual(audio.evidence.voicedSeconds, 0.02)
        XCTAssertEqual(audio.evidence.peak, 0.005, accuracy: 0.00001)
    }

    @MainActor
    func testSealBeforeStartupReturnsEmptyAudioWithoutOpeningTheDevice() async throws {
        let source = FakeDictationAudioSource()
        let queue = DispatchQueue(label: "dictation.test")
        queue.suspend()
        let microphone = DictationMicrophone(authorized: { true }, makeSource: { source }, queue: queue,
                                             startMeter: { _ in {} })
        let capture = try microphone.begin(level: { _ in }, failed: { _ in XCTFail("Unexpected failure") })
        capture.seal()
        queue.resume()
        let audio = try await capture.audio()
        XCTAssertEqual(audio.samples, [])
        XCTAssertEqual(source.starts, 0)
    }

    @MainActor
    func testStartupAndDeviceFailuresNotifyTheOwnerWithoutRelease() async throws {
        for failsDuringStart in [true, false] {
            let source = FakeDictationAudioSource()
            source.failsDuringStart = failsDuringStart
            let failure = DictationTestGate<DictationCaptureFailure>()
            let microphone = DictationMicrophone(authorized: { true }, makeSource: { source }, startMeter: { _ in {} })
            let capture = try microphone.begin(level: { _ in }, failed: { failure.resume($0) })
            if !failsDuringStart {
                await source.started.value()
                source.failed?()
            }
            let error = await failure.value()
            guard case .device = error else { XCTFail("Wrong failure"); return }
            do { _ = try await capture.audio(); XCTFail("Failed capture returned audio") }
            catch DictationCaptureFailure.device {}
            XCTAssertEqual(source.starts, 1)
            XCTAssertEqual(source.stops, 1)
        }
    }

    @MainActor
    func testMissingGrantDoesNotCreateASource() throws {
        let microphone = DictationMicrophone(authorized: { false }, makeSource: {
            XCTFail("Permission check opened microphone")
            return FakeDictationAudioSource()
        })
        XCTAssertThrowsError(try microphone.begin(level: { _ in }, failed: { _ in })) { error in
            guard case DictationCaptureFailure.permission = error else { XCTFail("Wrong error"); return }
        }
    }

    @MainActor
    func testSealPreservesAcceptedBuffersAndRejectsLaterBuffers() async throws {
        let source = FakeDictationAudioSource()
        let queue = DispatchQueue(label: "dictation.test")
        let microphone = DictationMicrophone(authorized: { true }, makeSource: { source }, queue: queue,
                                             startMeter: { _ in {} })
        let capture = try microphone.begin(level: { _ in }, failed: { _ in XCTFail("Unexpected capture failure") })
        await source.started.value()
        queue.suspend()
        source.receive?(try Self.pcm(frames: 320, rate: 16_000, channels: [0.25]))
        capture.seal()
        source.receive?(try Self.pcm(frames: 320, rate: 16_000, channels: [0.5]))
        queue.resume()
        let audio = try await capture.audio()
        XCTAssertEqual(audio.samples.count, 320)
        XCTAssertEqual(audio.samples[160], 0.25, accuracy: 0.001)
        XCTAssertEqual(source.stops, 1)
        source.failed?()
        let completed = try await capture.audio()
        XCTAssertEqual(completed.samples.count, 320)
    }

    @MainActor
    func testCancellationDiscardsAcceptedAudioBeforeConversion() async throws {
        let source = FakeDictationAudioSource()
        let queue = DispatchQueue(label: "dictation.test")
        let microphone = DictationMicrophone(authorized: { true }, makeSource: { source }, queue: queue,
                                             startMeter: { _ in {} })
        let capture = try microphone.begin(level: { _ in }, failed: { _ in XCTFail("Unexpected failure") })
        await source.started.value()
        queue.suspend()
        source.receive?(try Self.pcm(frames: 320, rate: 16_000, channels: [0.25]))
        capture.cancel()
        queue.resume()
        do { _ = try await capture.audio(); XCTFail("Cancelled samples returned") } catch is CancellationError {}
        XCTAssertEqual(source.stops, 1)
    }

    @MainActor
    func testCancelBeforeStartupCannotReopenTheMicrophone() async throws {
        let source = FakeDictationAudioSource()
        let queue = DispatchQueue(label: "dictation.test")
        queue.suspend()
        let microphone = DictationMicrophone(authorized: { true }, makeSource: { source }, queue: queue,
                                             startMeter: { _ in {} })
        let capture = try microphone.begin(level: { _ in }, failed: { _ in XCTFail("Unexpected capture failure") })
        capture.cancel()
        queue.resume()
        do { _ = try await capture.audio(); XCTFail("Cancelled audio returned") }
        catch is CancellationError {}
        XCTAssertEqual(source.starts, 0)
    }

    static func pcm(frames: Int, rate: Double, channels: [Float]) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(channels.count)))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        for (index, value) in channels.enumerated() {
            buffer.floatChannelData![index].initialize(repeating: value, count: frames)
        }
        return buffer
    }
}

private final class ManualAudioMeter: @unchecked Sendable {
    private let time = OSAllocatedUnfairLock(initialState: 0.0)
    private let callback = OSAllocatedUnfairLock<(@Sendable () -> Void)?>(initialState: nil)
    var now: Double {
        get { time.withLock { $0 } }
        set { time.withLock { $0 = newValue } }
    }
    func start(_ tick: @escaping @Sendable () -> Void) -> () -> Void {
        callback.withLock { $0 = tick }
        return { self.callback.withLock { $0 = nil } }
    }
    func tick() { callback.withLock { $0 }?() }
}

private final class FakeDictationAudioSource: DictationAudioSource, @unchecked Sendable {
    var receive: ((AVAudioPCMBuffer) -> Void)?
    let started = AudioTestSignal()
    var starts = 0
    var stops = 0
    var failsDuringStart = false
    var failed: (() -> Void)?
    func start(receive: @escaping (AVAudioPCMBuffer) -> Void, failed: @escaping () -> Void) throws {
        starts += 1
        self.receive = receive
        self.failed = failed
        if failsDuringStart { throw DictationCaptureFailure.device }
        Task { await started.send() }
    }
    func stop() { stops += 1 }
}
