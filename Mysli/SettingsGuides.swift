import Cocoa

/// The guides at the bottom of a page. Each title opens and closes its text.
@MainActor
final class SettingsGuides: NSObject {
    private(set) var view = NSView()
    private(set) var guides: [(button: NSButton, body: NSTextField)] = []
    var buttons: [NSButton] { guides.map(\.button) }

    init(_ texts: [(title: String, text: String)]) {
        super.init()
        let sections = texts.map { title, text in
            let button = NSButton(title: title, target: self, action: #selector(toggleGuide(_:)))
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .accessoryBarAction
            button.isBordered = false
            button.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.alignment = .left
            button.setAccessibilityLabel(title)
            button.setAccessibilityRole(.disclosureTriangle)
            button.setAccessibilityExpanded(false)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
            let body = SettingsLayout.label(text, size: 12, secondary: true)
            body.isHidden = true
            let section = SettingsLayout.stack(spacing: 8)
            SettingsLayout.add(button, to: section)
            SettingsLayout.add(body, to: section)
            guides.append((button, body))
            return section as NSView
        }
        view = SettingsLayout.group(sections)
    }

    @objc private func toggleGuide(_ sender: NSButton) {
        guard let body = guides.first(where: { $0.button === sender })?.body else { return }
        let expanded = sender.state == .on
        body.isHidden = !expanded
        sender.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
        sender.setAccessibilityExpanded(expanded)
    }
}

/// The shortcut rows of a page, with one keycap for each key.
@MainActor
enum SettingsShortcuts {
    static func group(_ rows: [(title: String, shortcuts: [HotkeyShortcut])]) -> NSView {
        SettingsLayout.group(rows.map { title, shortcuts in
            let key = Keycap(symbol: shortcuts.map(\.keycap.symbol).joined(separator: " / "),
                             name: shortcuts.map(\.keycap.name).joined(separator: " or "))
            let keycaps = shortcuts[0].modifierKeycaps + [key]
            let keys = NSStackView(views: keycaps.map(keycapView))
            keys.spacing = 4
            keys.setAccessibilityElement(true)
            keys.setAccessibilityRole(.group)
            keys.setAccessibilityLabel(keycaps.map(\.name).joined(separator: " + "))
            return SettingsLayout.row(title, control: keys)
        })
    }

    private static func keycapView(_ keycap: Keycap) -> NSView {
        let cap = NSTextField(labelWithString: " \(keycap.symbol) ")
        cap.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = 0.5
        box.cornerRadius = 4
        box.borderColor = .separatorColor
        box.fillColor = .controlBackgroundColor
        box.contentViewMargins = NSSize(width: 4, height: 3)
        box.contentView = cap
        box.widthAnchor.constraint(equalToConstant: max(26, cap.intrinsicContentSize.width + 8)).isActive = true
        box.heightAnchor.constraint(equalToConstant: 26).isActive = true
        box.setAccessibilityElement(true)
        box.setAccessibilityRole(.staticText)
        box.setAccessibilityLabel(keycap.name)
        return box
    }
}
