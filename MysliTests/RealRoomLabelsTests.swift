import AVFAudio
import XCTest
@testable import Mysli

/// Runs the real SpeakerKit model on a real me.caf, prints the voices it finds, and never
/// downloads. Skipped unless MYSLI_SPEAKER_MODEL names the installed folder that holds
/// `speaker_segmenter` and MYSLI_MEETING_AUDIO a folder with me.caf. xcodebuild passes the
/// MYSLI_ variables to the tests only with a TEST_RUNNER_ prefix:
///
///     TEST_RUNNER_MYSLI_SPEAKER_MODEL="$HOME/Library/Application Support/Mysli/speaker-models/speakerkit-coreml-556fc52a/models/argmaxinc/speakerkit-coreml" \
///     TEST_RUNNER_MYSLI_MEETING_AUDIO="$HOME/Meetings/<meeting folder>/audio" \
///     xcodebuild -project Mysli.xcodeproj -scheme Mysli test -only-testing:MysliTests/RealRoomLabelsTests
@MainActor
final class RealRoomLabelsTests: XCTestCase {
    private var modelPath = ""
    private var audioPath = ""

    /// Skips here, not in the test: in this test host, an async test on the main actor costs
    /// about 0.1 s even when it only skips.
    override func setUpWithError() throws {
        try super.setUpWithError()
        let environment = ProcessInfo.processInfo.environment
        guard let modelPath = environment["MYSLI_SPEAKER_MODEL"], !modelPath.isEmpty,
              let audioPath = environment["MYSLI_MEETING_AUDIO"], !audioPath.isEmpty else {
            throw XCTSkip("Set MYSLI_SPEAKER_MODEL to an installed speakerkit-coreml folder and MYSLI_MEETING_AUDIO to a folder with me.caf.")
        }
        self.modelPath = modelPath
        self.audioPath = audioPath
    }

    func testSpeakerKitTellsApartTheVoicesOnARealMicrophoneTrack() async throws {
        // The labeller loads <models folder>/<installed name>/models/argmaxinc/speakerkit-coreml,
        // so a temporary models folder links that path to the given model.
        let modelsFolder = try makeTemporaryDirectory()
        let repositories = modelsFolder.appendingPathComponent("speakerkit-coreml-556fc52a/models/argmaxinc", isDirectory: true)
        try FileManager.default.createDirectory(at: repositories, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: repositories.appendingPathComponent("speakerkit-coreml"),
                                                   withDestinationURL: URL(fileURLWithPath: modelPath, isDirectory: true))
        let microphone = URL(fileURLWithPath: audioPath, isDirectory: true).appendingPathComponent("me.caf")
        let file = try AVAudioFile(forReading: microphone)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        let client = RecordingSpeakerKitClient()
        let labeller = SpeakerKitRoomLabeller(client: client, modelsFolder: modelsFolder)
        XCTAssertFalse(labeller.needsDownload)

        let start = Date()
        let labels = await labeller.label(microphone)
        let wall = Date().timeIntervalSince(start)

        guard case .voices = labels else { return XCTFail("No room labels: \(labels)") }
        let seconds = Dictionary(client.turns.map { ($0.voice, $0.end - $0.start) }, uniquingKeysWith: +)
        print("Room voices: \(seconds.count) in \(String(format: "%.1f", duration)) s of audio, load and diarize \(String(format: "%.1f", wall)) s")
        for (voice, time) in seconds.sorted(by: { $0.key < $1.key }) {
            let turns = client.turns.filter { $0.voice == voice }
            print("Room voice \(voice): \(turns.count) turns, \(String(format: "%.1f", time)) s, first at \(String(format: "%.1f", turns.map(\.start).min() ?? 0)) s")
        }
    }
}

/// The real library, keeping the turns it returns so the test can report them.
private final class RecordingSpeakerKitClient: SpeakerKitClient {
    private let library = SpeakerKitLibrary()
    private(set) var turns: [VoiceTurn] = []

    func download(revision: String, into base: URL) async throws {
        throw MeetingStepError("This test never downloads a model.")
    }

    func load(from base: URL) async throws -> any VoiceModel {
        Model(loaded: try await library.load(from: base), client: self)
    }

    private struct Model: VoiceModel {
        let loaded: any VoiceModel
        let client: RecordingSpeakerKitClient

        func voiceTurns(in audio: URL) async throws -> [VoiceTurn] {
            client.turns = try await loaded.voiceTurns(in: audio)
            return client.turns
        }
    }
}
