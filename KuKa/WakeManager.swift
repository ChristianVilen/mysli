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
            NSLog("Ku-Ka: failed to create power assertion (code \(result))")
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

    private static let assertionReason = "Ku-Ka Keep Awake"

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

        // If this fails we were not preventing, so no session existed either —
        // returning leaves the manager honestly inactive.
        guard preventer.begin(reason: Self.assertionReason, keepDisplayAwake: keepDisplayAwake) else { return }

        let session = WakeSession(startedAt: now(), duration: duration)
        self.session = session

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
