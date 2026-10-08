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
    var tilingEnabled = true { didSet { refresh() } }
    var clipboardHistoryEnabled = false { didSet { refresh() } }
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
            $0.isTiling ? tilingEnabled : $0 != .clipboardHistory || clipboardHistoryEnabled
        })
        setIssues(registrar.reconcile(desired: desired))
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        for observer in observers { workspaceNotifications.removeObserver(observer) }
        observers = []
        setIssues(registrar.stop())
    }

    private func renewRegistrations() {
        guard isRunning else { return }
        registrar.stop()
        refresh()
    }

    private func setIssues(_ newIssues: [HotkeyRegistrationIssue]) {
        guard issues != newIssues else { return }
        for issue in newIssues where !issues.contains(issue) {
            NSLog("Ku-Ka: Shortcut unavailable: \(issue.shortcut.label), \(issue.failure)")
        }
        issues = newIssues
        onChange?()
    }
}
