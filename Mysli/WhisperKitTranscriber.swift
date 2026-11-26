import AVFAudio
import WhisperKit

struct WhisperKitTranscriber: Transcribing, EarlyTranscribing {
    static let model = "large-v3-v20240930_turbo"

    var name: String { "Whisper \(Self.model)" }

    private let client: WhisperKitClient
    private let install: ModelInstall
    private let owner: ModelOwner

    var pendingLoads: Int { get async { await owner.pendingCount } }

    init(client: WhisperKitClient = WhisperKitLibrary(),
         modelsFolder: URL = URL.applicationSupportDirectory.appendingPathComponent("Mysli/whisper-models", isDirectory: true)) {
        self.client = client
        install = ModelInstall(root: modelsFolder, name: Self.model, label: "Whisper")
        owner = ModelOwner()
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
        try await session(for: locale)
    }

    @concurrent
    func loadSamples(for locale: Locale) async throws -> any SampleTranscriptionSession {
        try await session(for: locale)
    }

    @concurrent
    func loadEarly(for locale: Locale) async throws -> any EarlyTranscriptionSession {
        try await session(for: locale)
    }

    private func session(for locale: Locale) async throws -> Session {
        let languageCode = try Self.supportedLanguageCode(for: locale)
        install.excludeFromBackup()
        return Session(lease: try await owner.acquire(client: client, folder: install.folder), name: name,
                       languageCode: languageCode)
    }

    private final class Lease {
        let model: any WhisperModel
        init(_ model: any WhisperModel) { self.model = model }
    }

