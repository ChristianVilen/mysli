import Cocoa

@MainActor
final class SettingsPreviewAppDelegate: NSObject, NSApplicationDelegate {
    let statusMenu: StatusMenu
    let settingsWindow: SettingsWindowController
    private let keepAwake: KeepAwakeController
    private var statusItem: NSStatusItem?

    init(defaults: UserDefaults = UserDefaults(suiteName: "Mysli.TestHost")!,
         present: @escaping @MainActor (NSWindow) -> Void = SettingsWindowController.presentWindow,
         activation: OrdinaryWindowActivation = .shared) {
        let settings = Settings(defaults: defaults, loginItem: DisabledLoginItem())
        keepAwake = KeepAwakeController(wakeManager: WakeManager(preventer: PreviewSleepPreventer()),
                                        keepDisplayAwake: settings.keepDisplayAwake, notifier: PreviewNotifier())
        statusMenu = StatusMenu(sections: [
            EnabledMenuSection(keepAwake, isEnabled: { settings.keepAwakeEnabled })
        ])
        settingsWindow = SettingsWindowController(
            settings: settings, permissionActions: .inert, openURL: { _ in },
            present: present, activation: activation)
        super.init()
        statusMenu.onShowSettings = { [weak self] in self?.settingsWindow.show() }
        keepAwake.onDisplayAwakeChanged = { settings.keepDisplayAwake = $0 }
        settingsWindow.onKeepScreenOnChanged = { [keepAwake] in keepAwake.setDisplayAwake($0) }
        settingsWindow.onKeepAwakeChanged = { [keepAwake] enabled in
            if !enabled { keepAwake.deactivate() }
        }
        settingsWindow.renderPermissions(.init(accessibility: true, screenRecording: false, microphone: .notDetermined,
                                               calendar: .notDetermined, notifications: .notDetermined))
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
