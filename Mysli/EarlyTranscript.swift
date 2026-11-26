import Foundation

/// The transcriber and language that made an early transcript.
struct EarlyTranscriptSource: Equatable, Sendable {
    /// With the model, for example "Whisper large-v3-v20240930_turbo".
    let transcriber: String
    /// Whisper's language code.
    let language: String
}

/// Whisper's text of the start of one track, made while the meeting records, so that after Stop
/// only the rest of the track is left to transcribe. Positions are frames of the track file.
struct EarlyTranscript: Equatable {
    static let framesPerSecond = Int64(AudioTrackWriter.fileFormat.sampleRate)

    let source: EarlyTranscriptSource
    /// Every segment comes from the audio before this frame, and the rest of the track starts at it.
    let covered: Int64
    /// Before the silence filter, with times in seconds from the start of the file.
    let segments: [TranscriptSegment]
}

extension EarlyTranscript {
    private struct File: Codable {
        struct Segment: Codable {
            let start: Double
            let end: Double
            let text: String
        }

        let version: Int
        let transcriber: String
        let language: String
        let coveredFrames: Int64
        let segments: [Segment]
    }

    private static let version = 1

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(File(
            version: Self.version, transcriber: source.transcriber, language: source.language, coveredFrames: covered,
            segments: segments.map { File.Segment(start: $0.start, end: $0.end, text: $0.text) }))
    }

    /// Nil for a file of another version or one that does not decode.
    init?(json: Data) {
        guard let file = try? JSONDecoder().decode(File.self, from: json), file.version == Self.version else { return nil }
        self.init(source: EarlyTranscriptSource(transcriber: file.transcriber, language: file.language),
                  covered: file.coveredFrames,
                  segments: file.segments.map { TranscriptSegment(start: $0.start, end: $0.end, text: $0.text) })
    }
}

extension MeetingFolder {
    /// Hidden, beside `transcript.md`. `stage()` never reads it.
    func earlyTranscriptURL(_ track: MeetingTrack) -> URL {
        let name = (track.fileName as NSString).deletingPathExtension
        return url.appendingPathComponent(".early-transcript-\(name).json")
    }

    /// Nil when the file is missing or does not decode.
    func earlyTranscript(_ track: MeetingTrack) -> EarlyTranscript? {
        guard let data = try? Data(contentsOf: earlyTranscriptURL(track)) else { return nil }
        return EarlyTranscript(json: data)
    }

    /// Atomic: the processor trusts every early transcript that decodes.
    func saveEarlyTranscript(_ early: EarlyTranscript, for track: MeetingTrack) throws {
        try early.encoded().write(to: earlyTranscriptURL(track), options: .atomic)
    }

    func removeEarlyTranscripts() throws {
        for track in MeetingTrack.allCases {
            do {
                try FileManager.default.removeItem(at: earlyTranscriptURL(track))
            } catch CocoaError.fileNoSuchFile {
                continue
            }
        }
    }
}
