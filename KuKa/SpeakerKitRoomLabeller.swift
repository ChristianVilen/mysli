import Foundation
import SpeakerKit
import WhisperKit

struct SpeakerKitRoomLabeller: RoomLabelling {
    /// Changing the `argmaxinc/speakerkit-coreml` revision installs into a new folder.
    static let revision = "556fc52a13327837688f02289457cded017802e9"

    private let client: SpeakerKitClient
    private let install: ModelInstall

    /// Unlike Whisper, which has Apple as its fallback, the labeller waits for another Ku-Ka's
    /// download: the model is small, and waiting is better than no labels.
    init(client: SpeakerKitClient = SpeakerKitLibrary(),
         modelsFolder: URL = URL.applicationSupportDirectory.appendingPathComponent("Ku-Ka/speaker-models", isDirectory: true),
         lockWait: Duration = .seconds(60)) {
        self.client = client
        install = ModelInstall(root: modelsFolder, name: "speakerkit-coreml-\(Self.revision.prefix(8))", label: "SpeakerKit",
                               lockWait: lockWait)
    }

    var needsDownload: Bool { !install.isInstalled }

    @concurrent
    func download(onStart: @MainActor () -> Void) async throws {
        try await install.install { partial in
            await onStart()
            try await client.download(revision: Self.revision, into: partial)
        }
    }

    @concurrent
    func label(_ microphone: URL) async -> RoomLabels {
        install.excludeFromBackup()
        let model: any VoiceModel
        do {
            model = try await client.load(from: install.folder)
        } catch {
            return .failed(.load(error.localizedDescription))
        }
        let turns: [VoiceTurn]
        do {
            turns = try await model.voiceTurns(in: microphone)
        } catch {
            return .failed(.diarize(error.localizedDescription))
        }
        guard let voices = RoomVoices(turns) else { return .failed(.noVoices) }
        return .voices(voices)
    }
}

protocol SpeakerKitClient {
    func download(revision: String, into base: URL) async throws
    func load(from base: URL) async throws -> any VoiceModel
}

protocol VoiceModel {
    /// Turn times are absolute in the file.
    func voiceTurns(in audio: URL) async throws -> [VoiceTurn]
}

struct SpeakerKitLibrary: SpeakerKitClient {
    // SpeakerKit's own default threshold, written out because the real-room
    // check ran with it. No speaker count: an exact count of 3 made the
    // measured labels worse.
    static let diarizationOptions = PyannoteDiarizationOptions(clusterDistanceThreshold: 0.6)

    // Every call gets an explicit folder: without one, the hub downloads into
    // ~/Documents/huggingface, which iCloud can sync.
    @concurrent
    func download(revision: String, into base: URL) async throws {
        let kit = try await SpeakerKit(PyannoteConfig(downloadBase: base.path, download: true, downloadRevision: revision,
                                                      load: false, verbose: false, logLevel: .none))
        let folder = (kit.diarizer as? ModelManager)?.modelPath
        guard folder?.standardizedFileURL.path == Self.modelFolder(in: base).standardizedFileURL.path else {
            throw MeetingStepError("SpeakerKit saved the model in an unexpected folder: \(folder?.path ?? "none").")
        }
    }

    /// With `modelFolder` set, SpeakerKit skips its download step entirely.
    @concurrent
    func load(from base: URL) async throws -> any VoiceModel {
        let config = PyannoteConfig(modelFolder: Self.modelFolder(in: base).path, download: false,
                                    load: true, verbose: false, logLevel: .none)
        return LoadedModel(kit: try await SpeakerKit(config))
    }

    private static func modelFolder(in base: URL) -> URL {
        base.appendingPathComponent("models/argmaxinc/speakerkit-coreml", isDirectory: true)
    }

    static func voiceTurns(from segments: [SpeakerSegment]) -> [VoiceTurn] {
        segments.compactMap { segment in
            segment.speaker.speakerId.map {
                VoiceTurn(voice: $0, start: TimeInterval(segment.startTime), end: TimeInterval(segment.endTime))
            }
        }
    }

    struct LoadedModel: VoiceModel {
        let kit: SpeakerKit

        @concurrent
        func voiceTurns(in audio: URL) async throws -> [VoiceTurn] {
            try Task.checkCancellation()
            let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audio.path)
            let result = try await kit.diarize(audioArray: samples, options: SpeakerKitLibrary.diarizationOptions)
            // SpeakerKit's unstructured Task keeps running after cancellation; drop its result.
            try Task.checkCancellation()
            return SpeakerKitLibrary.voiceTurns(from: result.segments)
        }
    }
}
