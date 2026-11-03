import AVFAudio
import SpeakerKit
import XCTest
@testable import KuKa

@MainActor
final class SpeakerKitRoomLabellerTests: XCTestCase {
    private let microphone = URL(fileURLWithPath: "/Meetings/2026-10-23_14-02/audio/me.caf")
    private var root: URL!
    private var client: FakeSpeakerKitClient!
    private var sut: SpeakerKitRoomLabeller!
    private var downloadsReported = 0

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = try makeTemporaryDirectory().appendingPathComponent("speaker-models", isDirectory: true)
        client = FakeSpeakerKitClient()
        sut = SpeakerKitRoomLabeller(client: client, modelsFolder: root)
        downloadsReported = 0
    }

    private func download() async throws {
        try await sut.download(onStart: { self.downloadsReported += 1 })
    }

    private func isExcludedFromBackup() throws -> Bool? {
        try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
    }

    func testAMissingModelIsDownloadedAtThePinnedRevision() async throws {
        XCTAssertTrue(sut.needsDownload)

        try await download()

        XCTAssertFalse(sut.needsDownload)
        XCTAssertEqual(downloadsReported, 1)
        XCTAssertEqual(client.downloads, [root.path + "/.speakerkit-coreml-556fc52a.partial"])
        XCTAssertEqual(client.revisions, ["556fc52a13327837688f02289457cded017802e9"])
    }

    func testTheVoicesComeBackAsRoomVoices() async throws {
        let turns = [VoiceTurn(voice: 3, start: 4, end: 6), VoiceTurn(voice: 0, start: 0.5, end: 3.5)]
        client.turns = turns
        try await download()

        let labels = await sut.label(microphone)

        XCTAssertEqual(labels, .voices(try XCTUnwrap(RoomVoices(turns))))
        XCTAssertEqual(client.loads, [root.path + "/speakerkit-coreml-556fc52a"])
        XCTAssertEqual(client.diarized, [microphone.path])
    }

    func testNoDownloadIsReportedWhenTheModelWasInstalledMeanwhile() async throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("speakerkit-coreml-556fc52a"),
                                                withIntermediateDirectories: true)

        try await download()

        XCTAssertEqual(downloadsReported, 0)
        XCTAssertEqual(client.downloads, [])
    }

    func testALoadErrorGivesTheReason() async throws {
        try await download()
        client.loadError = TestError(errorDescription: "Model is corrupt.")

        let labels = await sut.label(microphone)

        XCTAssertEqual(labels, .failed(.load("Model is corrupt.")))
        XCTAssertEqual(client.diarized, [])
    }

    func testADiarizationErrorGivesTheReason() async throws {
        try await download()
        client.diarizeError = TestError(errorDescription: "The audio file could not be read.")

        let labels = await sut.label(microphone)

        XCTAssertEqual(labels, .failed(.diarize("The audio file could not be read.")))
    }

    func testNoVoicesIsAFailure() async throws {
        try await download()

        let noTurns = await sut.label(microphone)
        client.turns = [VoiceTurn(voice: 0, start: 4, end: 4)]
        let onlyZeroLengthTurns = await sut.label(microphone)

        XCTAssertEqual([noTurns, onlyZeroLengthTurns], [.failed(.noVoices), .failed(.noVoices)])
    }

    func testLabellingExcludesTheModelCacheFromBackupsAgain() async throws {
        try await download()
        var folder = try XCTUnwrap(root)
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        try folder.setResourceValues(values)

        _ = await sut.label(microphone)

        XCTAssertEqual(client.downloads.count, 1)
        XCTAssertEqual(try isExcludedFromBackup(), true)
    }

    func testOnlySegmentsWithOneSpeakerBecomeVoiceTurns() {
        let turns = SpeakerKitLibrary.voiceTurns(from: [
            SpeakerSegment(speaker: .speakerId(2), startTime: 4.5, endTime: 6.25, frameRate: 100),
            SpeakerSegment(speaker: .noMatch, startTime: 6.25, endTime: 7, frameRate: 100),
            SpeakerSegment(speaker: .multiple([0, 2]), startTime: 7, endTime: 8, frameRate: 100),
            SpeakerSegment(speaker: .speakerId(0), startTime: 0.5, endTime: 4.5, frameRate: 100),
        ])

        XCTAssertEqual(turns, [VoiceTurn(voice: 2, start: 4.5, end: 6.25), VoiceTurn(voice: 0, start: 0.5, end: 4.5)])
    }

    func testTheLoadedModelDiarizesTheWholeFileWithThresholdPointSixAndNoSpeakerCount() async throws {
        let kit = try await CannedSpeakerKit()
        kit.segments = [SpeakerSegment(speaker: .speakerId(1), startTime: 0.5, endTime: 1.5, frameRate: 100)]
        let audio = try makeAudioFile(seconds: 2)

        let turns = try await SpeakerKitLibrary.LoadedModel(kit: kit).voiceTurns(in: audio)

        XCTAssertEqual(turns, [VoiceTurn(voice: 1, start: 0.5, end: 1.5)])
        XCTAssertEqual(kit.calls.map(\.samples), [32_000])
        XCTAssertEqual(kit.calls.map(\.threshold), [0.6])
        XCTAssertEqual(kit.calls.map(\.speakers), [nil])
    }

    func testACancelDuringDiarizationDropsItsResult() async throws {
        let kit = try await CannedSpeakerKit()
        kit.segments = [SpeakerSegment(speaker: .speakerId(1), startTime: 0.5, endTime: 1.5, frameRate: 100)]
        kit.cancelsItsTask = true
        let audio = try makeAudioFile(seconds: 2)
        let model = SpeakerKitLibrary.LoadedModel(kit: kit)

        let result = await Task { try await model.voiceTurns(in: audio) }.result

        XCTAssertThrowsError(try result.get()) { XCTAssertTrue($0 is CancellationError, "\($0)") }
        XCTAssertEqual(kit.calls.count, 1)
    }

    private func makeAudioFile(seconds: Int) throws -> URL {
        let url = try makeTemporaryDirectory().appendingPathComponent("me.caf")
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: false)
        let frames = AVAudioFrameCount(16_000 * seconds)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        try XCTUnwrap(buffer.int16ChannelData?[0]).initialize(repeating: 0, count: Int(frames))
        try file.write(from: buffer)
        return url
    }
}