    private actor ModelOwner {
        private weak var loaded: Lease?
        private var loading: (id: UUID, task: Task<Lease, Error>)?
        private(set) var pendingCount = 0

        func acquire(client: any WhisperKitClient, folder: URL) async throws -> Lease {
            try Task.checkCancellation()
            if let loaded { return loaded }
            pendingCount += 1
            defer { pendingCount -= 1 }
            let pending: (id: UUID, task: Task<Lease, Error>)
            if let loading { pending = loading }
            else {
                pending = (UUID(), Task { Lease(try await client.load(model: WhisperKitTranscriber.model, from: folder)) })
                loading = pending
            }
            do {
                let lease = try await pending.task.value
                loaded = lease
                if loading?.id == pending.id { loading = nil }
                try Task.checkCancellation()
                return lease
            } catch {
                if loading?.id == pending.id { loading = nil }
                throw error
            }
        }
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
    static func trackTranscript(_ segments: [TranscriptSegment], duration: TimeInterval) -> TrackTranscript {
        TrackTranscript(segments: segments.filter { !isSilencePhrase($0) }, duration: duration)
    }

    private static func trackSegment(_ segment: TranscriptionSegment) -> TranscriptSegment {
        TranscriptSegment(start: TimeInterval(segment.start), end: TimeInterval(segment.end), text: segment.text)
    }

    private static func isSilencePhrase(_ segment: TranscriptSegment) -> Bool {
        let words = segment.text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return words.isEmpty || (words == ["thank", "you"] && segment.end - segment.start >= 8)
    }

    private struct Session: TranscriptionSession, SampleTranscriptionSession, EarlyTranscriptionSession {
        let lease: Lease
        let name: String
        let languageCode: String

        private var source: EarlyTranscriptSource { EarlyTranscriptSource(transcriber: name, language: languageCode) }

        @concurrent
        func transcribe(samples: [Float]) async throws -> String {
            try Task.checkCancellation()
            guard !samples.isEmpty else { return "" }
            let segments = try await lease.model.transcribe(samples: samples, languageCode: languageCode)
            try Task.checkCancellation()
            return segments.map(\.text).joined()
        }

        @concurrent
        func extend(_ early: EarlyTranscript?, of audio: URL) async throws -> EarlyTranscript {
            let length = try AudioTrackWriter.frameCount(at: audio)
            let (start, rest) = try await startAndRest(of: audio, length: length, after: early)
            // A chunk that ends one window before the end of the audio was placed and decoded from
            // audio that is all there, so more audio cannot change it.
            let settled = rest.prefix { $0.end <= length - Int64(lease.model.windowSamples) }
            return EarlyTranscript(source: source, covered: settled.last?.end ?? start?.covered ?? 0,
                                   segments: (start?.segments ?? [])
                                       + settled.flatMap(\.segments).map(WhisperKitTranscriber.trackSegment))
        }

        /// Without an early transcript that fits, the rest is the whole file. A whole file of one
        /// window or less then goes through the chunker too: on real speech it gave the same text
        /// and times as decoding it in one go.
        @concurrent
        func transcribe(_ audio: URL, after early: EarlyTranscript?) async throws -> TrackTranscript {
            let length = try AudioTrackWriter.frameCount(at: audio)
            guard length > 0 else { return TrackTranscript(segments: [], duration: 0) }
            let (start, rest) = try await startAndRest(of: audio, length: length, after: early)
            let name = audio.lastPathComponent
            let perSecond = EarlyTranscript.framesPerSecond
            if let start {
                Log.meeting.notice("Step time: early text covered \(start.covered / perSecond) s of \(length / perSecond) s of \(name, privacy: .public)")
            } else if early != nil {
                Log.meeting.notice("Early text of \(name, privacy: .public) does not fit this transcript, so the whole track is transcribed")
            }
            let segments = (start?.segments ?? []) + rest.flatMap(\.segments).map(WhisperKitTranscriber.trackSegment)
            return WhisperKitTranscriber.trackTranscript(segments, duration: Double(length) / Double(perSecond))
        }

        /// `early` when it fits the first `length` frames of `audio`, and the chunks after it.
        private func startAndRest(of audio: URL, length: Int64, after early: EarlyTranscript?) async throws
            -> (start: EarlyTranscript?, rest: [WhisperChunk]) {
            let start = early.flatMap { fits($0, length: length) ? $0 : nil }
            do {
                let rest = try await lease.model.transcribe(audio, frames: (start?.covered ?? 0)..<length,
                                                            languageCode: languageCode)
                try Task.checkCancellation()
                return (start, rest)
            } catch {
                if Task.isCancelled { throw error }
                throw MeetingStepError("Whisper could not transcribe \(audio.lastPathComponent): \(error.localizedDescription)")
            }
        }

        /// Only an early transcript that this session made, and that ends inside the file, can stand
        /// in for the start of it.
        private func fits(_ early: EarlyTranscript, length: Int64) -> Bool {
            early.source == source && (0...length).contains(early.covered)
        }
    }
}

protocol WhisperKitClient {
    func download(model: String, into base: URL) async throws
    func load(model: String, from base: URL) async throws -> any WhisperModel
}

protocol WhisperModel {
    /// The samples at 16 kHz that Whisper decodes in one go.
    var windowSamples: Int { get }
    /// `frames` of a 16 kHz mono file, in the chunks that Whisper decoded one by one. Chunk ends
    /// are frames of the file, and segment times are absolute in it.
    func transcribe(_ audio: URL, frames: Range<Int64>, languageCode: String) async throws -> [WhisperChunk]
    func transcribe(samples: [Float], languageCode: String) async throws -> [TranscriptionSegment]
}

/// Audio that Whisper decoded on its own, so no word crosses its end, however wrong the segment
/// times are.
struct WhisperChunk {
    /// The frame after the chunk.
    let end: Int64
    let segments: [TranscriptionSegment]
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
        let inference = WhisperInferenceQueue()

        var windowSamples: Int { whisperKit.featureExtractor.windowSamples ?? Constants.defaultWindowSamples }

        /// `VADAudioChunker` places each chunk end only from the 30 s of audio after the chunk's
        /// start. So a range that starts at a chunk end of the whole file gets the chunks of the
        /// whole file from there on, as long as their 30 s fit in the range. A range of one window
        /// or less is one chunk too, as the end of a whole file is.
        @concurrent
        func transcribe(_ audio: URL, frames: Range<Int64>, languageCode: String) async throws -> [WhisperChunk] {
            try Task.checkCancellation()
            let samples = try Self.samples(of: audio, frames: frames)
            let offset = Int(frames.lowerBound)
            return try await decodeChunks(samples, languageCode: languageCode, priority: false).map { chunk in
                WhisperChunk(end: frames.lowerBound + chunk.end, segments: chunk.segments.map {
                    TranscriptionUtilities.updateSegmentTimings(segment: $0, seekOffsetIndex: offset)
                })
            }
        }

