import XCTest
@testable import Mysli

/// Runs the real Whisper model, and SpeakerKit when MYSLI_SPEAKER_MODELS is set, on real audio.
/// Skipped unless MYSLI_MEETING_AUDIO names a folder with me.caf and them.caf. The audio of a
/// processed meeting is in the Trash, so take it back from there first. xcodebuild passes the
/// MYSLI_ variables to the tests only with a TEST_RUNNER_ prefix:
///
///     TEST_RUNNER_MYSLI_MEETING_AUDIO="$HOME/Meetings/<meeting folder>/audio" \
///     TEST_RUNNER_MYSLI_WHISPER_MODELS="$HOME/Library/Application Support/Mysli/whisper-models" \
///     TEST_RUNNER_MYSLI_SPEAKER_MODELS="$HOME/Library/Application Support/Mysli/speaker-models" \
///     TEST_RUNNER_MYSLI_TRANSCRIPT_OUT="$HOME/whisper-check" \
///     xcodebuild -project Mysli.xcodeproj -scheme Mysli test -only-testing:MysliTests/RealMeetingAudioTests
final class RealMeetingAudioTests: XCTestCase {
    func testWhisperTranscribesRealMeetingAudio() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let audioPath = environment["MYSLI_MEETING_AUDIO"], !audioPath.isEmpty else {
            throw XCTSkip("Set MYSLI_MEETING_AUDIO to a folder with me.caf and them.caf.")
        }
        let modelsPath = try XCTUnwrap(environment["MYSLI_WHISPER_MODELS"], "Set MYSLI_WHISPER_MODELS to the Whisper models folder.")
        let outputPath = try XCTUnwrap(environment["MYSLI_TRANSCRIPT_OUT"], "Set MYSLI_TRANSCRIPT_OUT to the output folder.")
        let audio = URL(fileURLWithPath: audioPath, isDirectory: true)
        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        let transcriber = WhisperKitTranscriber(modelsFolder: URL(fileURLWithPath: modelsPath, isDirectory: true))
        let locale = Settings().meetingLocale
        let clock = ContinuousClock()
        var timings: [String] = []

        var tracks: [MeetingTrack: TrackTranscript] = [:]
        // A scope of its own, so the Whisper model is released before SpeakerKit loads, as in the app.
        do {
            var start = clock.now
            if try await transcriber.needsDownload(for: locale) {
                try await transcriber.download(for: locale) {}
                timings.append("download: \(seconds(clock.now - start)) s")
            } else {
                timings.append("download: none, the model was installed")
            }
            start = clock.now
            let session = try await transcriber.load(for: locale)
            timings.append("load: \(seconds(clock.now - start)) s")
            for track in [MeetingTrack.system, .microphone] {
                start = clock.now
                let transcript = try await session.transcribe(audio.appendingPathComponent(track.fileName))
                let wall = clock.now - start
                tracks[track] = transcript
                timings.append("\(track.fileName): audio \(String(format: "%.1f", transcript.duration)) s, wall \(seconds(wall)) s")
            }
        }

        var rooms = RoomLabels.notDiarized
        if let speakerModelsPath = environment["MYSLI_SPEAKER_MODELS"], !speakerModelsPath.isEmpty {
            let labeller = SpeakerKitRoomLabeller(modelsFolder: URL(fileURLWithPath: speakerModelsPath, isDirectory: true))
            let downloads = labeller.needsDownload
            let start = clock.now
            if downloads { try await labeller.download {} }
            rooms = await labeller.label(audio.appendingPathComponent(MeetingTrack.microphone.fileName))
            timings.append("room labels: \(seconds(clock.now - start)) s" + (downloads ? " with a download" : ""))
        }

        let lines = Transcript.merge(tracks.mapValues(\.segments), rooms: rooms)
        let markdown = Transcript.markdown(lines, title: "Meeting audio in \(audio.lastPathComponent)",
                                           duration: tracks.values.map(\.duration).max() ?? 0,
                                           by: transcriber.name, after: [], rooms: rooms, teams: .empty)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try markdown.write(to: output.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
        try (timings.joined(separator: "\n") + "\n").write(to: output.appendingPathComponent("timings.txt"),
                                                            atomically: true, encoding: .utf8)
        XCTAssertFalse(lines.isEmpty)
    }

    private func seconds(_ duration: Duration) -> String {
        let (whole, attoseconds) = duration.components
        return String(format: "%.1f", Double(whole) + Double(attoseconds) / 1e18)
    }
}
