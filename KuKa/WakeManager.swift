import Foundation
import IOKit.pwr_mgt

/// Seam over the IOKit power assertion so the orchestration logic can be
/// tested without touching real system sleep state.
protocol SleepPreventing: AnyObject {
    /// Create the assertion if not already held. Idempotent.
    func begin(reason: String)
    /// Release the assertion if held. Idempotent.
    func end()
    var isPreventing: Bool { get }
}

/// Production implementation backed by `IOPMAssertionCreateWithName` with the
/// `PreventUserIdleSystemSleep` assertion type — keeps the system awake while
/// allowing the display to sleep. Not thread-safe; call from the main thread.
final class IOKitSleepPreventer: SleepPreventing {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isPreventing = false

    func begin(reason: String) {
        guard !isPreventing else { return }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        if result == kIOReturnSuccess {
            assertionID = id
            isPreventing = true
        } else {
            NSLog("Ku-Ka: failed to create power assertion (code \(result))")
        }
    }

    func end() {
        guard isPreventing else { return }
        let result = IOPMAssertionRelease(assertionID)
        if result != kIOReturnSuccess {
            NSLog("Ku-Ka: failed to release power assertion (code \(result))")
        }
        assertionID = 0
        isPreventing = false
    }
}

/// Orchestrates a keep-awake session: drives the `SleepPreventing` seam,
/// schedules expiry for timed sessions, and reports state via closures.
/// Not thread-safe; intended to be used from the main thread.
final class WakeManager {
    private let preventer: SleepPreventing
    private let now: () -> Date
    private var timer: Timer?

    private(set) var session: WakeSession?
    var isActive: Bool { session != nil }

    /// Fired whenever the active/inactive state or session changes.
    var onStateChange: (() -> Void)?
    /// Fired only when a timed session reaches its expiry (not on manual off).
    var onExpire: (() -> Void)?

    init(preventer: SleepPreventing = IOKitSleepPreventer(), now: @escaping () -> Date = { Date() }) {
        self.preventer = preventer
        self.now = now
    }

    func activate(_ duration: WakeDuration) {
        timer?.invalidate()
        timer = nil

        let session = WakeSession(startedAt: now(), duration: duration)
        self.session = session
        preventer.begin(reason: "Ku-Ka Keep Awake")

        if let expiresAt = session.expiresAt {
            let interval = max(0, expiresAt.timeIntervalSince(now()))
            let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
                self?.deactivate(expired: true)
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        onStateChange?()
    }

    func deactivate(expired: Bool = false) {
        guard session != nil else { return }
        timer?.invalidate()
        timer = nil
        preventer.end()
        session = nil
        onStateChange?()
        if expired { onExpire?() }
    }
}
