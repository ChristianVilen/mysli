import Foundation

/// How long a keep-awake session should last.
enum WakeDuration: Equatable {
    case indefinite
    case timed(TimeInterval)
}

/// Pure, side-effect-free model of a keep-awake session. All time-dependent
/// queries take an explicit `now` so the logic is deterministically testable.
struct WakeSession: Equatable {
    let startedAt: Date
    let duration: WakeDuration

    var expiresAt: Date? {
        switch duration {
        case .indefinite:
            return nil
        case .timed(let interval):
            return startedAt.addingTimeInterval(interval)
        }
    }

    func isExpired(now: Date) -> Bool {
        guard let expiresAt = expiresAt else { return false }
        return now >= expiresAt
    }

    func remaining(now: Date) -> TimeInterval? {
        guard let expiresAt = expiresAt else { return nil }
        return max(0, expiresAt.timeIntervalSince(now))
    }
}
