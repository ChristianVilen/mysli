import Cocoa

struct PermissionSnapshot: Equatable {
    let accessibility: Bool
    let screenRecording: Bool
    let microphone: MicrophoneAccess
}

struct PermissionActions {
    let accessibility: () -> Void
    let screenRecording: () -> Void
    let microphone: () -> Void
    let keyboardSettings: () -> Void

    static let inert = Self(accessibility: {}, screenRecording: {}, microphone: {}, keyboardSettings: {})
}

final class PermissionRowView: NSView {
    enum Status { case granted, missing, notAsked }

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
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        grantButton.target = self
        grantButton.action = #selector(grantClicked)
        grantButton.bezelStyle = .rounded
        grantButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = NSStackView(views: [statusLabel, copy, grantButton])
        row.alignment = .top
        row.spacing = 10
        SettingsLayout.fill(row, in: self)
        setStatus(.missing)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setStatus(_ status: Status) {
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
    let keyboardSettings = NSButton(title: "Open Keyboard Settings…", target: nil, action: nil)
    private let shortcutText = SettingsLayout.label("", size: 12)
    private let keyboardAction: () -> Void
    private let shortcutGroup: SettingsGlass

    var controls: [NSView] {
        [accessibilityRow.grantButton, screenRecordingRow.grantButton, microphoneRow.grantButton, keyboardSettings]
    }

    init(actions: PermissionActions) {
        accessibilityRow = PermissionRowView(title: "Accessibility", explanation: "Move windows and paste items from clipboard history.", grant: actions.accessibility)
        screenRecordingRow = PermissionRowView(title: "Screen Recording", explanation: "Take screenshots and record Mac audio for meeting notes. After you grant access, macOS may ask you to restart Ku-Ka.", grant: actions.screenRecording)
        microphoneRow = PermissionRowView(title: "Microphone", explanation: "Record your voice for meeting notes. This permission is optional until you record a meeting.", grant: actions.microphone)
        keyboardAction = actions.keyboardSettings
        shortcutGroup = SettingsLayout.group([shortcutText, keyboardSettings])
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 16
        SettingsLayout.add(SettingsLayout.page(title: "Permissions", subtitle: "Allow access for the features you use. Status updates while this page is open."), to: self)
        SettingsLayout.add(SettingsLayout.group([accessibilityRow, screenRecordingRow, microphoneRow]), to: self)
        SettingsLayout.add(SettingsLayout.heading("Screenshot shortcuts", symbol: "keyboard", color: .systemOrange), to: self)
        SettingsLayout.add(shortcutGroup, to: self)
        SettingsLayout.add(SettingsLayout.label("Meeting audio stays on this Mac. To create a summary, Ku-Ka sends the transcript and any selected background file to your chosen AI tool.", size: 12, secondary: true), to: self)
        keyboardSettings.bezelStyle = .rounded
        keyboardSettings.target = self
        keyboardSettings.action = #selector(openKeyboardSettings)
        render(.init(accessibility: false, screenRecording: false, microphone: .notDetermined))
        showShortcutConflicts([])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func render(_ snapshot: PermissionSnapshot) {
        accessibilityRow.setStatus(snapshot.accessibility ? .granted : .missing)
        screenRecordingRow.setStatus(snapshot.screenRecording ? .granted : .missing)
        switch snapshot.microphone {
        case .granted: microphoneRow.setStatus(.granted)
        case .denied: microphoneRow.setStatus(.missing)
        case .notDetermined: microphoneRow.setStatus(.notAsked)
        }
    }

    func showShortcutConflicts(_ shortcuts: [HotkeyShortcut]) {
        let choices = shortcuts.isEmpty ? [.captureFullScreen, .captureArea] : shortcuts
        let labels = choices.map { shortcut in
            let setting = shortcut == .captureFullScreen
                ? "Save picture of screen as a file" : "Save picture of selected area as a file"
            return "\(shortcut.label)\n\(setting)"
        }.joined(separator: "\n\n")
        let introduction = shortcuts.isEmpty
            ? "Ku-Ka uses the same screenshot shortcuts as macOS. If a shortcut is unavailable, open Keyboard Settings > Keyboard Shortcuts > Screenshots and turn off the matching macOS shortcut."
            : "macOS is using these shortcuts. Open Keyboard Settings > Keyboard Shortcuts > Screenshots and turn off the matching macOS shortcuts."
        shortcutText.stringValue = "\(introduction)\n\n\(labels)\n\nKu-Ka retries automatically. If you quit Ku-Ka, turn these shortcuts back on to use the macOS screenshot tool."
    }

    func revealShortcutSetup() {
        layoutSubtreeIfNeeded()
        scrollToVisible(shortcutGroup.frame)
    }

    @objc private func openKeyboardSettings() { keyboardAction() }
}
