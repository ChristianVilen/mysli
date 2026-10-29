import AVFAudio
import CoreMedia
import Speech

protocol LiveTranscribing {
    /// Starts live transcription of `audio` and returns its updates at once. When the reader of
    /// the returned stream goes away, the engine stops. Never downloads a model.
    func updates(locale: Locale, audio: [MeetingTrack: AsyncStream<WrittenAudio>]) -> AsyncStream<LiveUpdate>
}

/// Apple `SpeechTranscriber` with the time-indexed progressive preset, one `SpeechAnalyzer` per
/// track. Runs only for a locale whose model is already installed, and never downloads or
/// reserves one. When the audio streams finish, the last text is finalized; when the reader goes
/// away, the analyzers are cancelled.
struct AppleLiveTranscriber: LiveTranscribing {
    func updates(locale: Locale, audio: [MeetingTrack: AsyncStream<WrittenAudio>]) -> AsyncStream<LiveUpdate> {
        // Unbounded: speech limits the rate to a few results a second, and a dropped final
        // would lose text.
        let (updates, continuation) = AsyncStream.makeStream(of: LiveUpdate.self)
        let task = Task { await Self.run(locale: locale, audio: audio, into: continuation) }
        continuation.onTermination = { _ in task.cancel() }
        return updates
    }

    @concurrent
    private static func run(locale: Locale, audio: [MeetingTrack: AsyncStream<WrittenAudio>],
                            into updates: AsyncStream<LiveUpdate>.Continuation) async {
        defer { updates.finish() }
        func unavailable(_ detail: String) {
            NSLog("Ku-Ka: no live transcript: \(detail)")
            let language = Locale(identifier: "en").localizedString(forIdentifier: locale.identifier)
                ?? locale.identifier(.bcp47)
            updates.yield(.unavailable("Live transcript is not available for \(language) on this Mac."))
        }

        do {
            if try await SpeechTranscriberAdapter().needsDownload(for: locale) {
                return unavailable("the \(locale.identifier(.bcp47)) speech model is not installed.")
            }
        } catch {
            return unavailable(error.localizedDescription)
        }
        let analyses = MeetingTrack.allCases.compactMap { track in
            audio[track].map { TrackAnalysis(track: track, audio: $0, locale: locale) }
        }
        // The analyzer does not convert audio, and this version has no converter of its own.
        let format = AudioTrackWriter.fileFormat
        let best = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: analyses.map(\.transcriber),
                                                                 considering: format)
        guard best == format else {
            return unavailable("the speech model wants \(best.map { "\($0)" } ?? "no format"), not \(format).")
        }

        do {
            try await withTaskCancellationHandler {
                try await analyze(analyses, in: format, into: updates)
            } onCancel: {
                Task { for analysis in analyses { await analysis.analyzer.cancelAndFinishNow() } }
            }
        } catch {
            if !Task.isCancelled { updates.yield(.failed(error.localizedDescription)) }
        }
    }

    /// Returns when every analyzer has finished. An error cancels all of them first, so no
    /// child task waits for audio that only ends with the recording.
    private static func analyze(_ analyses: [TrackAnalysis], in format: AVAudioFormat,
                                into updates: AsyncStream<LiveUpdate>.Continuation) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            do {
                for analysis in analyses { try await analysis.start(in: format) }
                // A cancel handler that ran before a start missed that analyzer. The catch
                // cancels them all again.
                try Task.checkCancellation()
                updates.yield(.started)
                for analysis in analyses {
                    group.addTask { try await analysis.forwardResults(into: updates) }
                    group.addTask { try await analysis.analyzer.finalizeAndFinishThroughEndOfInput() }
                }
                while try await group.next() != nil {}
            } catch {
                for analysis in analyses { await analysis.analyzer.cancelAndFinishNow() }
                throw error
            }
        }
    }
}

private struct TrackAnalysis {
    let track: MeetingTrack
    let audio: AsyncStream<WrittenAudio>
    let transcriber: SpeechTranscriber
    let analyzer: SpeechAnalyzer

    init(track: MeetingTrack, audio: AsyncStream<WrittenAudio>, locale: Locale) {
        self.track = track
        self.audio = audio
        // The time-indexed preset gives each word its audio time, so a result splits into phrases.
        transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        analyzer = SpeechAnalyzer(modules: [transcriber])
    }

    func start(in format: AVAudioFormat) async throws {
        try await analyzer.prepareToAnalyze(in: format)
        // Each buffer goes in at its file position, so the results are in file positions, and
        // the jump at a resume or a dropped buffer tells the analyzer the audio has a hole.
        try await analyzer.start(inputSequence: audio.map {
            AnalyzerInput(buffer: $0.buffer, bufferStartTime: $0.startTime)
        })
    }

    func forwardResults(into updates: AsyncStream<LiveUpdate>.Continuation) async throws {
        for try await result in transcriber.results {
            updates.yield(.result(LiveResult(track: track, range: result.range,
                                             finalizationTime: result.resultsFinalizationTime, text: result.text)))
        }
    }
}

extension WrittenAudio {
    /// The file position as a whole frame. `CMTime(seconds:preferredTimescale:)` rounds down,
    /// and gives 64_319 for 64_320 / 16_000 s.
    var startTime: CMTime {
        let sampleRate = buffer.format.sampleRate
        return CMTime(value: CMTimeValue((filePosition * sampleRate).rounded()), timescale: CMTimeScale(sampleRate))
    }
}

extension LiveResult {
    /// One analyzer result, with its times already in file positions. `isFinal` is Apple's rule:
    /// "Equivalent to resultsFinalizationTime >= range.end".
    init(track: MeetingTrack, range: CMTimeRange, finalizationTime: CMTime, text: AttributedString) {
        self.init(track: track, start: range.start.seconds, end: range.end.seconds,
                  phrases: Self.phrases(of: text, in: range),
                  isFinal: finalizationTime >= range.end, finalizedThrough: finalizationTime.seconds)
    }

    /// A pause between two words at least this long starts a new phrase.
    static let phrasePause: TimeInterval = 0.7

    /// Apple cuts a result at a pause, not at a new voice, so one result can hold the sentences
    /// of two people in one room. A phrase ends after a sentence or at a `phrasePause`, and runs
    /// from its first timed word to its last. Text without word times is one phrase over `range`.
    private static func phrases(of text: AttributedString, in range: CMTimeRange) -> [TranscriptSegment] {
        var phrases: [TranscriptSegment] = []
        var words = ""
        var times: (start: TimeInterval, end: TimeInterval)?
        func endPhrase() {
            let phrase = words.trimmingCharacters(in: .whitespacesAndNewlines)
            if !phrase.isEmpty {
                phrases.append(TranscriptSegment(start: times?.start ?? range.start.seconds,
                                                 end: times?.end ?? range.end.seconds, text: phrase))
            }
            words = ""
            times = nil
        }
        for run in text.runs {
            if let time = run.audioTimeRange {
                if let times, time.start.seconds - times.end >= phrasePause || endsSentence(words) { endPhrase() }
                times = (times?.start ?? time.start.seconds, time.end.seconds)
            }
            words += String(text[run.range].characters)
        }
        endPhrase()
        return phrases
    }

    private static func endsSentence(_ words: String) -> Bool {
        words.trimmingCharacters(in: .whitespacesAndNewlines).last.map { ".?!".contains($0) } ?? false
    }
}