        @concurrent
        func transcribe(samples: [Float], languageCode: String) async throws -> [TranscriptionSegment] {
            try await decode(samples, languageCode: languageCode, priority: true)
        }

        /// The samples that `AudioProcessor.loadAudioAsFloatArray` gives for a 16 kHz mono file, read
        /// by frame. Not `AudioProcessor.loadAudio(fromPath:…
        /// startTime:endTime:)`: it takes seconds and truncates seconds × 16 000, which puts some
        /// frames one short (193 of the 40 000 frames on a 0.1 s grid up to 4000 s), and a part must
        /// start at its exact frame. `AudioTrackWriter.frameCount(at:)` says why this works while
        /// the recording still writes the file.
        private static func samples(of audio: URL, frames: Range<Int64>) throws -> [Float] {
            let file = try AVAudioFile(forReading: audio, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard file.fileFormat.sampleRate == Double(WhisperKit.sampleRate), file.fileFormat.channelCount == 1,
                  frames.lowerBound >= 0, frames.upperBound <= file.length else {
                throw MeetingStepError("The audio file does not hold frames \(frames) at 16 kHz.")
            }
            let wanted = frames.count
            guard wanted > 0 else { return [] }
            let chunk = AVAudioFrameCount(WhisperKit.sampleRate * 60)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else {
                throw MeetingStepError("Mysli could not make an audio buffer.")
            }
            var samples: [Float] = []
            samples.reserveCapacity(wanted)
            file.framePosition = frames.lowerBound
            while samples.count < wanted {
                try file.read(into: buffer, frameCount: min(chunk, AVAudioFrameCount(wanted - samples.count)))
                guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { break }
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            }
            guard samples.count == wanted else {
                throw MeetingStepError("The audio file ended after \(samples.count) of \(wanted) frames.")
            }
            return samples
        }

        @concurrent
        private func decode(_ samples: [Float], languageCode: String, priority: Bool) async throws -> [TranscriptionSegment] {
            try Task.checkCancellation()
            guard !samples.isEmpty else { return [] }
            guard samples.count <= windowSamples else {
                return try await decodeChunks(samples, languageCode: languageCode, priority: priority).flatMap(\.segments)
            }
            let options = WhisperKitLibrary.decodingOptions(languageCode: languageCode)
            let results = try await inference.run(priority: priority) {
                try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
            }
            try Task.checkCancellation()
            return results.flatMap(\.segments)
        }

        /// Chunk ends are indexes of `samples`.
        @concurrent
        private func decodeChunks(_ samples: [Float], languageCode: String, priority: Bool) async throws -> [WhisperChunk] {
            try Task.checkCancellation()
            guard !samples.isEmpty else { return [] }
            let options = WhisperKitLibrary.decodingOptions(languageCode: languageCode)
            let chunker = VADAudioChunker(vad: whisperKit.voiceActivityDetector)
            let chunks = try await inference.run(priority: priority) {
                try await chunker.chunkAll(audioArray: samples, maxChunkLength: windowSamples, decodeOptions: options)
            }
            var chunkOptions = options
            chunkOptions.clipTimestamps = []
            var decoded: [WhisperChunk] = []
            // Yield between worker-sized batches so dictation cannot wait behind a whole meeting.
            for start in stride(from: 0, to: chunks.count, by: options.concurrentWorkerCount) {
                let batch = Array(chunks[start..<min(start + options.concurrentWorkerCount, chunks.count)])
                let results = try await inference.run(priority: priority) {
                    await whisperKit.transcribeWithOptions(
                        audioArrays: batch.map(\.audioSamples),
                        decodeOptionsArray: Array(repeating: chunkOptions, count: batch.count),
                        seekOffsets: batch.map(\.seekOffsetIndex))
                }
                try Task.checkCancellation()
                // WhisperKit 1.1.1's offset helper silently drops failed chunks.
                for result in results { _ = try result.get() }
                for (chunk, result) in zip(batch, results) {
                    let segments = chunker.updateSeekOffsetsForResults(chunkedResults: [result], audioChunks: [chunk])
                    decoded.append(WhisperChunk(end: Int64(chunk.seekOffsetIndex + chunk.audioSamples.count),
                                                segments: segments.flatMap(\.segments)))
                }
            }
            return decoded
        }
    }
}
