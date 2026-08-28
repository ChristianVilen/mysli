import Cocoa

/// Why hotkeys are currently dead, or `.healthy`. One cause at a time, in
/// causal "fix this first" order: without Accessibility no tap can exist at
/// all, and a stuck secure-input grab is what starves an otherwise healthy
/// tap — so it is reported instead of the dead tap it explains, because it
/// is the one with a remedy that works. `.tapDead` therefore means the tap
/// died for some other reason, where restarting the app is the right advice.
enum HotkeyHealth: Equatable {
    case healthy
    /// Accessibility permission is missing, so no event tap can be created.
    case noPermission
    /// Secure keyboard input has been held long enough to count as stuck.
    /// `holderName` is the app holding it, or nil when it can't be resolved.
    case secureInputStuck(holderName: String?)
    /// The event tap exists but the system has kept it disabled past the
    /// watchdog's ability to heal it, with no secure-input grab to blame.
    case tapDead
}

/// How long a condition has been continuously true, against a threshold.
/// Both causes that need dwell time — a dead tap and a held secure-input
/// grab — are the same rule, so they share one implementation.
private struct Dwell {
    let threshold: TimeInterval
    /// True while the condition has been held past `threshold`.
    private(set) var isPast = false
    private var since: Date?

    init(threshold: TimeInterval) {
        self.threshold = threshold
    }

    /// Feeds one reading. Returns true only on the tick where the dwell
    /// first crosses the threshold — the moment to capture anything that
    /// must be read while the condition still holds.
    mutating func update(active: Bool, now: Date) -> Bool {
        guard active else {
            reset()
            return false
        }
        let start = since ?? now
        since = start
        guard !isPast, now.timeIntervalSince(start) >= threshold else { return false }
        isPast = true
        return true
    }

    mutating func reset() {
        isPast = false
        since = nil
    }
}

/// The one place that answers "are hotkeys working, and if not why". Polls
/// its probes on one timer and reduces them to a single cause. Consumers
/// read `state` and listen on `onChange`.
@MainActor
final class HotkeyHealthMonitor {
    private(set) var state: HotkeyHealth = .healthy
    /// Fired whenever `state` changes.
    var onChange: (@MainActor () -> Void)?

    /// How long a cause must hold continuously before it is reported. Long
    /// enough to type a password into a secure field, and to let the tap
    /// watchdog heal a system-disabled tap on its own 5s tick — so neither
    /// normal case ever flashes a warning.
    static let dwellThreshold: TimeInterval = 10

    private let isAccessibilityGranted: () -> Bool
    private let isTapDelivering: () -> Bool
    private let isSecureInputEnabled: () -> Bool
    private let holderName: () -> String?
    private let now: () -> Date
    private let pollInterval: TimeInterval
    private var secureInputHeld = Dwell(threshold: HotkeyHealthMonitor.dwellThreshold)
    private var tapDead = Dwell(threshold: HotkeyHealthMonitor.dwellThreshold)
    /// Resolved once, when the grab first counts as stuck. Read only while
    /// `secureInputHeld.isPast`.
    private var secureInputHolder: String?
    private var timer: Timer?

    /// Neither `isAccessibilityGranted` nor `isTapDelivering` has a default:
    /// permission status is owned by `PermissionsManager` and tap status by
    /// `HotkeyManager`, so the caller must wire both to those owners instead
    /// of letting this type read the system a second time. The secure-input
    /// probes have no other owner, so they default to the real calls. Tests
    /// inject stand-ins for all of them.
    init(
        isAccessibilityGranted: @escaping () -> Bool,
        isTapDelivering: @escaping () -> Bool,
        isSecureInputEnabled: @escaping () -> Bool = SecureInput.isEnabled,
        holderName: @escaping () -> String? = SecureInput.holderName,
        now: @escaping () -> Date = Date.init,
        pollInterval: TimeInterval = 5
    ) {
        self.isAccessibilityGranted = isAccessibilityGranted
        self.isTapDelivering = isTapDelivering
        self.isSecureInputEnabled = isSecureInputEnabled
        self.holderName = holderName
        self.now = now
        self.pollInterval = pollInterval
    }

    /// Poll for the app's lifetime. Every cause can appear (and heal) at any
    /// moment, and an accessory app gets no notification for any of them, so
    /// a timer is the only way to notice.
    func startMonitoring() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            // Timers scheduled from the main thread fire on the main run loop.
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// Re-read every probe and update `state`.
    func refresh() {
        let timestamp = now()
        // Feed both dwells before picking a cause: one that loses this tick
        // must keep its own clock running, or it would restart from zero the
        // moment the louder cause clears. The secure-input dwell ticks even
        // without permission — its signal is valid regardless, so a grab that
        // turned stuck while permission was missing reports the moment
        // permission is granted.
        if secureInputHeld.update(active: isSecureInputEnabled(), now: timestamp) {
            // Resolve the holder while the grab is fresh: the holder can quit
            // and leak the grab, and a later lookup would lose its name.
            secureInputHolder = holderName()
        }
        let accessibility = isAccessibilityGranted()
        if accessibility {
            _ = tapDead.update(active: !isTapDelivering(), now: timestamp)
        } else {
            // Without permission the tap can't exist; don't let dwell time
            // accumulated here surface as an instant tapDead after a grant.
            tapDead.reset()
        }

        guard accessibility else {
            setState(.noPermission)
            return
        }
        if secureInputHeld.isPast {
            setState(.secureInputStuck(holderName: secureInputHolder))
            return
        }
        if tapDead.isPast {
            setState(.tapDead)
            return
        }
        setState(.healthy)
    }

    private func setState(_ new: HotkeyHealth) {
        guard new != state else { return }
        state = new
        onChange?()
    }
}
