import Cocoa

final class SettingsInstructionsView: NSStackView {
    static let shortcuts: [(title: String, shortcuts: [HotkeyShortcut])] = [
        ("Capture an area", [.captureArea]),
        ("Capture a screen", [.captureFullScreen]),
        ("Clipboard history", [.clipboardHistory]),
        ("Tile left or right", [.tileLeft, .tileRight]),
        ("Maximize or restore", [.maximize]),
        ("Center window", [.center])
    ]
    private(set) var guides: [(button: NSButton, body: NSTextField)] = []
    var guideButtons: [NSButton] { guides.map(\.button) }

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 14
        let intro = SettingsLayout.page(title: "Features & instructions", subtitle: "Capture, arrange, and keep track of your work.")
        SettingsLayout.add(intro, to: self)
        let example = SettingsLayout.stack(spacing: 6)
        SettingsLayout.add(SettingsLayout.label("Take your first screenshot", size: 15), to: example)
        SettingsLayout.add(SettingsLayout.label("Press Shift + Command + 4. Drag across the area you want, then release. Your screenshot is saved and copied. Click its thumbnail to draw on it.", secondary: true), to: example)
        SettingsLayout.add(SettingsLayout.group([example]), to: self)
        SettingsLayout.add(SettingsLayout.heading("Keyboard shortcuts", symbol: "keyboard", color: .systemPurple), to: self)
        let rows = Self.shortcuts.map { title, shortcuts in
            let key = Keycap(symbol: shortcuts.map(\.keycap.symbol).joined(separator: " / "),
                             name: shortcuts.map(\.keycap.name).joined(separator: " or "))
            let keycaps = shortcuts[0].modifierKeycaps + [key]
            let keys = NSStackView(views: keycaps.map(Self.keycapView))
            keys.spacing = 4
            keys.setAccessibilityElement(true)
            keys.setAccessibilityRole(.group)
            keys.setAccessibilityLabel(keycaps.map(\.name).joined(separator: " + "))
            return SettingsLayout.row(title, control: keys)
        }
        SettingsLayout.add(SettingsLayout.group(rows), to: self)
        SettingsLayout.add(SettingsLayout.heading("Feature guides", symbol: "book.closed.fill", color: .systemBlue), to: self)
        let guideTexts: [(String, String)] = [
            ("Screenshots and annotation", "Capture an area with Shift + Command + 4. Press Space before clicking to capture a window, or Escape to cancel. Shift + Command + 3 captures the screen under the pointer. Screenshots go to ~/Screenshots and the clipboard. Click a thumbnail to draw in red. Use Undo to remove a stroke. Click Crop and drag a box; move it or resize it with its handles. Click Crop again to return to drawing. Done saves the drawing and crop. The trash button removes the saved screenshot and clears its clipboard entry."),
            ("Combining screenshots", "Take two or more screenshots while their thumbnails are visible. Click Combine between two adjacent thumbnails to join those screenshots. Up to five thumbnails stay in the stack. A single thumbnail follows the duration in Settings."),
            ("Window tiling", "Use Control + Option + Left or Right Arrow to fill half a display. Repeat the same shortcut to move to the next display, with wrapping. Control + Option + Return maximizes the window; press it again to restore its previous frame. Control + Option + C centers the window without changing its size. A maximized window stays in place. Turn Window tiling off in Settings to release these shortcuts."),
            ("Clipboard history", "Press Shift + Command + C. Type to filter recent copies, use the arrow keys to select an item, and press Return to paste. For rich text, choose whether to keep formatting; paste without formatting is selected first. Escape goes back or closes the panel. History stays in memory until you quit. Turning Clipboard history off in Settings clears it and releases its shortcut. Password-manager items marked as concealed or transient are not recorded."),
            ("Keep Awake", "Open the Ku-Ka menu and choose 30m, 1h, 2h, or 4h. Choose ∞ to keep the session on until you turn it off. Choose Turn Off to end the session. Turn on Keep screen on in the same menu to prevent the display from sleeping while the session runs. Closing the lid still sleeps your Mac."),
            ("Meeting notes", "Choose Start Recording Meeting in the menu. Allow Microphone and Screen Recording access when asked. The microphone records Me; Mac audio records Them. Use Pause, Resume, and Stop on the floating controls. The live draft stays in memory. After Stop, Ku-Ka transcribes on this Mac and sends the transcript to the summary tool. The complete optional background file goes too; Automatic may use both providers. Find transcript.md and summary.md in the dated meeting folder. Audio goes to the Trash after transcription. Check Words lets you correct suspect words; Update Notes rebuilds the transcript and summary from the heard copy and replaces transcript edits. With Calendar reminders on, a calendar event offers to start and stop recording; Ku-Ka never records on its own. Teams speaker names is experimental and can name remote speakers after Stop."),
            ("Permissions and shortcut setup", "Choose Permissions… in the Ku-Ka menu to check access. Accessibility allows window tiling and paste; Screen Recording allows screenshots and Mac audio. Microphone is needed only for meetings. Grant access in System Settings. If macOS already uses the screenshot shortcuts, follow Ku-Ka's shortcut setup instructions to turn those system shortcuts off. Registration warnings appear in the Ku-Ka menu. You can use this window without these permissions.")
        ]
        let sections = guideTexts.map { title, text in
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
        SettingsLayout.add(SettingsLayout.group(sections), to: self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

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

    @objc private func toggleGuide(_ sender: NSButton) {
        guard let body = guides.first(where: { $0.button === sender })?.body else { return }
        let expanded = sender.state == .on
        body.isHidden = !expanded
        sender.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
        sender.setAccessibilityExpanded(expanded)
    }
}
