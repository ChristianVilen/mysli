import Cocoa

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

    private let wakeManager: WakeManager
    private let now: () -> Date
    private let notifier: Notifying

    let panelView: KeepAwakePanelView
    private let turnOffItem: NSMenuItem
    private let displayAwakeItem: NSMenuItem

    /// Fired whenever the active/inactive state changes, so the owner can
    /// refresh anything outside this section (e.g. the status-bar icon).
    var onStateChange: (() -> Void)?
    var onDisplayAwakeChanged: ((Bool) -> Void)?

    var isActive: Bool { wakeManager.isActive }

    init(wakeManager: WakeManager = WakeManager(),
         now: @escaping () -> Date = { Date() },
         keepDisplayAwake: Bool,
         notifier: Notifying = SystemNotifier.shared) {
        self.wakeManager = wakeManager
        self.now = now
        self.notifier = notifier
        panelView = KeepAwakePanelView(presets: Self.presets)
        turnOffItem = NSMenuItem(title: "Turn Off", action: #selector(turnOff(_:)), keyEquivalent: "")
        displayAwakeItem = NSMenuItem(title: "Keep screen on", action: #selector(toggleDisplayAwake), keyEquivalent: "")
        super.init()
        turnOffItem.target = self
        displayAwakeItem.target = self
        turnOffItem.isHidden = true
        panelView.onSelectDuration = { [weak self] duration in self?.select(duration) }
        wakeManager.keepDisplayAwake = keepDisplayAwake
        wakeManager.onStateChange = { [weak self] in self?.handleStateChange() }
        wakeManager.onExpire = { [weak self] in self?.notifyEnded() }
    }

    /// Releases the power assertion. Call on app termination.
    func deactivate() {
        wakeManager.deactivate()
    }

    /// Does not ask for notification permission; the chip-click path does.
    func activate(_ duration: WakeDuration) {
        wakeManager.activate(duration)
    }

    func buildMenuSection(into menu: NSMenu) {
        let panelItem = NSMenuItem()
        panelItem.view = panelView
        menu.addItem(panelItem)
        menu.addItem(displayAwakeItem)
        menu.addItem(turnOffItem)

        let hint = NSMenuItem(title: "Closing the lid still sleeps your Mac", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        hint.indentationLevel = 1
        menu.addItem(hint)

        menu.addItem(.separator())

        updateMenu()
    }

    func menuWillOpen() {
        updateMenu()
    }

    func menuTick() {
        updateMenu()
    }

    private func select(_ duration: WakeDuration) {
        // Only timed sessions post an expiry notification, so request
        // permission only for them.
        if case .timed = duration {
            notifier.requestPermission()
        }
        activate(duration)
    }

    func setDisplayAwake(_ isOn: Bool) {
        wakeManager.keepDisplayAwake = isOn
        updateMenu()
    }

    @objc private func toggleDisplayAwake() {
        let enabled = !wakeManager.keepDisplayAwake
        setDisplayAwake(enabled)
        onDisplayAwakeChanged?(enabled)
    }

    @objc private func turnOff(_ sender: NSMenuItem) {
        deactivate()
    }

    private func handleStateChange() {
        updateMenu()
        onStateChange?()
    }

    private func updateMenu() {
        displayAwakeItem.state = wakeManager.keepDisplayAwake ? .on : .off
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
    }

    private func notifyEnded() {
        // The notification center silently drops this if permission was denied or not asked.
        notifier.post(title: "Ku-Ka", body: "Keep-awake ended — your Mac can sleep again.", onClick: nil)
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

// In an extension: on the class declaration, the conformance would make the
// whole class @MainActor, and the nonisolated KeepAwakeControllerTests could
// no longer create or drive it.
extension KeepAwakeController: MenuSection {}
