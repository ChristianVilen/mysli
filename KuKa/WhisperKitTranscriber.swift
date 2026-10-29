import AVFAudio
import WhisperKit

struct WhisperKitTranscriber: Transcribing {
    static let model = "large-v3-v20240930_turbo"

    var name: String { "Whisper \(Self.model)" }

    private let client: WhisperKitClient
    private let install: ModelInstall

    init(client: WhisperKitClient = WhisperKitLibrary(),
         modelsFolder: URL = URL.applicationSupportDirectory.appendingPathComponent("Ku-Ka/whisper-models", isDirectory: true)) {
        self.client = client
        install = ModelInstall(root: modelsFolder, name: Self.model, label: "Whisper")
    }

    @concurrent
    func needsDownload(for locale: Locale) async throws -> Bool {
        _ = try Self.supportedLanguageCode(for: locale)
        return !install.isInstalled
    }

    @concurrent
    func download(for locale: Locale, onStart: @MainActor () -> Void) async throws {
        try await install.install { partial in
            await onStart()
            try await client.download(model: Self.model, into: partial)
        }
    }

    @concurrent
    func load(for locale: Locale) async throws -> any TranscriptionSession {
        let languageCode = try Self.supportedLanguageCode(for: locale)
        install.excludeFromBackup()
        return Session(model: try await client.load(model: Self.model, from: install.folder), languageCode: languageCode)
    }

    private static func supportedLanguageCode(for locale: Locale) throws -> String {
        guard let code = languageCode(for: locale) else {
            throw MeetingStepError("Whisper does not support \(locale.identifier(.bcp47)).")
        }
        return code
    }

    static func languageCode(for locale: Locale) -> String? {
        guard let code = locale.language.languageCode?.identifier else { return nil }
        let whisperCode = whisperSpellings[code] ?? code
        return Constants.languages.values.contains(whisperCode) ? whisperCode : nil
    }

    private static let whisperSpellings = ["nb": "no", "jv": "jw", "fil": "tl"]

    /// Measured on a 66-minute meeting: over silence, Whisper wrote "Thank
    /// you." segments of 9 to 30 s and "." segments of about 20 s. The few
    /// short "Thank you." segments (1 to 5 s) can be real speech. The
    /// no-speech and log probabilities were the same as for real speech, so
    /// the length is the signal.
    static func trackTranscript(_ segments: [TranscriptionSegment], duration: TimeInterval) -> TrackTranscript {
        TrackTranscript(segments: segments.filter { !isSilencePhrase($0) }.map {
            TranscriptSegment(start: TimeInterval($0.start), end: TimeInterval($0.end), text: $0.text)
        }, duration: duration)
    }

    private static func isSilencePhrase(_ segment: TranscriptionSegment) -> Bool {
        let words = segment.text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return words.isEmpty || (words == ["thank", "you"] && segment.end - segment.start >= 8)
    }

    private struct Session: TranscriptionSession {
        let model: any WhisperModel
        let languageCode: String

        @concurrent
        func transcribe(_ audio: URL) async throws -> TrackTranscript {
            let file = try AVAudioFile(forReading: audio)
            guard file.length > 0 else { return TrackTranscript(segments: [], duration: 0) }
            let duration = Double(file.length) / file.processingFormat.sampleRate
            do {
                let segments = try await model.transcribe(audio, languageCode: languageCode)
                try Task.checkCancellation()
                return WhisperKitTranscriber.trackTranscript(segments, duration: duration)
            } catch {
                if Task.isCancelled { throw error }
                throw MeetingStepError("Whisper could not transcribe \(audio.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}

protocol WhisperKitClient {
    func download(model: String, into base: URL) async throws
    func load(model: String, from base: URL) async throws -> any WhisperModel
}

protocol WhisperModel {
    /// Segment times are absolute in the file.
    func transcribe(_ audio: URL, languageCode: String) async throws -> [TranscriptionSegment]
}

struct WhisperKitLibrary: WhisperKitClient {
    // Every call that can reach the hub gets an explicit base: without one,
    // WhisperKit downloads into ~/Documents/huggingface, which iCloud can sync.
    @concurrent
    func download(model: String, into base: URL) async throws {
        let folder = try await WhisperKit.download(variant: "openai_whisper-\(model)", downloadBase: base)
        guard folder.standardizedFileURL.path == Self.modelFolder(model, in: base).standardizedFileURL.path else {
            throw MeetingStepError("WhisperKit saved the model in an unexpected folder: \(folder.path).")
        }
        // The tokenizer is not part of the model download. Without it, the
        // first load would fetch it from the network.
        _ = try await ModelUtilities.loadTokenizer(for: .largev3, tokenizerFolder: base)
    }

    @concurrent
    func load(model: String, from base: URL) async throws -> any WhisperModel {
        let config = WhisperKitConfig(
            downloadBase: base,
            modelFolder: Self.modelFolder(model, in: base).path,
            tokenizerFolder: base,
            computeOptions: ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine,
                                                textDecoderCompute: .cpuAndNeuralEngine),
            verbose: false,
            logLevel: .none,
            prewarm: false,
            load: true,
            download: false)
        return LoadedModel(whisperKit: try await WhisperKit(config))
    }

    private static func modelFolder(_ model: String, in base: URL) -> URL {
        base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(model)", isDirectory: true)
    }

    // The options of the measured whisperkit-cli run. No prompt: when
    // measured, the prompt's words leaked into the transcript. No first-token
    // threshold, as in the CLI: the library's default (-1.5) ends a segment on
    // a weak first token and retries it with random sampling, which dropped
    // sentences and changed the text between runs.
    static func decodingOptions(languageCode: String) -> DecodingOptions {
        DecodingOptions(language: languageCode, usePrefillPrompt: true, skipSpecialTokens: true,
                        firstTokenLogProbThreshold: nil, concurrentWorkerCount: 4, chunkingStrategy: .vad)
    }

    struct LoadedModel: WhisperModel {
        let whisperKit: WhisperKit

        @concurrent
        func transcribe(_ audio: URL, languageCode: String) async throws -> [TranscriptionSegment] {
            try Task.checkCancellation()
            let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audio.path)
            let options = WhisperKitLibrary.decodingOptions(languageCode: languageCode)
            let window = whisperKit.featureExtractor.windowSamples ?? Constants.defaultWindowSamples
            if samples.count <= window {
                let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
                try Task.checkCancellation()
                return results.flatMap(\.segments)
            }

            let chunker = VADAudioChunker(vad: whisperKit.voiceActivityDetector)
            let chunks = try await chunker.chunkAll(audioArray: samples, maxChunkLength: window, decodeOptions: options)
            var chunkOptions = options
            chunkOptions.clipTimestamps = []
            let results = await whisperKit.transcribeWithOptions(
                audioArrays: chunks.map(\.audioSamples),
                decodeOptionsArray: Array(repeating: chunkOptions, count: chunks.count),
                seekOffsets: chunks.map(\.seekOffsetIndex))
            try Task.checkCancellation()
            // WhisperKit 1.1.1's high-level VAD path drops failed chunks. Check
            // every result before its offset helper can discard any failures.
            for result in results { _ = try result.get() }
            return chunker.updateSeekOffsetsForResults(chunkedResults: results, audioChunks: chunks).flatMap(\.segments)
        }
    }
}
