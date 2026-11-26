import AVFAudio
import XCTest
@testable import Mysli

/// Transcribes each track of real meeting audio twice with the real Whisper model: whole, as
/// without early text, and as the early worker and the processor do it. The worker's passes read
/// a copy that grows by 240 s at a time while it is open for writing, as in a recording. A
/// second case ends the copy 20 s after the early text, a rest of less than one Whisper window.
/// A third test decodes short clips in one go and through the chunker. Writes the transcripts and
/// comparisons into MYSLI_TRANSCRIPT_OUT. Skipped unless
/// MYSLI_MEETING_AUDIO names a folder with me.caf and them.caf. It only reads that folder.
/// Release gives the wall times of the app:
///
///     TEST_RUNNER_MYSLI_MEETING_AUDIO="$HOME/Meetings/<meeting folder>/audio" \
///     TEST_RUNNER_MYSLI_WHISPER_MODELS="$HOME/Library/Application Support/Mysli/whisper-models" \
///     TEST_RUNNER_MYSLI_TRANSCRIPT_OUT="$HOME/early-check" \
///     xcodebuild -project Mysli.xcodeproj -scheme Mysli -configuration Release test \
///         -only-testing:MysliTests/RealEarlyTranscriptTests ENABLE_TESTABILITY=YES
final class RealEarlyTranscriptTests: XCTestCase {
    private let growth = AVAudioFrameCount(240 * EarlyTranscript.framesPerSecond)
    private let shortRest = 20 * EarlyTranscript.framesPerSecond
    private let clock = ContinuousClock()

    private struct Folders {
        let audio: URL
        let models: URL
        let output: URL
        let copies: URL
    }

    private func folders(for locale: Locale) async throws -> Folders {
        let environment = ProcessInfo.processInfo.environment
        guard let audioPath = environment["MYSLI_MEETING_AUDIO"], !audioPath.isEmpty else {
            throw XCTSkip("Set MYSLI_MEETING_AUDIO to a folder with me.caf and them.caf.")
        }
        let modelsPath = try XCTUnwrap(environment["MYSLI_WHISPER_MODELS"], "Set MYSLI_WHISPER_MODELS to the Whisper models folder.")
        let outputPath = try XCTUnwrap(environment["MYSLI_TRANSCRIPT_OUT"], "Set MYSLI_TRANSCRIPT_OUT to the output folder.")
        let folders = Folders(audio: URL(fileURLWithPath: audioPath, isDirectory: true),
                              models: URL(fileURLWithPath: modelsPath, isDirectory: true),
                              output: URL(fileURLWithPath: outputPath, isDirectory: true),
                              copies: try makeTemporaryDirectory())
        try FileManager.default.createDirectory(at: folders.output, withIntermediateDirectories: true)
        guard try await !WhisperKitTranscriber(modelsFolder: folders.models).needsDownload(for: locale) else {
            throw XCTSkip("Install the Whisper model first. This test never downloads it.")
        }
        return folders
    }

    /// Dictation and a whole file of one window or less are decoded in one go; a range always goes
    /// through the chunker. This compares the two on clips of real speech.
    func testClipsOfOneWindowOrLessInOneGoAndThroughTheChunker() async throws {
        let locale = Settings().meetingLocale
        let folders = try await folders(for: locale)
        let language = try XCTUnwrap(WhisperKitTranscriber.languageCode(for: locale))
        let model = try await WhisperKitLibrary().load(
            model: WhisperKitTranscriber.model, from: folders.models.appendingPathComponent(WhisperKitTranscriber.model))
        let clips: [(track: MeetingTrack, start: Int64, seconds: Int64)] = [
            (.system, 900, 29), (.system, 1400, 20), (.system, 2595, 20), (.microphone, 2355, 20), (.microphone, 2840, 20),
        ]
        var report: [String] = []
        for clip in clips {
            let url = folders.copies.appendingPathComponent("clip-\(clip.start)-\(clip.track.fileName)")
            let perSecond = EarlyTranscript.framesPerSecond
            try writePart(of: folders.audio.appendingPathComponent(clip.track.fileName), into: url,
                          frames: clip.start * perSecond..<(clip.start + clip.seconds) * perSecond)
            let samples = try floatSamples(of: url)
            let oneGo = try await model.transcribe(samples: samples, languageCode: language).map {
                TranscriptSegment(start: TimeInterval($0.start), end: TimeInterval($0.end), text: $0.text)
            }
            let chunked = try await model.transcribe(url, frames: 0..<Int64(samples.count), languageCode: language)
                .flatMap(\.segments).map { TranscriptSegment(start: TimeInterval($0.start), end: TimeInterval($0.end), text: $0.text) }
            report.append("\n# \(clip.track.fileName) from \(clip.start) s, \(clip.seconds) s")
            report += compare(whole: TrackTranscript(segments: oneGo, duration: 0),
                              early: TrackTranscript(segments: chunked, duration: 0), cuts: [])
            report += ["in one go:"] + oneGo.map { "  \(line($0))" } + ["through the chunker:"] + chunked.map { "  \(line($0))" }
        }
        try (report.joined(separator: "\n") + "\n").write(to: folders.output.appendingPathComponent("clips.txt"),
                                                          atomically: true, encoding: .utf8)
    }

