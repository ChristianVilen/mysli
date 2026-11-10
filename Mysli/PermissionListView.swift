import Cocoa

struct PermissionActions {
    let accessibility: () -> Void
    let screenRecording: () -> Void
    let microphone: () -> Void
    let calendar: () -> Void
    let notifications: () -> Void
    let keyboardSettings: () -> Void
    var inputMonitoring: () -> Void = {}

    static let inert = Self(accessibility: {}, screenRecording: {}, microphone: {}, calendar: {}, notifications: {}, keyboardSettings: {})
}

final class PermissionRowView: NSView {
    let grantButton = NSButton(title: "Grant", target: nil, action: nil)
    private let statusIcon = NSImageView()
    private let name: String
    private let grant: () -> Void
    private var shownStatus: PermissionSnapshot.Status?

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
        statusIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        statusIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        grantButton.target = self
        grantButton.action = #selector(grantClicked)
        grantButton.bezelStyle = .rounded
        grantButton.setContentHuggingPriority(.required, for: .horizontal)
        grantButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        grantButton.widthAnchor.constraint(equalToConstant: 84).isActive = true
        let row = NSView()
        for child in [statusIcon, copy, grantButton] {
            child.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(child)
        }
        NSLayoutConstraint.activate([
            statusIcon.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            statusIcon.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            copy.leadingAnchor.constraint(equalTo: statusIcon.trailingAnchor, constant: 12),
            copy.topAnchor.constraint(equalTo: row.topAnchor, constant: 4),
            copy.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -4),
            copy.trailingAnchor.constraint(equalTo: grantButton.leadingAnchor, constant: -16),
            grantButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            grantButton.firstBaselineAnchor.constraint(equalTo: heading.firstBaselineAnchor)
        ])
        SettingsLayout.fill(row, in: self)
        setStatus(.missing)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setStatus(_ status: PermissionSnapshot.Status) {
        guard status != shownStatus else { return }
        shownStatus = status
        let text: String
        let symbol: String
        switch status {
        case .granted:
            symbol = "checkmark.circle.fill"
            statusIcon.contentTintColor = .systemGreen
            grantButton.title = "Allowed"
            text = "Allowed"
        case .missing:
            symbol = "xmark.circle"
            statusIcon.contentTintColor = .systemRed
            grantButton.title = "Grant"
            text = "Not granted"
        case .notAsked:
            symbol = "minus.circle"
            statusIcon.contentTintColor = .secondaryLabelColor
            grantButton.title = "Allow"
            text = "Not asked yet"
        }
        statusIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "\(name): \(text)")
        grantButton.setAccessibilityLabel("\(grantButton.title) \(name)")
        grantButton.isEnabled = status != .granted
    }

    @objc private func grantClicked() { grant() }
}

@MainActor
final class PermissionListView: NSView {
    let rows: [(permission: MysliPermission, view: PermissionRowView)]
    var controls: [NSButton] { rows.filter { !$0.view.isHidden }.map { $0.view.grantButton } }

    init(actions: PermissionActions, spacing: CGFloat = 8, inset: CGFloat = 14) {
        rows = MysliPermission.allCases.map { permission in
            let grant: () -> Void = switch permission {
            case .accessibility: actions.accessibility
            case .screenRecording: actions.screenRecording
            case .microphone: actions.microphone
            case .calendar: actions.calendar
            case .notifications: actions.notifications
            case .inputMonitoring: actions.inputMonitoring
            }
            return (permission, PermissionRowView(title: permission.title, explanation: permission.explanation, grant: grant))
        }
        super.init(frame: .zero)
        let glass = SettingsGlass()
        let stack = SettingsLayout.stack(spacing: spacing)
        for row in rows { SettingsLayout.add(row.view, to: stack) }
        SettingsLayout.fill(stack, in: glass.content, inset: inset)
        SettingsLayout.fill(glass, in: self)
        render(.init(accessibility: false, screenRecording: false, microphone: .notDetermined,
                     calendar: .notDetermined, notifications: .notDetermined))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func showRequired(_ required: RequiredPermissions) {
        for row in rows { row.view.isHidden = !required.permissions.contains(row.permission) }
        isHidden = required.permissions.isEmpty
    }

    func render(_ snapshot: PermissionSnapshot) {
        for row in rows { row.view.setStatus(snapshot.status(for: row.permission)) }
    }
}
