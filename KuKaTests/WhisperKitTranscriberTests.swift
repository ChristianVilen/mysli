import AVFAudio
import WhisperKit
import XCTest
@testable import KuKa

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

    private func folderContents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
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

    func testSegmentsKeepTheirTextAndTimesAndSilencePhrasesAreDropped() {
        let transcript = WhisperKitTranscriber.trackTranscript([
            TranscriptionSegment(start: 0, end: 22.5, text: " Thank you."),
            TranscriptionSegment(start: 10, end: 11.5, text: " Thank you."),
            TranscriptionSegment(start: 30, end: 50, text: " ."),
            TranscriptionSegment(start: 60, end: 61.5, text: " my weekend was pretty good"),
        ], duration: 90.25)

        XCTAssertEqual(transcript, TrackTranscript(segments: [
            TranscriptSegment(start: 10, end: 11.5, text: " Thank you."),
            TranscriptSegment(start: 60, end: 61.5, text: " my weekend was pretty good"),
        ], duration: 90.25))
    }

    func testThankYouCountsAsSilenceFromEightSecondsOn() {
        let transcript = WhisperKitTranscriber.trackTranscript([
            TranscriptionSegment(start: 70, end: 78, text: " Thank you!"),
            TranscriptionSegment(start: 80, end: 87.75, text: " THANK YOU"),
            TranscriptionSegment(start: 90, end: 100, text: " Thank you so much."),
            TranscriptionSegment(start: 100, end: 101.25, text: " 42"),
            TranscriptionSegment(start: 110, end: 111, text: " ..."),
        ], duration: 120)

        XCTAssertEqual(transcript.segments.map(\.text), [" THANK YOU", " Thank you so much.", " 42"])
    }

    func testTheDecodingOptionsHaveNoPromptAndNoFirstTokenThreshold() {
        let options = WhisperKitLibrary.decodingOptions(languageCode: "fi")

        XCTAssertEqual(options.language, "fi")
        XCTAssertNil(options.promptTokens)
        XCTAssertNil(options.firstTokenLogProbThreshold)
        XCTAssertEqual(options.chunkingStrategy, .vad)
        XCTAssertTrue(options.skipSpecialTokens)
    }

    func testADownloadInstallsTheModelOnlyWhenItIsComplete() async throws {
        let neededBefore = try await sut.needsDownload(for: english)

        try await download()

        let neededAfter = try await sut.needsDownload(for: english)
        XCTAssertEqual([neededBefore, neededAfter], [true, false])
        XCTAssertEqual(downloadsReported, 1)
        XCTAssertEqual(client.downloads, [root.path + "/.large-v3-v20240930_turbo.partial"])
        XCTAssertEqual(try folderContents(), [".lock", "large-v3-v20240930_turbo"])
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("large-v3-v20240930_turbo/model.bin"), encoding: .utf8),
                       "weights")
    }

    func testAFailedDownloadKeepsThePartialFolderAndTheNextDownloadResumesThere() async throws {
        client.downloadError = TestError(errorDescription: "The network connection was lost.")

        let message = await errorMessage { try await download() }

        XCTAssertEqual(message, "The network connection was lost.")
        XCTAssertEqual(try folderContents(), [".large-v3-v20240930_turbo.partial", ".lock"])
        let stillNeeded = try await sut.needsDownload(for: english)
        XCTAssertTrue(stillNeeded)

        client.downloadError = nil
        try await download()

        XCTAssertEqual(client.downloads, [root.path + "/.large-v3-v20240930_turbo.partial",
                                          root.path + "/.large-v3-v20240930_turbo.partial"])
        XCTAssertEqual(try folderContents(), [".lock", "large-v3-v20240930_turbo"])
    }

    func testAnUnsupportedLanguageThrowsWhetherOrNotTheModelIsInstalled() async throws {
        let esperanto = Locale(identifier: "eo")
        let beforeInstall = await errorMessage { _ = try await sut.needsDownload(for: esperanto) }
        try await download()

        let afterInstall = await errorMessage { _ = try await sut.needsDownload(for: esperanto) }

        XCTAssertEqual([beforeInstall, afterInstall], ["Whisper does not support eo.", "Whisper does not support eo."])
    }

    func testADownloadFailsWhileAnotherKuKaHoldsTheLock() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let otherKuKa = try FileLock.acquire(at: root.appendingPathComponent(".lock"))

        let message = await errorMessage { try await download() }

        XCTAssertEqual(message, "Another Ku-Ka is downloading the Whisper model.")
        XCTAssertEqual(downloadsReported, 0)
        XCTAssertEqual(client.downloads, [])
        otherKuKa.release()
    }

    func testTheModelCacheIsExcludedFromBackupsWhenDownloadedOrLoaded() async throws {
        try await download()
        XCTAssertEqual(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)

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
    var downloadError: Error?
    var transcribeError: Error?
    var segments: [TranscriptionSegment] = []
    private(set) var downloads: [String] = []
    private(set) var loads: [String] = []
    private(set) var transcriptions: [String] = []

    func download(model: String, into base: URL) async throws {
        downloads.append(base.path)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data("weights".utf8).write(to: base.appendingPathComponent("model.bin"))
        if let downloadError { throw downloadError }
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