    func testEarlyTextAndTheRestAgainstTheWholeTrack() async throws {
        let locale = Settings().meetingLocale
        let folders = try await folders(for: locale)
        let (audio, output, copies) = (folders.audio, folders.output, folders.copies)
        let transcriber = WhisperKitTranscriber(modelsFolder: folders.models)

        var report: [String] = []
        var start = clock.now
        let session = try await transcriber.load(for: locale)
        let earlySession = try await transcriber.loadEarly(for: locale)
        report.append("load: \(seconds(since: start)) s")
        for track in [MeetingTrack.system, .microphone] {
            let original = audio.appendingPathComponent(track.fileName)
            let name = (track.fileName as NSString).deletingPathExtension
            start = clock.now
            let whole = try await session.transcribe(original)
            report.append("\n# \(track.fileName)\n\nwhole file: \(seconds(since: start)) s")

            let copy = copies.appendingPathComponent(track.fileName)
            let (early, cuts, passes) = try await record(original, into: copy, with: earlySession)
            report += passes
            start = clock.now
            let joined = try await session.transcribe(copy, after: early)
            report.append("rest \(time(early.covered))..<end after the last pass: \(seconds(since: start)) s")
            report += compare(whole: whole, early: joined, cuts: cuts)
            try lines(whole.segments).write(to: output.appendingPathComponent("whole-\(name).txt"), atomically: true, encoding: .utf8)
            try lines(joined.segments).write(to: output.appendingPathComponent("early-\(name).txt"), atomically: true, encoding: .utf8)

            let short = copies.appendingPathComponent("short-\(track.fileName)")
            let end = early.covered + shortRest
            try writePart(of: original, into: short, frames: 0..<end)
            let shortWhole = try await session.transcribe(short)
            start = clock.now
            let shortJoined = try await session.transcribe(short, after: early)
            report.append("\n## short rest \(time(early.covered))..<\(time(end)): \(seconds(since: start)) s")
            report += compare(whole: shortWhole, early: shortJoined, cuts: [early.covered])
            try lines(shortWhole.segments).write(to: output.appendingPathComponent("short-whole-\(name).txt"),
                                                 atomically: true, encoding: .utf8)
            try lines(shortJoined.segments).write(to: output.appendingPathComponent("short-early-\(name).txt"),
                                                  atomically: true, encoding: .utf8)
        }
        try (report.joined(separator: "\n") + "\n").write(to: output.appendingPathComponent("comparison.txt"),
                                                          atomically: true, encoding: .utf8)
    }

