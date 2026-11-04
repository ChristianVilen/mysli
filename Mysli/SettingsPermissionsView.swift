import Cocoa

struct PermissionActions {
    let accessibility: () -> Void
    let screenRecording: () -> Void
    let microphone: () -> Void
    let calendar: () -> Void
    let notifications: () -> Void
    let keyboardSettings: () -> Void

    static let inert = Self(accessibility: {}, screenRecording: {}, microphone: {}, calendar: {}, notifications: {}, keyboardSettings: {})
}

final class PermissionRowView: NSView {
    let grantButton = NSButton(title: "Grant", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let name: String
    private let grant: () -> Void

    init(title: String, explanation: String, grant: @escaping () -> Void) {
        name = title
        self.grant = grant
        super.init(frame: .zero)
        let copy = SettingsLayout.stack(spacing: 4)
        let heading = SettingsLayout.label(title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        SettingsLayout.add(heading, to: copy)
        SettingsLayout.add(SettingsLayout.label(explanation, size: 12, secondary: true), to: copy)
        copy.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        copy.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        grantButton.target = self
        grantButton.action = #selector(grantClicked)
        grantButton.bezelStyle = .rounded
        grantButton.setContentHuggingPriority(.required, for: .horizontal)
        grantButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = NSStackView(views: [statusLabel, copy, grantButton])
        row.distribution = .fill
        row.alignment = .top
        row.spacing = 10
        SettingsLayout.fill(row, in: self)
        setStatus(.missing)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setStatus(_ status: PermissionSnapshot.Status) {
        let text: String
        switch status {
        case .granted:
            statusLabel.stringValue = "✅"
            grantButton.title = "Granted"
            text = "Granted"
        case .missing:
            statusLabel.stringValue = "❌"
            grantButton.title = "Grant"
            text = "Not granted"
        case .notAsked:
            statusLabel.stringValue = "–"
            grantButton.title = "Allow"
            text = "Not asked yet"
        }
        statusLabel.setAccessibilityLabel("\(name): \(text)")
        grantButton.setAccessibilityLabel("\(grantButton.title) \(name)")
        grantButton.isEnabled = status != .granted
    }

    @objc private func grantClicked() { grant() }
}

final class SettingsPermissionsView: NSStackView {
    let accessibilityRow: PermissionRowView
    let screenRecordingRow: PermissionRowView
    let microphoneRow: PermissionRowView
    let calendarRow: PermissionRowView
    let notificationsRow: PermissionRowView
    let keyboardSettings = NSButton(title: "Open Keyboard Settings…", target: nil, action: nil)
    private let shortcutText = SettingsLayout.label("", size: 12)
    private let keyboardAction: () -> Void
    private let shortcutGroup: SettingsGlass
    private let shortcutHeading = SettingsLayout.heading("Screenshot shortcuts", symbol: "keyboard", color: .systemOrange)
    private let permissionGroup: SettingsGlass

    var rows: [(permission: MysliPermission, view: PermissionRowView)] {
        [(.accessibility, accessibilityRow), (.screenRecording, screenRecordingRow),
         (.microphone, microphoneRow), (.calendar, calendarRow), (.notifications, notificationsRow)]
    }

    var controls: [NSView] {
        rows.filter { !$0.view.isHidden }.map { $0.view.grantButton }
            + (shortcutGroup.isHidden ? [] : [keyboardSettings])
    }

    init(actions: PermissionActions) {
        accessibilityRow = PermissionRowView(title: "Accessibility", explanation: "Move windows and paste items from clipboard history.", grant: actions.accessibility)
        screenRecordingRow = PermissionRowView(title: "Screen Recording", explanation: "Take screenshots and record Mac audio for meeting notes. After you grant access, macOS may ask you to restart Mysli.", grant: actions.screenRecording)
        microphoneRow = PermissionRowView(title: "Microphone", explanation: "Record your voice for meeting notes.", grant: actions.microphone)
        calendarRow = PermissionRowView(title: "Calendar", explanation: "Read event titles and times for calendar reminders. Mysli never changes your calendar.", grant: actions.calendar)
        notificationsRow = PermissionRowView(title: "Notifications", explanation: "Show reminders when a calendar meeting starts or ends.", grant: actions.notifications)
        permissionGroup = SettingsLayout.group([accessibilityRow, screenRecordingRow, microphoneRow, calendarRow, notificationsRow])
        keyboardAction = actions.keyboardSettings
        shortcutGroup = SettingsLayout.group([shortcutText, keyboardSettings])
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 16
        SettingsLayout.add(SettingsLayout.page(title: "Permissions", subtitle: "Allow access for the features you use. Status updates while this page is open."), to: self)
        SettingsLayout.add(permissionGroup, to: self)
        SettingsLayout.add(SettingsLayout.label("Turn on more tools to see their permissions.", size: 12, secondary: true), to: self)
        SettingsLayout.add(shortcutHeading, to: self)
        SettingsLayout.add(shortcutGroup, to: self)
        SettingsLayout.add(SettingsLayout.label("Meeting audio stays on this Mac. To create a summary, Mysli sends the transcript and any selected background file to your chosen AI tool.", size: 12, secondary: true), to: self)
        keyboardSettings.bezelStyle = .rounded
        keyboardSettings.target = self
        keyboardSettings.action = #selector(openKeyboardSettings)
        render(.init(accessibility: false, screenRecording: false, microphone: .notDetermined,
                     calendar: .notDetermined, notifications: .notDetermined))
        showShortcutConflicts([])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func render(_ snapshot: PermissionSnapshot) {
        for row in rows { row.view.setStatus(snapshot.status(for: row.permission)) }
    }

    func showRequired(_ required: RequiredPermissions, screenshotShortcuts: Bool) {
        for row in rows {
            row.view.isHidden = !required.permissions.contains(row.permission)
        }
        permissionGroup.isHidden = required.permissions.isEmpty
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
