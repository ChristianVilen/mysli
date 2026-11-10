import AVFoundation
import os

protocol DictationAudioSource: AnyObject {
    func start(receive: @escaping (AVAudioPCMBuffer) -> Void, failed: @escaping () -> Void) throws
    func stop()
}

@MainActor
final class DictationMicrophone: DictationCapturing {
    typealias StartMeter = (@escaping @Sendable () -> Void) -> () -> Void
    private let authorized: () -> Bool
    private let makeSource: () -> any DictationAudioSource
    private let queue: DispatchQueue
    private let startMeter: StartMeter
    private let now: @Sendable () -> Double

    init(authorized: @escaping () -> Bool = { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized },
         makeSource: @escaping () -> any DictationAudioSource = { EngineMicrophone() },
         queue: DispatchQueue = DispatchQueue(label: "Mysli.dictation.audio", qos: .userInitiated),
         now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime },
         startMeter: @escaping StartMeter = DictationMicrophone.startMeter) {
        self.authorized = authorized
        self.makeSource = makeSource
        self.queue = queue
        self.now = now
        self.startMeter = startMeter
    }

    func begin(level: @escaping @MainActor (Float) -> Void,
               failed: @escaping @MainActor (DictationCaptureFailure) -> Void) throws -> any DictationCapture {
        guard authorized() else { throw DictationCaptureFailure.permission }
        let storage = CaptureStorage(queue: queue, now: now, level: level, failed: failed)
        storage.start(makeSource: makeSource, startMeter: startMeter)
        return Capture(storage)
    }

    private nonisolated static func startMeter(_ tick: @escaping @Sendable () -> Void) -> () -> Void {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: 0.1)
        timer.setEventHandler(handler: tick)
        timer.resume()
        return { timer.cancel() }
    }

    private final class Capture: DictationCapture {
        private let storage: CaptureStorage
        init(_ storage: CaptureStorage) { self.storage = storage }
        func seal() { storage.seal() }
        func cancel() { storage.cancel() }
        func audio() async throws -> DictationAudio { try await storage.audio() }
        deinit { storage.cancel() }
    }
}

private final class CaptureStorage: @unchecked Sendable {
    // The callback makes this copy, then transfers its only mutable use to the audio queue.
    private struct CopiedPCM: @unchecked Sendable { let buffer: AVAudioPCMBuffer }
    private enum Admission { case open, sealed, completed, cancelled, failed(DictationCaptureFailure) }
    private struct Gate {
        var admission = Admission.open
        var seconds: Double = 0
    }
    private let gate = OSAllocatedUnfairLock(initialState: Gate())
    private let queue: DispatchQueue
    private let now: @Sendable () -> Double
    private let level: @MainActor (Float) -> Void
    private let failed: @MainActor (DictationCaptureFailure) -> Void
    // Only the audio queue owns the engine, converter, samples, and meter.
    private var source: (any DictationAudioSource)?
    private var accumulator = DictationPCMAccumulator()
    private var meter = RecordingAudioMeter()
    private var stopMeter: (() -> Void)?

    init(queue: DispatchQueue, now: @escaping @Sendable () -> Double,
         level: @escaping @MainActor (Float) -> Void,
         failed: @escaping @MainActor (DictationCaptureFailure) -> Void) {
        self.queue = queue
        self.now = now
        self.level = level
        self.failed = failed
    }

    func start(makeSource: @escaping () -> any DictationAudioSource, startMeter: @escaping DictationMicrophone.StartMeter) {
        queue.async { [self] in
            guard isOpen else { return }
            let source = makeSource()
            self.source = source
            do {
                try source.start(receive: { [weak self] in self?.receive($0) },
                                 failed: { [weak self] in self?.fail(.device) })
                guard isOpen else { stop(); return }
                stopMeter = startMeter { [weak self] in
                    guard let self else { return }
                    self.queue.async { self.publishLevel() }
                }
            } catch { fail(.device) }
        }
    }

    private var isOpen: Bool { gate.withLock { if case .open = $0.admission { true } else { false } } }

    private func receive(_ input: AVAudioPCMBuffer) {
        guard isOpen, input.format.sampleRate > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: input.frameLength) else { return }
        copy.frameLength = input.frameLength
        let from = UnsafeMutableAudioBufferListPointer(input.mutableAudioBufferList)
        let to = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in from.indices {
            guard let source = from[index].mData, let destination = to[index].mData,
                  from[index].mDataByteSize >= to[index].mDataByteSize else { fail(.conversion); return }
            memcpy(destination, source, Int(to[index].mDataByteSize))
        }
        let receivedAt = now()
        let owned = CopiedPCM(buffer: copy)
        // Enqueue under admission's lock so seal cannot overtake an accepted buffer.
        gate.withLock { state in
            guard case .open = state.admission, state.seconds < 120 else { return }
            state.seconds += Double(copy.frameLength) / copy.format.sampleRate
            queue.async { [self] in
                if case .cancelled = gate.withLock({ $0.admission }) { return }
                do {
                    let copy = owned.buffer
                    let rms = try accumulator.append(copy)
                    meter.record(rms: rms, for: .microphone, at: receivedAt)
                } catch { fail(.conversion) }
            }
        }
    }

    func seal() {
        gate.withLock { state in
            if case .open = state.admission { state.admission = .sealed }
            queue.async { self.stop() }
        }
    }

    func cancel() {
        gate.withLock { state in
            state.admission = .cancelled
            queue.async { self.stop(); self.accumulator = DictationPCMAccumulator() }
        }
    }

    private func fail(_ failure: DictationCaptureFailure) {
        let notify = gate.withLock { state in
            switch state.admission {
            case .cancelled, .failed, .completed: return false
            case .open, .sealed: state.admission = .failed(failure); return true
            }
        }
        guard notify else { return }
        queue.async { self.stop() }
        Task { @MainActor in failed(failure) }
    }

    private func stop() {
        stopMeter?()
        stopMeter = nil
        source?.stop()
        source = nil
    }

    private func publishLevel() {
        guard isOpen else { return }
        let value = Float(meter.levels(at: now()).microphone)
        Task { @MainActor in level(value) }
    }

    @concurrent
    func audio() async throws -> DictationAudio {
        let audio: DictationAudio = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    let admission = gate.withLock { state in
                        if case .sealed = state.admission { state.admission = .completed }
                        return state.admission
                    }
                    switch admission {
                    case .cancelled: continuation.resume(throwing: CancellationError())
                    case .failed(let error): continuation.resume(throwing: error)
                    case .sealed, .completed: continuation.resume(returning: accumulator.audio)
                    case .open: continuation.resume(throwing: DictationCaptureFailure.device)
                    }
                }
            }
        } onCancel: { self.cancel() }
        try Task.checkCancellation()
        return audio
    }
}

private final class EngineMicrophone: DictationAudioSource {
    private let engine = AVAudioEngine()
    private var observation: NSObjectProtocol?
    private var installed = false

    func start(receive: @escaping (AVAudioPCMBuffer) -> Void, failed: @escaping () -> Void) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw DictationCaptureFailure.device }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in receive(buffer) }
        installed = true
        try engine.start()
        observation = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                              object: engine, queue: nil) { _ in failed() }
    }

    func stop() {
        if let observation { NotificationCenter.default.removeObserver(observation) }
        observation = nil
        if installed { engine.inputNode.removeTap(onBus: 0); installed = false }
        engine.stop()
    }
}
