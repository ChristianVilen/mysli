import AVFAudio
import WhisperKit
import Speech
import XCTest
@testable import Mysli

final class WhisperKitTranscriberTests: XCTestCase {
    private let english = Locale(identifier: "en-US")
    private var root: URL!
    private var client: FakeWhisperKitClient!
    private var sut: WhisperKitTranscriber!
    private var downloadsReported = 0

    override func setUp() async throws {
        root = try makeTemporaryDirectory().appendingPathComponent("whisper-models", isDirectory: true)
        client = FakeWhisperKitClient()
        sut = WhisperKitTranscriber(client: client, modelsFolder: root)
        downloadsReported = 0
    }

    private func download() async throws {
        try await sut.download(for: english, onStart: { self.downloadsReported += 1 })
    }

    private func errorMessage(_ work: () async throws -> Void) async -> String? {
        do {
            try await work()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func makeAudioFile(named name: String, seconds: Int, sample: Int16 = 0) throws -> URL {
        let url = try makeTemporaryDirectory().appendingPathComponent(name)
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: false)
        let frames = AVAudioFrameCount(16_000 * seconds)
        if frames > 0 {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
            buffer.frameLength = frames
            let samples = try XCTUnwrap(buffer.int16ChannelData?[0])
            samples.initialize(repeating: sample, count: Int(frames))
            try file.write(from: buffer)
        }
        return url
    }

    func testLanguageCodeIsWhispersSpellingOfTheLanguagePart() {
        let rows: [(tag: String, code: String?)] = [
            ("en-US", "en"), ("en-GB", "en"), ("fi-FI", "fi"), ("de-DE", "de"), ("nb-NO", "no"),
            ("jv-ID", "jw"), ("fil-PH", "tl"), ("yue-HK", "yue"), ("zh-Hans-CN", "zh"), ("eo", nil),
        ]
        for row in rows {
            XCTAssertEqual(WhisperKitTranscriber.languageCode(for: Locale(identifier: row.tag)), row.code, row.tag)
        }
    }

    func testThankYouCountsAsSilenceFromEightSecondsOn() {
        let transcript = WhisperKitTranscriber.trackTranscript([
            TranscriptionSegment(start: 60, end: 61.5, text: " my weekend was pretty good"),
            TranscriptionSegment(start: 70, end: 78, text: " Thank you!"),
            TranscriptionSegment(start: 80, end: 87.75, text: " THANK YOU"),
            TranscriptionSegment(start: 90, end: 100, text: " Thank you so much."),
            TranscriptionSegment(start: 100, end: 101.25, text: " 42"),
            TranscriptionSegment(start: 110, end: 111, text: " ..."),
        ], duration: 120.25)

        XCTAssertEqual(transcript, TrackTranscript(segments: [
            TranscriptSegment(start: 60, end: 61.5, text: " my weekend was pretty good"),
            TranscriptSegment(start: 80, end: 87.75, text: " THANK YOU"),
            TranscriptSegment(start: 90, end: 100, text: " Thank you so much."),
            TranscriptSegment(start: 100, end: 101.25, text: " 42"),
        ], duration: 120.25))
    }

    func testTheDecodingOptionsHaveNoPromptAndNoFirstTokenThreshold() {
        let options = WhisperKitLibrary.decodingOptions(languageCode: "fi")

        XCTAssertEqual(options.language, "fi")
        XCTAssertNil(options.promptTokens)
        XCTAssertNil(options.firstTokenLogProbThreshold)
        XCTAssertEqual(options.chunkingStrategy, .vad)
        XCTAssertTrue(options.skipSpecialTokens)
    }

    func testADownloadGivesTheClientThePartialFolderAndReportsItsStartOnce() async throws {
        let neededBefore = try await sut.needsDownload(for: english)

        try await download()

        let neededAfter = try await sut.needsDownload(for: english)
        XCTAssertEqual([neededBefore, neededAfter], [true, false])
        XCTAssertEqual(downloadsReported, 1)
        XCTAssertEqual(client.downloads, [root.path + "/.large-v3-v20240930_turbo.partial"])
    }

    func testAnUnsupportedLanguageThrowsWhetherOrNotTheModelIsInstalled() async throws {
        let esperanto = Locale(identifier: "eo")
        let beforeInstall = await errorMessage { _ = try await sut.needsDownload(for: esperanto) }
        try await download()

        let afterInstall = await errorMessage { _ = try await sut.needsDownload(for: esperanto) }

        XCTAssertEqual([beforeInstall, afterInstall], ["Whisper does not support eo.", "Whisper does not support eo."])
    }

    func testADownloadFailsWhileAnotherMysliHoldsTheLock() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let otherMysli = try FileLock.acquire(at: root.appendingPathComponent(".lock"))

        let message = await errorMessage { try await download() }

        XCTAssertEqual(message, "Another Mysli is downloading the Whisper model.")
        XCTAssertEqual(downloadsReported, 0)
        XCTAssertEqual(client.downloads, [])
        otherMysli.release()
    }

