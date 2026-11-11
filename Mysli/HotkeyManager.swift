import Cocoa

enum HotkeyAction: Equatable {
    case captureArea
    case captureFullScreen
    case tile(TilingAction)
    case showClipboardHistory
}

@MainActor
final class HotkeyManager {
    private let registrar: CarbonHotkeyRegistrar
    private let pollInterval: TimeInterval
    private let workspaceNotifications: NotificationCenter
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private(set) var isRunning = false
    private(set) var issues: [HotkeyRegistrationIssue] = []
    var onChange: (() -> Void)?
    var screenshotsEnabled = true { didSet { refresh() } }
    var tilingEnabled = true { didSet { refresh() } }
    var clipboardHistoryEnabled = false { didSet { refresh() } }
    var dictationEnabled = false { didSet { refresh() } }
    var dictationCancellable = false { didSet { refresh() } }
    var onDictationAvailabilityChange: (() -> Void)?
    var onDictation: ((DictationKeyEvent) -> Void)? {
        get { registrar.onDictation }
        set { registrar.onDictation = newValue }
    }
    var onAction: ((HotkeyAction) -> Void)? {
        get { registrar.onAction }
        set { registrar.onAction = newValue }
    }

    init(registrar: CarbonHotkeyRegistrar = CarbonHotkeyRegistrar(),
         pollInterval: TimeInterval = 5,
         workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.registrar = registrar
        self.pollInterval = pollInterval
        self.workspaceNotifications = workspaceNotifications
    }

    isolated deinit {
        timer?.invalidate()
        for observer in observers { workspaceNotifications.removeObserver(observer) }
        registrar.stop()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refresh()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspaceNotifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.renewRegistrations() }
            })
        }
    }

    func refresh() {
        guard isRunning else { return }
        let desired = Set(HotkeyShortcut.allCases.filter {
            if $0 == .dictation { return dictationEnabled }
            if $0 == .dictationEscape { return dictationEnabled && dictationCancellable }
            if $0.isTiling { return tilingEnabled }
            if $0.isScreenshot { return screenshotsEnabled }
            return clipboardHistoryEnabled
        })
        setIssues(registrar.reconcile(desired: desired))
        onDictationAvailabilityChange?()
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        for observer in observers { workspaceNotifications.removeObserver(observer) }
        observers = []
        setIssues(registrar.stop())
        onDictationAvailabilityChange?()
    }

    private func renewRegistrations() {
        guard isRunning else { return }
        registrar.stop()
        refresh()
    }

    private func setIssues(_ newIssues: [HotkeyRegistrationIssue]) {
        guard issues != newIssues else { return }
        for issue in newIssues where !issues.contains(issue) {
            Log.hotkeys.error("Shortcut unavailable: \(issue.shortcut.label, privacy: .public), \(String(describing: issue.failure), privacy: .public)")
        }
        issues = newIssues
        onChange?()
    }
}
