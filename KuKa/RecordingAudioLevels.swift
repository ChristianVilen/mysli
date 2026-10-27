import Foundation

struct RecordingAudioLevels: Equatable, Sendable {
    let microphone: Double
    let system: Double

    static let silent = RecordingAudioLevels(microphone: 0, system: 0)
}

struct RecordingAudioMeter {
    private struct Sample {
        let rms: Double
        let receivedAt: TimeInterval
    }

    private var samples: [MeetingTrack: Sample] = [:]

    mutating func record(rms: Double, for track: MeetingTrack, at uptime: TimeInterval) {
        samples[track] = Sample(rms: rms, receivedAt: uptime)
    }

    func levels(at uptime: TimeInterval) -> RecordingAudioLevels {
        RecordingAudioLevels(microphone: fraction(for: .microphone, at: uptime),
                             system: fraction(for: .system, at: uptime))
    }

    private func fraction(for track: MeetingTrack, at uptime: TimeInterval) -> Double {
        guard let sample = samples[track], uptime - sample.receivedAt < 0.5, sample.rms > 0 else { return 0 }
        return min(1, max(0, (20 * log10(sample.rms) + 60) / 60))
    }
}
