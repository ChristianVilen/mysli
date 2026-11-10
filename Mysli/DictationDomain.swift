import Foundation

struct PasteText: Equatable, Sendable {
    let value: String

    init?(_ text: String) {
        let value = String(text.reversed()
            .drop(while: { $0.isNewline }).reversed())
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
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

enum DictationKeyEvent { case pressed, released, cancelled }

@MainActor
protocol DictationKeyInput: AnyObject {
    func start(_ receive: @escaping @MainActor (DictationKeyEvent) -> Void) throws
    func setCancellable(_ cancellable: Bool)
    func stop()
}

@MainActor
protocol DictationCapturing: AnyObject {
    func begin(level: @escaping @MainActor (Float) -> Void) throws -> any DictationCapture
}

@MainActor
protocol DictationCapture: AnyObject {
    func seal()
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
    func release()
}

@MainActor
protocol DictationPolishing: AnyObject {
    func prepare() async
    func polish(_ request: DictationPolishRequest) async -> DictationPolishResult
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
