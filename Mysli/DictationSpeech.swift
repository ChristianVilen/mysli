import Foundation

@MainActor
final class DictationSpeech: DictationSpeechPreparing {
    private let load: () async throws -> any SampleTranscriptionSession

    init(transcriber: WhisperKitTranscriber) {
        load = {
            let locale = Locale(identifier: "en-US")
            if try await transcriber.needsDownload(for: locale) {
                try await transcriber.download(for: locale, onStart: {})
            }
            return try await transcriber.loadSamples(for: locale)
        }
    }

    init(load: @escaping () async throws -> any SampleTranscriptionSession) { self.load = load }

    func prepare() async throws -> any DictationSpeechSession {
        let session = try await load()
        try Task.checkCancellation()
        return Session(session)
    }

    private final class Session: DictationSpeechSession {
        private var retained: (any SampleTranscriptionSession)?
        init(_ session: any SampleTranscriptionSession) { retained = session }

        func transcribe(_ audio: DictationAudio) async throws -> DictationSpeechResult {
            guard let session = retained else { throw CancellationError() }
            try Task.checkCancellation()
            guard !audio.samples.isEmpty, audio.evidence.voicedSeconds >= 0.12, audio.evidence.peak >= 0.01 else {
                return .noSpeech
            }
            let text = try await session.transcribe(samples: audio.samples)
            try Task.checkCancellation()
            guard text.rangeOfCharacter(from: .alphanumerics) != nil else { return .noSpeech }
            return .text(text)
        }

        func release() { retained = nil }
    }
}
