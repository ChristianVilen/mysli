import Cocoa
import UserNotifications

/// Owns the "Keep Awake" menu section and drives a `WakeManager`: builds the
/// inline panel (status line, duration chips, display checkbox) plus the
/// Turn Off item, reflects session state, runs the per-second countdown while
/// the menu is open, persists the display-awake preference, and posts the
/// expiry notification. Keeping all of the feature's AppKit glue here lets
/// `AppDelegate` stay a thin coordinator.
final class KeepAwakeController: NSObject {
    /// Selectable keep-awake durations, in chip order. The chip index is the
    /// only identifier that travels through the panel's callback.
    static let presets: [(chip: String, duration: WakeDuration)] = [
        ("30m", .timed(30 * 60)),
        ("1h", .timed(60 * 60)),
        ("2h", .timed(120 * 60)),
        ("4h", .timed(240 * 60)),
        ("∞", .indefinite),
    ]

    static let displayAwakeDefaultsKey = "keepDisplayAwake"

    private let wakeManager: WakeManager
    private let now: () -> Date
    private let defaults: UserDefaults

    let panelView: KeepAwakePanelView
    private let turnOffItem: NSMenuItem
    private var countdownTimer: Timer?
    private var hasRequestedNotificationAuth = false

    /// Fired whenever the active/inactive state changes, so the owner can
    /// refresh anything outside this section (e.g. the status-bar icon).
    var onStateChange: (() -> Void)?

    var isActive: Bool { wakeManager.isActive }

    init(wakeManager: WakeManager = WakeManager(),
         now: @escaping () -> Date = { Date() },
         defaults: UserDefaults = .standard) {
        self.wakeManager = wakeManager
        self.now = now
        self.defaults = defaults
        panelView = KeepAwakePanelView(presets: Self.presets)
        turnOffItem = NSMenuItem(title: "Turn Off", action: #selector(turnOff(_:)), keyEquivalent: "")
        super.init()
        turnOffItem.target = self
        turnOffItem.isHidden = true
        panelView.onSelectDuration = { [weak self] duration in self?.select(duration) }
        panelView.onToggleDisplayAwake = { [weak self] isOn in self?.setDisplayAwake(isOn) }
        // Defaults to on: a dark, locked screen reads as "the feature didn't
        // work", so keeping the display awake is the least surprising default.
        wakeManager.keepDisplayAwake = defaults.object(forKey: Self.displayAwakeDefaultsKey) as? Bool ?? true
        wakeManager.onStateChange = { [weak self] in self?.handleStateChange() }
        wakeManager.onExpire = { [weak self] in self?.notifyEnded() }
    }

    /// Releases the power assertion. Call on app termination.
    func deactivate() {
        wakeManager.deactivate()
    }

    /// Starts a keep-awake session. The non-UI activation path; chip clicks
    /// layer the notification-permission prompt on top of this.
    func activate(_ duration: WakeDuration) {
        wakeManager.activate(duration)
    }

    // MARK: - Menu construction

    /// Appends the full "Keep Awake" section (inline panel, Turn Off, lid
    /// hint, and a trailing separator) to `menu`.
    func buildMenuSection(into menu: NSMenu) {
        let panelItem = NSMenuItem()
        panelItem.view = panelView
        menu.addItem(panelItem)
        menu.addItem(turnOffItem)

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

    private func select(_ duration: WakeDuration) {
        // Only timed sessions post an expiry notification, so request
        // permission (once) only for them.
        if case .timed = duration {
            requestNotificationAuthIfNeeded()
        }
        activate(duration)
    }

    private func setDisplayAwake(_ isOn: Bool) {
        defaults.set(isOn, forKey: Self.displayAwakeDefaultsKey)
        wakeManager.keepDisplayAwake = isOn
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
        turnOffItem.isHidden = session == nil

        if let session {
            if let remaining = session.remaining(now: now()) {
                panelView.titleLabel.stringValue = "☕ Awake · \(Self.formatRemaining(remaining))"
            } else {
                panelView.titleLabel.stringValue = "☕ Awake · On"
            }
        } else {
            panelView.titleLabel.stringValue = "Keep Awake"
        }

        panelView.showSelection(session?.duration)
        panelView.displayAwakeCheckbox.state = wakeManager.keepDisplayAwake ? .on : .off
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
