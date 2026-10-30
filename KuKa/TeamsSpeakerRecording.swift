import Foundation

struct RecordedMeeting {
    let folder: MeetingFolder
    let speakers: TeamsSpeakerEvidence
}

@MainActor
final class TeamsSpeakerRecording {
    private let observer: any TeamsSpeakerObserving
    private let log: (LogMessage) -> Void
    private var history = TeamsSpeakerHistory()
    private var tally = TeamsScanTally()
    private var task: Task<Void, Never>?
    private var runID: UUID?
    private var ended = false

    init(observer: any TeamsSpeakerObserving, log: @escaping (LogMessage) -> Void = { Log.teams.notice($0) }) {
        self.observer = observer
        self.log = log
    }

    static func startLine(enabled: Bool, accessibilityGranted: Bool) -> LogMessage {
        guard enabled else { return "Teams speaker names: off." }
        return accessibilityGranted
            ? "Teams speaker names: on. Accessibility: granted."
            : "Teams speaker names: on. Accessibility: not granted."
    }

    isolated deinit { task?.cancel() }

    func resume(at lowerBound: HostTime) {
        guard !ended, runID == nil else { return }
        let id = UUID()
        runID = id
        let observations = observer.observations()
        task = Task { [weak self] in
            for await sample in observations {
                guard !Task.isCancelled, let self, self.runID == id else { break }
                guard sample.began >= lowerBound else { continue }
                if let line = self.tally.line(for: sample) { self.log(line) }
                if !self.history.append(sample, runID: id) {
                    self.log("Teams speaker names: collection stopped at the cap of \(TeamsSpeakerHistory.capacity) scans.")
                    self.ended = true
                    self.pause()
                    break
                }
            }
        }
    }

    func pause() {
        runID = nil
        task?.cancel()
        task = nil
    }

    func finish(clock: RecordingClock, endingAt: HostTime) -> TeamsSpeakerEvidence {
        pause()
        ended = true
        let evidence = history.finish(clock: clock, endingAt: endingAt)
        log(evidence.scans.stopLine)
        return evidence
    }
}
