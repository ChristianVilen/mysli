import Foundation
import IOKit.pwr_mgt

/// Seam over the IOKit power assertion so the orchestration logic can be
/// tested without touching real system sleep state.
protocol SleepPreventing: AnyObject {
    /// Create the assertion if not already held. Idempotent — returns true
    /// when the assertion is held afterwards, false when creation failed.
    /// `keepDisplayAwake` chooses whether the display is kept on too.
    func begin(reason: String, keepDisplayAwake: Bool) -> Bool
    /// Release the assertion if held. Idempotent.
    func end()
    var isPreventing: Bool { get }
}

/// Production implementation backed by `IOPMAssertionCreateWithName`.
/// `keepDisplayAwake` picks the assertion type: `PreventUserIdleDisplaySleep`
/// keeps both display and system awake; `PreventUserIdleSystemSleep` keeps
/// only the system awake, so the display sleeps and the screen locks on its
/// normal schedule. Not thread-safe; call from the main thread.
final class IOKitSleepPreventer: SleepPreventing {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isPreventing = false

    func begin(reason: String, keepDisplayAwake: Bool) -> Bool {
        guard !isPreventing else { return true }
        let type = keepDisplayAwake
            ? kIOPMAssertionTypePreventUserIdleDisplaySleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            Log.keepAwake.error("Failed to create power assertion (code \(result))")
            return false
        }
        assertionID = id
        isPreventing = true
        return true
    }

    func end() {
        guard isPreventing else { return }
        let result = IOPMAssertionRelease(assertionID)
        if result != kIOReturnSuccess {
            Log.keepAwake.error("Failed to release power assertion (code \(result))")
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
    private let scheduleExpiry: (TimeInterval, @escaping () -> Void) -> () -> Void
    private var cancelExpiry: (() -> Void)?

    private(set) var session: WakeSession?
    var isActive: Bool { session != nil }

    /// Whether sessions should also keep the display on. Toggling this during
    /// an active session swaps the underlying assertion without ending the
    /// session or touching its expiry timer.
    var keepDisplayAwake = false {
        didSet {
            guard oldValue != keepDisplayAwake, isActive else { return }
            preventer.end()
            if !preventer.begin(reason: Self.assertionReason, keepDisplayAwake: keepDisplayAwake) {
                // The replacement assertion failed; end the session rather
                // than report one that protects nothing.
                deactivate()
            }
        }
    }

    private static let assertionReason = "Mysli Keep Awake"

    /// Fired whenever the active/inactive state or session changes.
    var onStateChange: (() -> Void)?
    /// Fired only when a timed session reaches its expiry (not on manual off).
    var onExpire: (() -> Void)?

    /// `scheduleExpiry` runs its work once after the interval and returns a
    /// closure that cancels it.
    init(preventer: SleepPreventing = IOKitSleepPreventer(), now: @escaping () -> Date = { Date() },
         scheduleExpiry: @escaping (TimeInterval, @escaping () -> Void) -> () -> Void = WakeManager.afterInterval) {
        self.preventer = preventer
        self.now = now
        self.scheduleExpiry = scheduleExpiry
    }

    static func afterInterval(_ interval: TimeInterval, _ work: @escaping () -> Void) -> () -> Void {
        let timer = Timer(timeInterval: interval, repeats: false) { _ in work() }
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }

    func activate(_ duration: WakeDuration) {
        cancelExpiry?()
        cancelExpiry = nil

        // If this fails we were not preventing, so no session existed either —
        // returning leaves the manager honestly inactive.
        guard preventer.begin(reason: Self.assertionReason, keepDisplayAwake: keepDisplayAwake) else { return }

        let session = WakeSession(startedAt: now(), duration: duration)
        self.session = session

        if let expiresAt = session.expiresAt {
            let interval = max(0, expiresAt.timeIntervalSince(now()))
            cancelExpiry = scheduleExpiry(interval) { [weak self] in
                self?.deactivate(expired: true)
            }
        }

        onStateChange?()
    }

    func deactivate(expired: Bool = false) {
        guard session != nil else { return }
        cancelExpiry?()
        cancelExpiry = nil
        preventer.end()
        session = nil
        onStateChange?()
        if expired { onExpire?() }
    }
}