    func testLoadingExcludesTheModelCacheFromBackupsAgain() async throws {
        try await download()
        var folder = try XCTUnwrap(root)
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        try folder.setResourceValues(values)

        _ = try await sut.load(for: english)

        XCTAssertEqual(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testTheSessionTranscribesInWhispersLanguageCode() async throws {
        try await download()
        client.segments = [TranscriptionSegment(start: 0.5, end: 1.25, text: " Hyvää huomenta"),
                           TranscriptionSegment(start: 1.5, end: 1.75, text: " .")]
        let audio = try makeAudioFile(named: "them.caf", seconds: 2)

        let session = try await sut.load(for: Locale(identifier: "fi-FI"))
        let transcript = try await session.transcribe(audio)

        XCTAssertEqual(client.loads, [root.path + "/large-v3-v20240930_turbo"])
        XCTAssertEqual(client.transcriptions, ["them.caf in fi"])
        XCTAssertEqual(transcript, TrackTranscript(segments: [TranscriptSegment(start: 0.5, end: 1.25, text: " Hyvää huomenta")],
                                                   duration: 2))
    }

    func testATranscriptionErrorNamesTheTrack() async throws {
        try await download()
        client.transcribeError = TestError(errorDescription: "Out of memory.")
        let audio = try makeAudioFile(named: "me.caf", seconds: 1)
        let session = try await sut.load(for: english)

        let message = await errorMessage { _ = try await session.transcribe(audio) }

        XCTAssertEqual(message, "Whisper could not transcribe me.caf: Out of memory.")
    }

    func testAnEmptyTrackIsNotSentToTheModel() async throws {
        try await download()
        client.segments = [TranscriptionSegment(start: 0, end: 1, text: " Hello")]
        let audio = try makeAudioFile(named: "me.caf", seconds: 0)
        let session = try await sut.load(for: english)

        let transcript = try await session.transcribe(audio)

        XCTAssertEqual(transcript, TrackTranscript(segments: [], duration: 0))
        XCTAssertEqual(client.transcriptions, [])
    }

    func testAWhisperChunkFailureFailsTheWholeTrackInsteadOfReturningPartialSpeech() async throws {
        let model = try await ChunkResultWhisperKit(WhisperKitConfig(verbose: false, load: false, download: false))
        model.failChunks = true
        let audio = try makeAudioFile(named: "them.caf", seconds: 61)
        let adapter = WhisperKitLibrary.LoadedModel(whisperKit: model)

        let message = await errorMessage { _ = try await adapter.transcribe(audio, languageCode: "en") }

        XCTAssertEqual(message, "Chunk failed.")
    }

    func testSuccessfulWhisperChunksKeepTheirAbsoluteTrackTimes() async throws {
        let model = try await ChunkResultWhisperKit(WhisperKitConfig(verbose: false, load: false, download: false))
        let audio = try makeAudioFile(named: "them.caf", seconds: 60, sample: 3_277)
        let adapter = WhisperKitLibrary.LoadedModel(whisperKit: model)

        let segments = try await adapter.transcribe(audio, languageCode: "en")

        XCTAssertEqual(segments.map(\.start), [0.5, 30.5])
        XCTAssertEqual(segments.map(\.end), [1.5, 31.5])
        XCTAssertEqual(segments.map(\.text), ["Synthetic speech", "Synthetic speech"])
    }
}

private final class ChunkResultWhisperKit: WhisperKit {
    var failChunks = false

    override func transcribeWithOptions(audioArrays: [[Float]], decodeOptionsArray: [DecodingOptions?] = [nil],
                                         seekOffsets: [Int]? = nil, callback: TranscriptionCallback? = nil)
        async -> [Result<[TranscriptionResult], Error>] {
        audioArrays.enumerated().map { index, _ in
            if failChunks && index == 1 { return .failure(MeetingStepError("Chunk failed.")) }
            return .success([TranscriptionResult(text: "Synthetic speech", segments: [
                TranscriptionSegment(start: 0.5, end: 1.5, text: "Synthetic speech")
            ], language: "en", timings: TranscriptionTimings())])
        }
    }
}

private final class FakeWhisperKitClient: WhisperKitClient {
    var transcribeError: Error?
    var segments: [TranscriptionSegment] = []
    private(set) var downloads: [String] = []
    private(set) var loads: [String] = []
    private(set) var transcriptions: [String] = []

    func download(model: String, into base: URL) async throws {
        downloads.append(base.path)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    func load(model: String, from base: URL) async throws -> any WhisperModel {
        loads.append(base.path)
        return Model(client: self)
    }

    private struct Model: WhisperModel {
        let client: FakeWhisperKitClient

        func transcribe(_ audio: URL, languageCode: String) async throws -> [TranscriptionSegment] {
            client.transcriptions.append("\(audio.lastPathComponent) in \(languageCode)")
            if let error = client.transcribeError { throw error }
            return client.segments
        }
    }
}

/// TEST_RUNNER_MYSLI_DICTATION_MEASURE=<scratch> xcodebuild -project Mysli.xcodeproj -scheme Mysli -configuration Release test -only-testing:MysliTests/RealDictationSpeechTests -parallel-testing-enabled NO ENABLE_TESTABILITY=YES
final class RealDictationSpeechTests: XCTestCase {
    func testLoadedSpeechEngines() async throws {
        guard let path = ProcessInfo.processInfo.environment["MYSLI_DICTATION_MEASURE"] else {
            throw XCTSkip("Set MYSLI_DICTATION_MEASURE to run synthetic speech measurements.")
        }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let recordsURL = root.appendingPathComponent("speech-rows.jsonl")
        try Data().write(to: recordsURL)
        let records = try FileHandle(forWritingTo: recordsURL)
        defer { try? records.close() }
        let locale = Locale(identifier: "en-US")
        guard try await !SpeechTranscriberAdapter().needsDownload(for: locale) else {
            XCTFail("Apple English speech model is not installed.")
            return
        }
        let base = URL.applicationSupportDirectory.appendingPathComponent("Mysli/whisper-models/\(WhisperKitTranscriber.model)")
        let model = try await WhisperKitLibrary().load(model: WhisperKitTranscriber.model, from: base)
        let loaded = try XCTUnwrap(model as? WhisperKitLibrary.LoadedModel)
        let scripts: [(Int, String)] = [
            (5, "Please send the draft before lunch and call me tomorrow."),
            (10, "The meeting starts at nine. Please send the draft before lunch. We can review the changes together tomorrow morning."),
            (30, "The meeting starts at nine. Please send the draft before lunch. We can review the changes together tomorrow morning. The first version needs a clear title and a short introduction. Keep the examples simple so everyone can follow the steps. After the review, send the updated document to the team. We will discuss the next steps on Friday and confirm the final schedule.")
        ]
        for (duration, source) in scripts {
            let url = root.appendingPathComponent("synthetic-\(duration).aiff")
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-v", "Samantha", "-r", "165", "-o", url.path, source]
            try say.run()
            say.waitUntilExit()
            XCTAssertEqual(say.terminationStatus, 0)
            var samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
            let spokenSeconds = Double(samples.count) / 16_000
            guard samples.count <= duration * 16_000 else {
                XCTFail("Synthetic speech exceeds \(duration) seconds: \(spokenSeconds)")
                return
            }
            samples = Array(repeating: 0, count: duration * 16_000 - samples.count) + samples
            print("DICTATION_CLIP \(duration) spoken=\(spokenSeconds) source=\(source)")
            let buffers = try stride(from: 0, to: samples.count, by: 320).map { offset in
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: AudioTrackWriter.fileFormat, frameCapacity: 320))
                buffer.frameLength = 320
                let channel = try XCTUnwrap(buffer.int16ChannelData?[0])
                for index in 0..<320 { channel[index] = Int16(max(-32767, min(32767, samples[offset + index] * 32767))) }
                return buffer
            }
            for repeatIndex in 0..<6 {
                let engines = repeatIndex.isMultiple(of: 2) ? ["whisper", "apple"] : ["apple", "whisper"]
                for engine in engines {
                    let seconds: Double
                    let text: String
                    if engine == "whisper" {
                        let start = ContinuousClock.now
                        let results = try await loaded.whisperKit.transcribe(audioArray: samples, decodeOptions: WhisperKitLibrary.decodingOptions(languageCode: "en"))
                        text = results.map(\.text).joined(separator: " ")
                        seconds = Self.seconds(ContinuousClock.now - start)
                    } else {
                        (seconds, text) = try await apple(buffers)
                    }
                    let record: [String: Any] = ["duration": duration, "engine": engine, "repeat": repeatIndex,
                                               "warmup": repeatIndex == 0, "seconds": seconds, "text": text,
                                               "wordErrors": Self.wordErrors(source, text), "sourceWords": Self.words(source).count]
                    let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                    try records.write(contentsOf: data + Data([10]))
                    print("DICTATION_ROW " + String(decoding: data, as: UTF8.self))
                    XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func apple(_ buffers: [AVAudioPCMBuffer]) async throws -> (Double, String) {
        let transcriber = SpeechTranscriber(locale: Locale(identifier: "en-US"), preset: .timeIndexedProgressiveTranscription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let format = AudioTrackWriter.fileFormat
        let best = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: format)
        XCTAssertEqual(best, format)
        try await analyzer.prepareToAnalyze(in: format)
        let input = DictationMeasurementInput(buffers: buffers)
        let stream = AsyncStream<AnalyzerInput>(unfolding: { await input.next() })
        let reader = Task { () throws -> String in
            var finals: [String] = []
            for try await result in transcriber.results where result.resultsFinalizationTime >= result.range.end {
                finals.append(String(result.text.characters))
            }
            return finals.joined(separator: " ")
        }
        try await analyzer.start(inputSequence: stream)
        await input.waitUntilDelivered()
        let start = ContinuousClock.now
        await input.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let text = try await reader.value
        return (Self.seconds(ContinuousClock.now - start), text)
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private static func wordErrors(_ source: String, _ text: String) -> Int {
        let expected = words(source)
        let actual = words(text)
        var previous = Array(0...actual.count)
        for (index, word) in expected.enumerated() {
            var current = [index + 1]
            for (other, candidate) in actual.enumerated() {
                current.append(min(previous[other + 1] + 1, current[other] + 1,
                                   previous[other] + (word == candidate ? 0 : 1)))
            }
            previous = current
        }
        return previous[actual.count]
    }
}

private actor DictationMeasurementInput {
    let buffers: [AVAudioPCMBuffer]
    let start = ContinuousClock.now
    var index = 0
    var delivered = false
    var waiter: CheckedContinuation<Void, Never>?
    var ending: CheckedContinuation<AnalyzerInput?, Never>?

    init(buffers: [AVAudioPCMBuffer]) { self.buffers = buffers }

    func next() async -> AnalyzerInput? {
        if index == buffers.count {
            delivered = true
            waiter?.resume()
            waiter = nil
            return await withCheckedContinuation { ending = $0 }
        }
        try? await Task.sleep(until: start + .milliseconds(index * 20), clock: .continuous)
        let result = AnalyzerInput(buffer: buffers[index], bufferStartTime: CMTime(value: Int64(index * 320), timescale: 16_000))
        index += 1
        return result
    }

    func waitUntilDelivered() async {
        if !delivered { await withCheckedContinuation { waiter = $0 } }
    }

    func finish() { ending?.resume(returning: nil); ending = nil }
}
