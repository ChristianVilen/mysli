import XCTest
@testable import KuKa

/// xcodebuild passes the KUKA_ variables to the tests only with a
/// TEST_RUNNER_ prefix, for example TEST_RUNNER_KUKA_MEETING_AUDIO.
final class RealMeetingAudioTests: XCTestCase {
    func testWhisperTranscribesRealMeetingAudio() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let audioPath = environment["KUKA_MEETING_AUDIO"], !audioPath.isEmpty else {
            throw XCTSkip("Set KUKA_MEETING_AUDIO to a folder with me.caf and them.caf.")
        }
        let modelsPath = try XCTUnwrap(environment["KUKA_WHISPER_MODELS"], "Set KUKA_WHISPER_MODELS to the Whisper models folder.")
        let outputPath = try XCTUnwrap(environment["KUKA_TRANSCRIPT_OUT"], "Set KUKA_TRANSCRIPT_OUT to the output folder.")
        let audio = URL(fileURLWithPath: audioPath, isDirectory: true)
        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        let transcriber = WhisperKitTranscriber(modelsFolder: URL(fileURLWithPath: modelsPath, isDirectory: true))
        let locale = Settings().meetingLocale
        let clock = ContinuousClock()
        var timings: [String] = []

        var start = clock.now
        if try await transcriber.needsDownload(for: locale) {
            try await transcriber.download(for: locale)
            timings.append("download: \(seconds(clock.now - start)) s")
        } else {
            timings.append("download: none, the model was installed")
        }
        start = clock.now
        let session = try await transcriber.load(for: locale)
        timings.append("load: \(seconds(clock.now - start)) s")
        var tracks: [MeetingTrack: TrackTranscript] = [:]
        for track in [MeetingTrack.system, .microphone] {
            start = clock.now
            let transcript = try await session.transcribe(audio.appendingPathComponent(track.fileName))
            let wall = clock.now - start
            tracks[track] = transcript
            timings.append("\(track.fileName): audio \(String(format: "%.1f", transcript.duration)) s, wall \(seconds(wall)) s")
        }

        let lines = Transcript.merge(tracks)
        let markdown = Transcript.markdown(lines, title: "Meeting audio in \(audio.lastPathComponent)",
                                           duration: tracks.values.map(\.duration).max() ?? 0,
                                           by: transcriber.name, after: [])
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
