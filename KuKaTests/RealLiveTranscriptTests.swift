import AVFAudio
import XCTest
import os
@testable import KuKa

/// The gated tests run Apple's speech model for `meetingLocale`, which must already be
/// installed, on real audio at real-time pace. They are skipped unless KUKA_LIVE_AUDIO names a
/// folder with me.caf and them.caf. xcodebuild passes it to the tests only with a TEST_RUNNER_
/// prefix: TEST_RUNNER_KUKA_LIVE_AUDIO.
final class RealLiveTranscriptTests: XCTestCase {
    /// About one ScreenCaptureKit buffer.
    private static let chunkDuration = Duration.milliseconds(20)

    /// Loads no model and reads no audio, so it runs in the default suite.
    func testAnUnsupportedLocaleIsUnavailableAndReadsNoAudio() async throws {
        let feeds = Dictionary(uniqueKeysWithValues: MeetingTrack.allCases.map { ($0, LiveAudioFeed()) })
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: AudioTrackWriter.fileFormat, frameCapacity: 320))
        buffer.frameLength = 320
        for feed in feeds.values { feed.offer(WrittenAudio(buffer: buffer, filePosition: 0, rms: 0)) }

        var received: [LiveUpdate] = []
        for await update in AppleLiveTranscriber().updates(locale: Locale(identifier: "fi-FI"),
                                                           audio: feeds.mapValues(\.audio)) {
            received.append(update)
        }

        XCTAssertEqual(received, [.unavailable("Live transcript is not available for Finnish (Finland) on this Mac.")])
        for feed in feeds.values {
            feed.finish()
            var unread = feed.audio.makeAsyncIterator()
            let first = await unread.next()
            XCTAssertNotNil(first, "an analyzer read the audio")
        }
    }

    func testLiveTextArrivesForBothTracks() async throws {
        let folder = try audioFolder()
        let buffers = Dictionary(uniqueKeysWithValues: try MeetingTrack.allCases.map {
            ($0, try chunks(of: folder.appendingPathComponent($0.fileName)))
        })
        let count = buffers.values.map(\.count).max() ?? 0
        let audioSeconds = seconds(Self.chunkDuration * count)
        let feeds = Dictionary(uniqueKeysWithValues: MeetingTrack.allCases.map { ($0, LiveAudioFeed()) })
        let clock = ContinuousClock()
        let start = clock.now

        // Fed as the recording feeds it: as soon as capture starts, in real time.
        let updates = AppleLiveTranscriber().updates(locale: Settings().meetingLocale, audio: feeds.mapValues(\.audio))
        let feeder = Task {
            for index in 0..<count {
                try await Task.sleep(until: start + Self.chunkDuration * index, clock: clock)
                for (track, list) in buffers where index < list.count { feeds[track]?.offer(list[index]) }
            }
            for feed in feeds.values { feed.finish() }
        }
        let reader = Task { () -> (events: [Event], timedOut: Bool) in
            var events: [Event] = []
            for await update in updates { events.append(Event(at: self.seconds(clock.now - start), update: update)) }
            return (events, Task.isCancelled)
        }
        let watchdog = Task {
            try await Task.sleep(until: start + .seconds(audioSeconds + 60), clock: clock)
            reader.cancel()
        }
        let (events, timedOut) = await reader.value
        let finishedAt = seconds(clock.now - start)
        watchdog.cancel()
        feeder.cancel()

        XCTAssertFalse(timedOut, "The updates did not finish within 60 s after the audio ended.")
        XCTAssertEqual(events.first?.update, .started)
        let results = events.compactMap { event -> (at: Double, result: LiveResult)? in
            guard case .result(let result) = event.update else { return nil }
            return (event.at, result)
        }
        XCTAssertEqual(events.count, results.count + 1, "Unexpected updates: \(events.map(\.update))")

        let script = try self.script(in: folder)
        var report = [String(format: "RealLiveTranscriptTests: %.1f s per track fed at real-time pace in 20 ms buffers.", audioSeconds)]
        let firstText = results.first { !text(of: $0.result).isEmpty }
        report.append(String(format: "Started at %.2f s. First text at %.2f s. Last update at %.1f s. Updates finished at %.1f s.",
                             events.first?.at ?? -1, firstText?.at ?? -1, events.last?.at ?? -1, finishedAt))
        for track in MeetingTrack.allCases {
            let finals = results.filter { $0.result.track == track && $0.result.isFinal }
            let volatiles = results.filter { $0.result.track == track && !$0.result.isFinal }
            XCTAssertFalse(finals.isEmpty, "No final text for \(track.fileName).")
            let text = finals.map { self.text(of: $0.result) }.joined(separator: " ")
            let lags = finals.map { $0.at - $0.result.end }.sorted()
            var line = String(format: "%@: %d volatile, %d final, final lag median %.2f s, max %.2f s",
                              track.fileName, volatiles.count, finals.count,
                              lags.isEmpty ? -1 : lags[lags.count / 2], lags.last ?? -1)
            if let script {
                let wanted = words(script.utterances.filter { $0.isOnTrack(of: track.speaker) }.map(\.text).joined(separator: " "))
                let recall = Double(wanted.intersection(words(text)).count) / Double(max(wanted.count, 1))
                XCTAssertGreaterThan(recall, 0.8, "Too few of the script's words in the final text of \(track.fileName).")
                line += String(format: ", %.0f%% of the script's words", recall * 100)
            }
            report.append(line + ".")
            report.append("\(track.fileName) final text starts: \(text.prefix(300))")
        }

        let outside = results.flatMap { item in
            item.result.phrases.filter { $0.start < item.result.start || $0.end > item.result.end }
        }
        report.append("\(results.map(\.result.phrases.count).reduce(0, +)) phrases, \(outside.count) outside their result's range.")
        let finalPhrases = { (track: MeetingTrack) in
            results.filter { $0.result.isFinal && $0.result.track == track }.flatMap(\.result.phrases)
        }
        let echoes = finalPhrases(.microphone).filter { mic in finalPhrases(.system).contains { Transcript.isEcho(mic, of: $0) } }
        report.append("\(echoes.count) microphone phrases hidden as echoes: \(echoes.map(\.text))")
        var live = LiveTranscript()
        let recording = RecordingClock(origin: HostTime(seconds: 0))
        for event in events { live.apply(event.update, now: HostTime(seconds: event.at), clock: recording) }
        let rows = live.preview(on: recording).rows
        if let script { report += turnReport(rows: rows, script: script) }
        report += rows.compactMap { row in
            guard case .speech(let speaker, let text, _) = row.content else { return nil }
            return String(format: "[%6.1f] %@: %@", row.at, speaker.label, text)
        }
        print(report.joined(separator: "\n"))
    }

    /// A turn that follows another person on the same track is where a join would hide a new
    /// speaker. It started a row when a row of its track starts with its first word, within 1 s
    /// of it. Word times can be half a second ahead of the script.
    private func turnReport(rows: [LiveRow], script: Script) -> [String] {
        let turns = script.utterances.sorted { $0.start < $1.start }
        let changes = zip(turns, turns.dropFirst()).filter { previous, turn in
            previous.track != nil && previous.track == turn.track && previous.speaker != turn.speaker
        }.map(\.1)
        let speech = rows.compactMap { row -> (at: Double, speaker: Speaker, text: String)? in
            guard case .speech(let speaker, let text, _) = row.content else { return nil }
            return (row.at, speaker, text)
        }
        let missed = changes.filter { turn in
            !speech.contains { row in
                turn.isOnTrack(of: row.speaker) && abs(row.at - turn.start) <= 1
                    && firstWord(row.text) == firstWord(turn.text)
            }
        }
        return ["\(changes.count - missed.count) of \(changes.count) turn changes within one track started a new row."]
            + missed.map { turn in
                let row = speech.last { turn.isOnTrack(of: $0.speaker) && $0.at <= turn.start + 1 }
                return String(format: "Missed at %.1f s (%@): \"%@\" is in the row at %.1f s: \"%@\"", turn.start, turn.speaker,
                              String(turn.text.prefix(40)), row?.at ?? -1, row?.text ?? "")
            }
    }

    func testTheAnalyzersStopReadingWhenTheReaderGoesAway() async throws {
        let folder = try audioFolder()
        let clock = ContinuousClock()
        let start = clock.now
        let pulls = OSAllocatedUnfairLock(initialState: [MeetingTrack: Int]())
        var audio: [MeetingTrack: AsyncStream<WrittenAudio>] = [:]
        for track in MeetingTrack.allCases {
            let list = try chunks(of: folder.appendingPathComponent(track.fileName))
            audio[track] = AsyncStream(unfolding: {
                let index = pulls.withLock { pulls in
                    defer { pulls[track, default: 0] += 1 }
                    return pulls[track, default: 0]
                }
                guard index < list.count else { return nil }
                try? await Task.sleep(until: start + Self.chunkDuration * index, clock: clock)
                return Task.isCancelled ? nil : list[index]
            })
        }
        let firstResult = expectation(description: "a result")
        firstResult.assertForOverFulfill = false

        let updates = AppleLiveTranscriber().updates(locale: Settings().meetingLocale, audio: audio)
        let reader = Task {
            for await update in updates {
                if case .result = update { firstResult.fulfill() }
            }
        }
        await fulfillment(of: [firstResult], timeout: 30)
        reader.cancel()
        await reader.value

        // The cancel reaches the analyzers through a task of its own.
        try await Task.sleep(for: .seconds(1))
        let atStop = pulls.withLock { $0.values.reduce(0, +) }
        try await Task.sleep(for: .seconds(3))
        let later = pulls.withLock { $0.values.reduce(0, +) }
        XCTAssertEqual(later, atStop, "The analyzers kept reading audio after the reader went away.")
        print(String(format: "RealLiveTranscriptTests: reader went away at %.1f s; %d buffers read in total, %d in the 3 s after.",
                     seconds(clock.now - start) - 4, later, later - atStop))
    }

    private struct Event {
        let at: Double
        let update: LiveUpdate
    }

    /// The generated test meeting has a manifest.json with its script. A recorded one has none.
    private struct Script: Decodable {
        struct Utterance: Decodable {
            /// "me" or "them", or in a meeting with several people on one track, the person.
            let speaker: String
            /// "me" or "them" when `speaker` is the person.
            let track: String?
            let start: TimeInterval
            let text: String

            func isOnTrack(of speaker: Speaker) -> Bool {
                (track ?? self.speaker) == speaker.label.lowercased()
            }
        }
        let utterances: [Utterance]
    }

    private func audioFolder() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["KUKA_LIVE_AUDIO"], !path.isEmpty else {
            throw XCTSkip("Set KUKA_LIVE_AUDIO to a folder with me.caf and them.caf.")
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func script(in folder: URL) throws -> Script? {
        let url = folder.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Script.self, from: Data(contentsOf: url))
    }

    /// The track in 20 ms buffers, each with its file position, as `AudioTrackWriter` hands them on.
    private func chunks(of url: URL) throws -> [WrittenAudio] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
        XCTAssertEqual(file.processingFormat, AudioTrackWriter.fileFormat)
        let frames = AVAudioFrameCount(file.processingFormat.sampleRate * seconds(Self.chunkDuration))
        var chunks: [WrittenAudio] = []
        while file.framePosition < file.length {
            let position = Double(file.framePosition) / file.processingFormat.sampleRate
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
            try file.read(into: buffer, frameCount: frames)
            chunks.append(WrittenAudio(buffer: buffer, filePosition: position, rms: 0))
        }
        return chunks
    }

    private func text(of result: LiveResult) -> String {
        result.phrases.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }

    private func firstWord(_ text: String) -> String? {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).first { !$0.isEmpty }
    }

    private func words(_ text: String) -> Set<String> {
        Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
    }

    private func seconds(_ duration: Duration) -> Double {
        let (whole, attoseconds) = duration.components
        return Double(whole) + Double(attoseconds) / 1e18
    }
}