    /// Writes `source` into `copy` as the recorder does, `growth` frames at a time, with a pass after
    /// each step but the last, which is left for the rest after Stop.
    private func record(_ source: URL, into copy: URL, with session: any EarlyTranscriptionSession) async throws
        -> (early: EarlyTranscript, cuts: [Int64], passes: [String]) {
        let reader = try AVAudioFile(forReading: source, commonFormat: .pcmFormatInt16, interleaved: true)
        let writer = try AVAudioFile(forWriting: copy, settings: AudioTrackWriter.fileFormat.settings,
                                     commonFormat: .pcmFormatInt16, interleaved: true)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: growth))
        var early: EarlyTranscript?
        var cuts: [Int64] = []
        var passes: [String] = []
        while reader.framePosition < reader.length {
            try reader.read(into: buffer, frameCount: growth)
            try writer.write(from: buffer)
            guard reader.framePosition < reader.length else { break }
            let start = clock.now
            let extended = try await session.extend(early, of: copy)
            passes.append("pass to \(time(writer.length)): \(seconds(since: start)) s, covered \(time(extended.covered))")
            early = extended
            cuts.append(extended.covered)
        }
        writer.close()
        return (try XCTUnwrap(early), cuts, passes)
    }

    private func writePart(of source: URL, into copy: URL, frames: Range<Int64>) throws {
        let reader = try AVAudioFile(forReading: source, commonFormat: .pcmFormatInt16, interleaved: true)
        let writer = try AVAudioFile(forWriting: copy, settings: AudioTrackWriter.fileFormat.settings,
                                     commonFormat: .pcmFormatInt16, interleaved: true)
        let count = AVAudioFrameCount(frames.count)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: count))
        reader.framePosition = frames.lowerBound
        try reader.read(into: buffer, frameCount: count)
        try writer.write(from: buffer)
        writer.close()
    }

    private func floatSamples(of url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: try XCTUnwrap(buffer.floatChannelData?[0]), count: Int(buffer.frameLength)))
    }

    private func compare(whole: TrackTranscript, early: TrackTranscript, cuts: [Int64]) -> [String] {
        let wholeWords = whole.segments.flatMap { words($0.text) }
        let earlyWords = early.segments.flatMap { words($0.text) }
        var report = [
            "identical with times: \(lines(whole.segments) == lines(early.segments))",
            "segments: whole \(whole.segments.count), early \(early.segments.count)",
            "words: whole \(wholeWords.count), early \(earlyWords.count)",
            "word edits between the two: \(editDistance(wholeWords, earlyWords))",
        ]
        for cut in cuts {
            // Segment times are Float seconds, so a segment that starts at the cut can read a little earlier.
            let seconds = Double(cut) / Double(EarlyTranscript.framesPerSecond) - 0.01
            let window = (seconds - 30)..<(seconds + 30)
            let near = { (segments: [TranscriptSegment]) in
                segments.filter { window.contains($0.start) }.flatMap { self.words($0.text) }
            }
            report.append("\n## cut at \(time(cut)): word edits within 30 s: "
                          + "\(editDistance(near(whole.segments), near(early.segments)))")
            for (name, segments) in [("whole", whole.segments), ("early", early.segments)] {
                let before = segments.filter { $0.start < seconds }.suffix(2)
                let after = segments.filter { $0.start >= seconds }.prefix(2)
                report.append("\(name):")
                report += before.map { "  \(line($0))" } + ["  -- cut --"] + after.map { "  \(line($0))" }
            }
        }
        return report
    }

    private func lines(_ segments: [TranscriptSegment]) -> String {
        segments.map(line).joined(separator: "\n") + "\n"
    }

    private func line(_ segment: TranscriptSegment) -> String {
        String(format: "[%.2f-%.2f]", segment.start, segment.end) + segment.text
    }

    private func words(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private func editDistance(_ lhs: [String], _ rhs: [String]) -> Int {
        var previous = Array(0...rhs.count)
        for (index, word) in lhs.enumerated() {
            var current = [index + 1]
            current.reserveCapacity(rhs.count + 1)
            for (other, candidate) in rhs.enumerated() {
                current.append(min(previous[other + 1] + 1, current[other] + 1, previous[other] + (word == candidate ? 0 : 1)))
            }
            previous = current
        }
        return previous[rhs.count]
    }

    private func time(_ frames: Int64) -> String {
        String(format: "%.2f s", Double(frames) / Double(EarlyTranscript.framesPerSecond))
    }

    private func seconds(since start: ContinuousClock.Instant) -> String {
        String(format: "%.1f", (clock.now - start) / .seconds(1))
    }
}
