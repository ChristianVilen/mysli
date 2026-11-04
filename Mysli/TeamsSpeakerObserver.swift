import Foundation

protocol TeamsSpeakerObserving: Sendable {
    func observations() -> AsyncStream<TeamsSpeakerObservation>
}

protocol TeamsSnapshotReading {
    func snapshot() -> TeamsAXSnapshot
}

extension TeamsAccessibility: TeamsSnapshotReading {}

struct TeamsSpeakerObserver: TeamsSpeakerObserving {
    private let makeSource: @Sendable () -> any TeamsSnapshotReading
    private let now: @Sendable () -> HostTime
    private let wait: @Sendable (TimeInterval) async throws -> Void

    init() {
        self.init(makeSource: { makeNativeTeamsSnapshotSource() })
    }

    init(makeSource: @escaping @Sendable () -> any TeamsSnapshotReading,
         now: @escaping @Sendable () -> HostTime = { .now() },
         wait: @escaping @Sendable (TimeInterval) async throws -> Void = {
             try await Task.sleep(for: .seconds($0))
         }) {
        self.makeSource = makeSource
        self.now = now
        self.wait = wait
    }

    func observations() -> AsyncStream<TeamsSpeakerObservation> {
        AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            let task = Task.detached(priority: .utility) {
                guard !Task.isCancelled else { continuation.finish(); return }
                let source = makeSource()
                var sequence = 0
                while !Task.isCancelled {
                    let began = now()
                    let snapshot = source.snapshot()
                    let ended = now()
                    guard !Task.isCancelled else { break }
                    sequence += 1
                    let sample = TeamsSpeakerObservation(began: began, ended: ended, sequence: sequence,
                                                         sourceID: snapshot.sourceID, result: snapshot.result,
                                                         nodes: snapshot.nodes)
                    if case .terminated = continuation.yield(sample) { break }
                    do { try await wait(0.3) } catch { break }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
