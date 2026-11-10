import Foundation

struct PasteText: Equatable, Sendable {
    let value: String

    init?(_ text: String) {
        let value = String(text.map { $0.isNewline ? " " : $0 })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        self.value = value
    }
}

struct DictationAudio: Sendable {
    /// Mono samples at 16 kHz. The capture adapter owns conversion.
    let samples: [Float]
    let evidence: AcousticEvidence

    struct AcousticEvidence: Sendable {
        let voicedSeconds: Double
        let peak: Float
    }
}

enum DictationSpeechResult: Sendable {
    case noSpeech
    case text(String)
}

struct DictationPolishRequest: Sendable {
    let heardText: String
    let localText: PasteText
    let correctSpellings: [String]
    let appName: String
    let precedingText: String?
}

enum DictationPolishResult: Sendable {
    case polished(PasteText)
    case unavailable
}

enum DictationKeyEvent: Equatable { case pressed, released, cancelled, unavailable }

@MainActor
protocol DictationKeyInput: AnyObject {
    func start(_ receive: @escaping @MainActor (DictationKeyEvent) -> Void) throws
    func setCancellable(_ cancellable: Bool) throws
    func stop()
}

@MainActor
protocol DictationCapturing: AnyObject {
    func begin(level: @escaping @MainActor (Float) -> Void,
               failed: @escaping @MainActor (DictationCaptureFailure) -> Void) throws -> any DictationCapture
}

enum DictationCaptureFailure: Error { case permission, device, conversion }

@MainActor
protocol DictationCapture: AnyObject {
    /// Closes sample admission synchronously, including while startup is pending.
    func seal()
    /// Discards audio and prevents pending startup from reopening admission.
    func cancel()
    func audio() async throws -> DictationAudio
}

@MainActor
protocol DictationSpeechPreparing: AnyObject {
    func prepare() async throws -> any DictationSpeechSession
}

@MainActor
protocol DictationSpeechSession: AnyObject {
    func transcribe(_ audio: DictationAudio) async throws -> DictationSpeechResult
    /// Idempotent. In-flight transcription retains its own resource until it ends.
    func release()
}

@MainActor
protocol DictationPolishing: AnyObject {
    func prepare() async
    func polish(_ request: DictationPolishRequest) async -> DictationPolishResult
    /// Invalidates pending preparation as well as the active request.
    func stop()
}

@MainActor
protocol DictationPasting: AnyObject {
    /// Returns only after clipboard cleanup, including when cancelled or failed.
    func paste(_ text: PasteText) async throws
}

struct LastDictation: Equatable {
    let heardText: String
    let selectedText: PasteText
}

enum DictationPresentation: Equatable {
    case disabled, loading, idle
    case listening(level: Float, warning: Bool)
    case transcribing, polishing, unpolished, error
}
