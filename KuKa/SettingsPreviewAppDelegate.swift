import Cocoa

@MainActor
final class SettingsPreviewAppDelegate: NSObject, NSApplicationDelegate {
    let statusMenu: StatusMenu
    let settingsWindow: SettingsWindowController
    private let keepAwake: KeepAwakeController
    private var statusItem: NSStatusItem?

    init(defaults: UserDefaults = UserDefaults(suiteName: "KuKa.TestHost")!,
         present: @escaping (NSWindow) -> Void = SettingsWindowController.presentWindow,
         activation: OrdinaryWindowActivation = .shared) {
        let settings = Settings(defaults: defaults, loginItem: DisabledLoginItem())
        keepAwake = KeepAwakeController(wakeManager: WakeManager(preventer: PreviewSleepPreventer()),
                                        keepDisplayAwake: settings.keepDisplayAwake, notifier: PreviewNotifier())
        statusMenu = StatusMenu(sections: [keepAwake])
        settingsWindow = SettingsWindowController(
            settings: settings, permissionActions: .inert, openURL: { _ in },
            present: present, activation: activation)
        super.init()
        statusMenu.onShowSettings = { [weak self] in self?.settingsWindow.show() }
        statusMenu.onShowKuKa = statusMenu.onShowSettings
        statusMenu.onShowPermissions = { [weak self] in self?.settingsWindow.show(.permissions) }
        keepAwake.onDisplayAwakeChanged = { settings.keepDisplayAwake = $0 }
        settingsWindow.renderPermissions(.init(accessibility: true, screenRecording: false, microphone: .notDetermined))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = statusMenu.icon(keepAwakeActive: false, recording: nil, warning: nil)
        item.menu = statusMenu.menu
        statusItem = item
        NSApp.mainMenu = statusMenu.applicationMenu()
        settingsWindow.show()
    }
}

private struct DisabledLoginItem: LoginItemManaging {
    var isEnabled: Bool { false }
    func setEnabled(_ enabled: Bool) throws {}
}

private final class PreviewSleepPreventer: SleepPreventing {
    private(set) var isPreventing = false
    func begin(reason: String, keepDisplayAwake: Bool) -> Bool { isPreventing = true; return true }
    func end() { isPreventing = false }
}

private struct PreviewNotifier: Notifying {
    func requestPermission() {}
    func post(title: String, body: String, onClick: NotificationClick?) {}
}
