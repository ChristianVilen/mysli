import XCTest
@testable import Mysli

@MainActor
final class DictationTestGate<Value> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var entered: (() -> Void)?

    func value() async -> Value {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered?()
            entered = nil
        }
    }

    func waitUntilEntered() async {
        if continuation != nil { return }
        await withCheckedContinuation { continuation in
            entered = { continuation.resume() }
        }
    }

    func resume(_ value: Value) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: value)
    }
}

@MainActor
final class DictationTestClock {
    var now: Double = 0
    var callbacks: [(deadline: Double, work: @MainActor () -> Void, cancelled: Bool)] = []

    func schedule(_ delay: Double, _ work: @escaping @MainActor () -> Void) -> () -> Void {
        let index = callbacks.count
        callbacks.append((now + delay, work, false))
        return { self.callbacks[index].cancelled = true }
    }

    func advance(to time: Double) {
        now = time
        for index in callbacks.indices where !callbacks[index].cancelled && callbacks[index].deadline <= time {
            callbacks[index].cancelled = true
            callbacks[index].work()
        }
    }
}

@MainActor
final class DictationTestKeys: DictationKeyInput {
    var receive: (@MainActor (DictationKeyEvent) -> Void)?
    var fails = false
    var cancellable = false
    var cancellationFails = false
    func start(_ receive: @escaping @MainActor (DictationKeyEvent) -> Void) throws {
        if fails { throw DictationTestError.failed }
        self.receive = receive
    }
    func setCancellable(_ cancellable: Bool) throws {
        if cancellable && cancellationFails { throw DictationTestError.failed }
        self.cancellable = cancellable
    }
    func stop() { receive = nil; cancellable = false }
}

enum DictationTestError: Error { case failed }

@MainActor
final class DictationTestCapture: DictationCapture {
    var sealed = false
    var cancelled = false
    var gate: DictationTestGate<DictationAudio>?
    func seal() { sealed = true }
    func cancel() { cancelled = true }
    func audio() async throws -> DictationAudio {
        if let gate { return await gate.value() }
        return DictationAudio(samples: [0.25], evidence: .init(voicedSeconds: 1, peak: 0.25))
    }
}

@MainActor
final class DictationTestRecorder: DictationCapturing {
    var captures: [DictationTestCapture] = []
    var next = DictationTestCapture()
    var level: (@MainActor (Float) -> Void)?
    var failed: (@MainActor (DictationCaptureFailure) -> Void)?
    func begin(level: @escaping @MainActor (Float) -> Void,
               failed: @escaping @MainActor (DictationCaptureFailure) -> Void) throws -> any DictationCapture {
        self.level = level
        self.failed = failed
        let capture = next
        captures.append(capture)
        next = DictationTestCapture()
        return capture
    }
}

@MainActor
final class DictationTestSession: DictationSpeechSession {
    var released = false
    var result = DictationSpeechResult.text("as heard")
    var gate: DictationTestGate<DictationSpeechResult>?
    var audioSamples: [Float]?
    func transcribe(_ audio: DictationAudio) async throws -> DictationSpeechResult {
        audioSamples = audio.samples
        if let gate { return await gate.value() }
        return result
    }
    func release() { released = true }
}

@MainActor
final class DictationTestSpeech: DictationSpeechPreparing {
    var session = DictationTestSession()
    var gate: DictationTestGate<any DictationSpeechSession>?
    func prepare() async throws -> any DictationSpeechSession {
        if let gate { return await gate.value() }
        return session
    }
}

@MainActor
final class DictationTestPolisher: DictationPolishing {
    var result = DictationPolishResult.polished(PasteText("polished")!)
    var requests: [DictationPolishRequest] = []
    var gate: DictationTestGate<DictationPolishResult>?
    var preparationGate: DictationTestGate<Void>?
    var stopped = false
    func prepare() async { if let preparationGate { await preparationGate.value() } }
    func polish(_ request: DictationPolishRequest) async -> DictationPolishResult {
        requests.append(request)
        if let gate { return await gate.value() }
        return result
    }
    func stop() { stopped = true }
}

@MainActor
final class DictationTestPaste: DictationPasting {
    var texts: [PasteText] = []
    var fails = false
    var gate: DictationTestGate<Void>?
    func paste(_ text: PasteText) async throws {
        texts.append(text)
        if let gate { await gate.value() }
        if fails { throw DictationTestError.failed }
    }
}

@MainActor
final class DictationFixture {
    let clock = DictationTestClock()
    let keys = DictationTestKeys()
    let recorder = DictationTestRecorder()
    let speech = DictationTestSpeech()
    let polisher = DictationTestPolisher()
    let paste = DictationTestPaste()
    var pasteOverride: (any DictationPasting)?
    var preparedHeard: [String] = []
    var textGate: DictationTestGate<Void>?
    var noContent = false
    lazy var controller = DictationController(
        keys: keys, recorder: recorder, speech: speech, polisher: polisher, paster: pasteOverride ?? paste,
        now: { self.clock.now }, schedule: clock.schedule,
        prepareText: { heard in
            self.preparedHeard.append(heard)
            if let textGate = self.textGate { await textGate.value() }
            if self.noContent { return nil }
            return DictationPolishRequest(heardText: heard, localText: PasteText("local")!,
                                         correctSpellings: ["Mysli"], appName: "Editor", precedingText: nil)
        }
    )

    func enable() async {
        let ready = DictationTestGate<Void>()
        controller.onChange = { if self.controller.presentation == .idle { ready.resume(()) } }
        controller.setEnabled(true)
        if controller.presentation != .idle { await ready.value() }
        controller.onChange = nil
    }

    func hold(_ seconds: Double = 0.3) {
        controller.receive(.pressed)
        clock.now += seconds
        controller.receive(.released)
    }

    func waitFor(_ expected: DictationPresentation) async {
        if controller.presentation == expected { return }
        await withCheckedContinuation { continuation in
            controller.onChange = {
                if self.controller.presentation == expected {
                    self.controller.onChange = nil
                    continuation.resume()
                }
            }
        }
    }

    func enableSettling() async {
        controller.setEnabled(true)
        await waitFor(.transcribing)
    }
}
