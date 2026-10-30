import Cocoa

@MainActor
final class SettingsPreviewAppDelegate: NSObject, NSApplicationDelegate {
    let statusMenu = StatusMenu(sections: [])
    let settingsWindow: SettingsWindowController
    private var statusItem: NSStatusItem?

    init(defaults: UserDefaults = UserDefaults(suiteName: "KuKa.TestHost")!,
         present: @escaping (NSWindow) -> Void = SettingsWindowController.presentWindow,
         activation: OrdinaryWindowActivation = .shared) {
        settingsWindow = SettingsWindowController(
            settings: Settings(defaults: defaults, loginItem: DisabledLoginItem()),
            present: present, activation: activation)
        super.init()
        statusMenu.onShowSettings = { [weak self] in self?.settingsWindow.show() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = statusMenu.icon(keepAwakeActive: false, recording: nil, warning: nil)
        item.menu = statusMenu.menu
        statusItem = item
        NSApp.mainMenu = statusMenu.applicationMenu()
    }
}

private struct DisabledLoginItem: LoginItemManaging {
    var isEnabled: Bool { false }
    func setEnabled(_ enabled: Bool) throws {}
}
