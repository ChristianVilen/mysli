import Cocoa

final class SettingsPermissionsView: NSStackView {
    let permissionList: PermissionListView
    let keyboardSettings = NSButton(title: "Open Keyboard Settings…", target: nil, action: nil)
    private let shortcutText = SettingsLayout.label("", size: 12)
    private let keyboardAction: () -> Void
    private let shortcutGroup: SettingsGlass
    private let shortcutHeading = SettingsLayout.heading("Screenshot shortcuts", symbol: "keyboard", color: .systemOrange)

    var controls: [NSView] {
        permissionList.controls + (shortcutGroup.isHidden ? [] : [keyboardSettings])
    }

    init(actions: PermissionActions) {
        permissionList = PermissionListView(actions: actions)
        keyboardAction = actions.keyboardSettings
        shortcutGroup = SettingsLayout.group([shortcutText, keyboardSettings])
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 16
        SettingsLayout.add(SettingsLayout.page(title: "Permissions", subtitle: "Allow access for the features you use. Status updates while this page is open."), to: self)
        SettingsLayout.add(permissionList, to: self)
        SettingsLayout.add(SettingsLayout.label("Turn on more tools to see their permissions.", size: 12, secondary: true), to: self)
        SettingsLayout.add(shortcutHeading, to: self)
        SettingsLayout.add(shortcutGroup, to: self)
        SettingsLayout.add(SettingsLayout.label("Meeting audio stays on this Mac. To create a summary, Mysli sends the transcript and any selected background file to your chosen AI tool.", size: 12, secondary: true), to: self)
        keyboardSettings.bezelStyle = .rounded
        keyboardSettings.target = self
        keyboardSettings.action = #selector(openKeyboardSettings)
        showShortcutConflicts([])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func showRequired(_ required: RequiredPermissions, screenshotShortcuts: Bool) {
        permissionList.showRequired(required)
        shortcutGroup.isHidden = !screenshotShortcuts
        shortcutHeading.isHidden = !screenshotShortcuts
    }

    func showShortcutConflicts(_ shortcuts: [HotkeyShortcut]) {
        let choices = shortcuts.isEmpty ? [.captureFullScreen, .captureArea] : shortcuts
        let labels = choices.map { shortcut in
            let setting = shortcut == .captureFullScreen
                ? "Save picture of screen as a file" : "Save picture of selected area as a file"
            return "\(shortcut.label)\n\(setting)"
        }.joined(separator: "\n\n")
        let introduction = shortcuts.isEmpty
            ? "Mysli uses the same screenshot shortcuts as macOS. If a shortcut is unavailable, open Keyboard Settings > Keyboard Shortcuts > Screenshots and turn off the matching macOS shortcut."
            : "macOS is using these shortcuts. Open Keyboard Settings > Keyboard Shortcuts > Screenshots and turn off the matching macOS shortcuts."
        shortcutText.stringValue = "\(introduction)\n\n\(labels)\n\nMysli retries automatically. If you quit Mysli, turn these shortcuts back on to use the macOS screenshot tool."
    }

    func revealShortcutSetup() {
        layoutSubtreeIfNeeded()
        scrollToVisible(shortcutGroup.frame)
    }

    @objc private func openKeyboardSettings() { keyboardAction() }
}
