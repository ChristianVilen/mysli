import Cocoa
import UserNotifications

/// Owns the "Keep Awake" menu section and drives a `WakeManager`: builds the
/// menu items, reflects session state (countdown header, preset checkmarks),
/// runs the per-second countdown while the menu is open, and posts the expiry
/// notification. Keeping all of the feature's AppKit glue here lets
/// `AppDelegate` stay a thin coordinator.
final class KeepAwakeController: NSObject {
    /// Selectable keep-awake durations, in menu order. The `WakeDuration` is
    /// carried directly on each item's `representedObject`, so there is no
    /// separate tag encoding to keep in sync.
    private static let presets: [(title: String, duration: WakeDuration)] = [
        ("30 minutes", .timed(30 * 60)),
        ("1 hour", .timed(60 * 60)),
        ("2 hours", .timed(120 * 60)),
        ("4 hours", .timed(240 * 60)),
        ("Until I turn it off", .indefinite),
    ]

    private let wakeManager: WakeManager
    private let now: () -> Date

    private var headerItem: NSMenuItem?
    private var turnOffItem: NSMenuItem?
    private var presetItems: [NSMenuItem] = []
    private var countdownTimer: Timer?
    private var hasRequestedNotificationAuth = false

    /// Fired whenever the active/inactive state changes, so the owner can
    /// refresh anything outside this section (e.g. the status-bar icon).
    var onStateChange: (() -> Void)?

    var isActive: Bool { wakeManager.isActive }

    init(wakeManager: WakeManager = WakeManager(), now: @escaping () -> Date = { Date() }) {
        self.wakeManager = wakeManager
        self.now = now
        super.init()
        wakeManager.onStateChange = { [weak self] in self?.handleStateChange() }
        wakeManager.onExpire = { [weak self] in self?.notifyEnded() }
    }

    /// Releases the power assertion. Call on app termination.
    func deactivate() {
        wakeManager.deactivate()
    }

    /// Starts a keep-awake session. The non-UI activation path; `selectDuration`
    /// layers the notification-permission prompt on top of this.
    func activate(_ duration: WakeDuration) {
        wakeManager.activate(duration)
    }

    // MARK: - Menu construction

    /// Appends the full "Keep Awake" section (label, status header, Turn Off,
    /// preset submenu, lid hint, and a trailing separator) to `menu`.
    func buildMenuSection(into menu: NSMenu) {
        let label = NSMenuItem(title: "Keep Awake", action: nil, keyEquivalent: "")
        label.isEnabled = false
        menu.addItem(label)

        let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.isHidden = true
        menu.addItem(header)
        headerItem = header

        let turnOff = NSMenuItem(title: "Turn Off", action: #selector(turnOff(_:)), keyEquivalent: "")
        turnOff.target = self
        turnOff.isHidden = true
        menu.addItem(turnOff)
        turnOffItem = turnOff

        let forItem = NSMenuItem(title: "Keep Awake For", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for preset in Self.presets {
            let item = NSMenuItem(title: preset.title, action: #selector(selectDuration(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.duration
            submenu.addItem(item)
            presetItems.append(item)
        }
        forItem.submenu = submenu
        menu.addItem(forItem)

        let hint = NSMenuItem(title: "Closing the lid still sleeps your Mac", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        hint.indentationLevel = 1
        menu.addItem(hint)

        menu.addItem(.separator())

        updateMenu()
    }

    // MARK: - Menu delegate forwarding (called by AppDelegate)

    func menuWillOpen() {
        updateMenu()
        // Re-entrancy guard: never leak a previous timer if open/close didn't pair.
        countdownTimer?.invalidate()
        countdownTimer = nil
        guard wakeManager.session?.expiresAt != nil else { return }
        // .common mode so it keeps firing while the menu tracks events. Teardown
        // is owned solely by menuDidClose.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMenu()
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    func menuDidClose() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    // MARK: - Actions

    @objc private func selectDuration(_ sender: NSMenuItem) {
        guard let duration = sender.representedObject as? WakeDuration else { return }
        // Only timed sessions post an expiry notification, so request permission
        // (once) only for them.
        if case .timed = duration {
            requestNotificationAuthIfNeeded()
        }
        activate(duration)
    }

    @objc private func turnOff(_ sender: NSMenuItem) {
        deactivate()
    }

    // MARK: - State

    private func handleStateChange() {
        updateMenu()
        onStateChange?()
    }

    private func updateMenu() {
        let session = wakeManager.session
        headerItem?.isHidden = session == nil
        turnOffItem?.isHidden = session == nil

        if let session {
            if let remaining = session.remaining(now: now()) {
                headerItem?.title = "☕ Awake · \(Self.formatRemaining(remaining))"
            } else {
                headerItem?.title = "☕ Awake · On"
            }
        }

        for item in presetItems {
            let duration = item.representedObject as? WakeDuration
            item.state = (duration == session?.duration) ? .on : .off
        }
    }

    private func requestNotificationAuthIfNeeded() {
        guard !hasRequestedNotificationAuth else { return }
        hasRequestedNotificationAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyEnded() {
        // If notification authorization was denied or never requested (indefinite
        // sessions don't request it), the center silently drops this request.
        // That's fine — the notification is purely informational.
        let content = UNMutableNotificationContent()
        content.title = "Ku-Ka"
        content.body = "Keep-awake ended — your Mac can sleep again."
        let request = UNNotificationRequest(identifier: "keepAwakeEnded", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func formatRemaining(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(ceil(interval / 60))
        if totalMinutes <= 0 { return "less than a minute left" }
        if totalMinutes < 60 { return "\(totalMinutes) min left" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours)h left" : "\(hours)h \(minutes)m left"
    }
}
