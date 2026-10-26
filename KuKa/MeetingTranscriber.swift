import AVFAudio
import Speech

protocol Transcribing {
    var name: String { get }
    func needsDownload(for locale: Locale) async throws -> Bool
    func download(for locale: Locale) async throws
    func load(for locale: Locale) async throws -> any TranscriptionSession
}

protocol TranscriptionSession {
    func transcribe(_ audio: URL) async throws -> TrackTranscript
}

struct TranscriberFailure: Equatable, CustomStringConvertible {
    enum Stage: Equatable {
        case unavailable
        case download
        case load
    }
    let transcriber: String
    let stage: Stage
    let message: String

    var description: String {
        switch stage {
        case .unavailable: return "\(transcriber) cannot be used: \(message)"
        case .download: return "\(transcriber) could not download its model: \(message)"
        case .load: return "\(transcriber) could not load its model: \(message)"
        }
    }
}

/// Needs no speech-recognition permission and no
/// `NSSpeechRecognitionUsageDescription` (measured).
struct SpeechTranscriberAdapter: Transcribing {
    var name: String { "Apple speech recognition" }

    @concurrent
    func needsDownload(for locale: Locale) async throws -> Bool {
        guard SpeechTranscriber.isAvailable else {
            throw MeetingStepError("On-device speech recognition is not available on this Mac.")
        }
        let wanted = locale.identifier(.bcp47)
        let supported = await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }
        guard supported.contains(wanted) else {
            throw MeetingStepError("Speech recognition does not support \(wanted) on this Mac. "
                                   + "Supported: \(supported.sorted().joined(separator: ", ")).")
        }
        return await !SpeechTranscriber.installedLocales.contains { $0.identifier(.bcp47) == wanted }
    }

    @concurrent
    func download(for locale: Locale) async throws {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    func load(for locale: Locale) async throws -> any TranscriptionSession {
        Session(locale: locale)
    }

    private struct Session: TranscriptionSession {
        let locale: Locale

        @concurrent
        func transcribe(_ audio: URL) async throws -> TrackTranscript {
            let file = try AVAudioFile(forReading: audio)
            guard file.length > 0 else { return TrackTranscript(segments: [], duration: 0) }
            let duration = Double(file.length) / file.processingFormat.sampleRate

            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            let collector = Task { () -> [TranscriptSegment] in
                var segments: [TranscriptSegment] = []
                for try await result in transcriber.results {
                    segments.append(TranscriptSegment(start: result.range.start.seconds,
                                                      end: result.range.end.seconds,
                                                      text: String(result.text.characters)))
                }
                return segments
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            do {
                if let last = try await analyzer.analyzeSequence(from: file) {
                    try await analyzer.finalizeAndFinish(through: last)
                } else {
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                }
            } catch {
                collector.cancel()
                throw error
            }
            return TrackTranscript(segments: try await collector.value, duration: duration)
        }
    }
}