/// Answers `diarize` with canned segments, so the adapter runs without a model.
private final class CannedSpeakerKit: SpeakerKit, @unchecked Sendable {
    var segments: [SpeakerSegment] = []
    var cancelsItsTask = false
    private(set) var calls: [(samples: Int, threshold: Float?, speakers: Int?)] = []

    init() async throws {
        try await super.init(PyannoteConfig(modelDownloadConfig: nil, download: false, load: false, verbose: false))
    }

    override func diarize(audioArray: [Float], options: (any DiarizationOptions)? = nil,
                          progressCallback: (@Sendable (Progress) -> Void)? = nil) async throws -> DiarizationResult {
        let options = options as? PyannoteDiarizationOptions
        calls.append((audioArray.count, options?.clusterDistanceThreshold, options?.numberOfSpeakers))
        if cancelsItsTask { withUnsafeCurrentTask { $0?.cancel() } }
        return DiarizationResult(speakerCount: 2, totalFrames: 200, frameRate: 100, segments: segments)
    }
}

private final class FakeSpeakerKitClient: SpeakerKitClient {
    var loadError: Error?
    var diarizeError: Error?
    var turns: [VoiceTurn] = []
    private(set) var downloads: [String] = []
    private(set) var revisions: [String] = []
    private(set) var loads: [String] = []
    private(set) var diarized: [String] = []

    func download(revision: String, into base: URL) async throws {
        downloads.append(base.path)
        revisions.append(revision)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    func load(from base: URL) async throws -> any VoiceModel {
        loads.append(base.path)
        if let loadError { throw loadError }
        return Model(client: self)
    }

    private struct Model: VoiceModel {
        let client: FakeSpeakerKitClient

        func voiceTurns(in audio: URL) async throws -> [VoiceTurn] {
            client.diarized.append(audio.path)
            if let error = client.diarizeError { throw error }
            return client.turns
        }
    }
}
