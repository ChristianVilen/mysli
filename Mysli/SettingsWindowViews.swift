import Cocoa

/// The pages of the Mysli window: General, one page for each tool, then Permissions and Help.
enum SettingsPage: Int, CaseIterable {
    case general, screenshots, clipboard, windows, keepAwake, meetings, dictation, permissions, help

    var tool: MysliTool? {
        switch self {
        case .screenshots: .screenshots
        case .clipboard: .clipboard
        case .windows: .windows
        case .keepAwake: .keepAwake
        case .meetings: .meetings
        case .dictation: .dictation
        case .general, .permissions, .help: nil
        }
    }

    var title: String {
        switch self {
        case .general: "General"
        case .permissions: "Permissions"
        case .help: "Help"
        default: tool?.title ?? ""
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Start Mysli with your Mac. Changes save automatically."
        case .screenshots: "Capture an area or the screen, then draw, crop, or combine."
        case .clipboard: "Find and paste what you copied before."
        case .windows: "Move the active window with the keyboard."
        case .keepAwake: "Keep your Mac awake while a long task runs."
        case .meetings: "Record a call. Mysli writes a transcript and a summary on this Mac."
        case .dictation: "Hold a key, speak, then release to paste."
        case .permissions, .help: ""
        }
    }

    func icon(size: CGFloat) -> NSImage {
        if let tool { return tool.icon(size: size) }
        let symbol = switch self {
        case .permissions: "lock.fill"
        case .help: "questionmark"
        default: "gearshape.fill"
        }
        return MysliTool.neutralIcon(symbolName: symbol, size: size, description: title)
    }

    var shortcuts: [(title: String, shortcuts: [HotkeyShortcut])] {
        switch self {
        case .screenshots: [("Capture an area", [.captureArea]), ("Capture the screen under the pointer", [.captureFullScreen])]
        case .clipboard: [("Open clipboard history", [.clipboardHistory])]
        case .windows: [("Tile left or right", [.tileLeft, .tileRight]), ("Maximize or restore", [.maximize]), ("Center window", [.center])]
        case .dictation: [("Alternative dictation key", [.dictation]), ("Cancel dictation", [.dictationEscape])]
        default: []
        }
    }

    var guides: [(title: String, text: String)] {
        switch self {
        case .screenshots: [
            ("Screenshots and annotation", "Capture an area with Shift + Command + 4. Press Space before clicking to capture a window, or Escape to cancel. Shift + Command + 3 captures the screen under the pointer. Screenshots go to ~/Screenshots and the clipboard. Click a thumbnail to draw in red. Use Undo to remove a stroke. Click Crop and drag a box; move it or resize it with its handles. Click Crop again to return to drawing. Done saves the drawing and crop. The trash button removes the saved screenshot and clears its clipboard entry."),
            ("Combining screenshots", "Take two or more screenshots while their thumbnails are visible. Click Combine between two adjacent thumbnails to join those screenshots. Up to five thumbnails stay in the stack. A single thumbnail follows the duration above.")
        ]
        case .windows: [
            ("Window tiling", "Use Control + Option + Left or Right Arrow to fill half a display. Repeat the same shortcut to move to the next display, with wrapping. Control + Option + Return maximizes the window; press it again to restore its previous frame. Control + Option + C centers the window without changing its size. A maximized window stays in place. Turn Window tiling off above to release these shortcuts.")
        ]
        case .clipboard: [
            ("Clipboard history", "Press Shift + Command + C. Type to filter recent copies, use the arrow keys to select an item, and press Return to paste. For rich text, choose whether to keep formatting; paste without formatting is selected first. Escape goes back or closes the panel. History stays in memory until you quit. Turning Clipboard history off above clears it and releases its shortcut. Password-manager items marked as concealed or transient are not recorded.")
        ]
        case .keepAwake: [
            ("Keep Awake", "Open the Mysli menu and choose 30m, 1h, 2h, or 4h. Choose ∞ to keep the session on until you turn it off. Choose Turn Off to end the session. Keep screen on, here or in the menu, prevents the display from sleeping while the session runs. Closing the lid still sleeps your Mac.")
        ]
        case .meetings: [
            ("Meeting notes", "Choose Start Recording Meeting in the menu. Allow Microphone and Screen Recording access when asked. The microphone records Me; Mac audio records Them. Use Pause, Resume, and Stop on the floating controls. The live draft stays in memory. The pencil button opens a separate notes window. Typed notes save to notes.md and remain editable while paused and after Stop. Recent Meeting Notes reopens them. Update summary includes later edits without changing the transcript or word review. Save errors keep your draft; Retry save tries again. After Stop, Mysli transcribes on this Mac and sends the transcript and saved typed notes to the summary tool. The complete optional background file goes too; Automatic may use both providers. Find transcript.md and summary.md in the dated meeting folder. Audio goes to the Trash after transcription. Check Words lets you correct suspect words; Update Notes rebuilds the transcript and summary from the heard copy and replaces transcript edits. With Calendar reminders on, a calendar event offers to start and stop recording; Mysli never records on its own. Teams speaker names is experimental and can name remote speakers after Stop.")
        ]
        case .permissions: [
            ("Permissions and shortcut setup", "Accessibility allows window tiling and paste; Screen Recording allows screenshots and Mac audio. Microphone is needed for meetings and dictation. Fn dictation also needs Input Monitoring. Grant access in System Settings. If macOS already uses the screenshot shortcuts, follow Mysli's shortcut setup instructions to turn those system shortcuts off. Registration warnings appear in the Mysli menu. You can use this window without these permissions.")
        ]
        case .dictation: [
            ("Dictate and paste", "Hold Fn or Control + Option + D for at least 0.3 seconds. Release to transcribe and polish the words with Claude Haiku. Escape cancels. A hold stops after two minutes. A triangle means local text was pasted without Claude polish; a cross means an error. Paste last dictation again in the menu uses the last text in memory. Dictation never sends Return. During a meeting, the meeting microphone also records your dictated words.")
        ]
        case .general, .help: []
        }
    }
}

struct SettingsDisplayOptions {
    var reduceTransparency: Bool
    var increaseContrast: Bool

    static var current: Self {
        Self(reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
             increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
    }
}

final class SettingsBackground: NSView {
    private let effect = NSVisualEffectView()
    private var options = SettingsDisplayOptions.current

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        SettingsLayout.fill(effect, in: self)
        apply(options)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(_ options: SettingsDisplayOptions) {
        self.options = options
        effect.isHidden = options.reduceTransparency
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = options.reduceTransparency ? NSColor.windowBackgroundColor.cgColor : nil
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        apply(options)
    }
}

final class SettingsGlass: NSView {
    let content = NSView()
    private let glass = NSGlassEffectView()
    private var options = SettingsDisplayOptions.current

    init(radius: CGFloat = 14) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = radius
        glass.style = .regular
        glass.cornerRadius = radius
        SettingsLayout.fill(glass, in: self)
        apply(options)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(_ options: SettingsDisplayOptions) {
        self.options = options
        glass.isHidden = options.reduceTransparency
        let parent: NSView = options.reduceTransparency ? self : glass
        if content.superview !== parent {
            glass.contentView = nil
            content.removeFromSuperview()
            if options.reduceTransparency { addSubview(content) } else { glass.contentView = content }
            content.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
                content.topAnchor.constraint(equalTo: parent.topAnchor),
                content.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
            ])
        }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = options.reduceTransparency ? NSColor.controlBackgroundColor.cgColor : nil
            layer?.borderWidth = options.increaseContrast ? 1.5 : 0.5
            layer?.borderColor = (options.increaseContrast ? NSColor.labelColor : NSColor.labelColor.withAlphaComponent(0.12)).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        apply(options)
    }
}

enum SettingsLayout {
    static func stack(_ views: [NSView] = [], spacing: CGFloat = 12) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    static func label(_ text: String, size: CGFloat = 13, secondary: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        return label
    }

    static func fill(_ child: NSView, in parent: NSView, inset: CGFloat = 0) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
        ])
    }

    static func add(_ child: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(child)
        child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    static func row(_ title: String, detail: String? = nil, control: NSView) -> NSView {
        let copy = stack(spacing: 4)
        let heading = label(title)
        add(heading, to: copy)
        if let detail { add(label(detail, size: 11, secondary: true), to: copy) }
        copy.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        copy.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let row = NSView()
        for child in [copy, control] {
            child.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(child)
        }
        NSLayoutConstraint.activate([
            copy.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            copy.topAnchor.constraint(equalTo: row.topAnchor, constant: 4),
            copy.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -4),
            copy.trailingAnchor.constraint(equalTo: control.leadingAnchor, constant: -12),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            control.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor),
            control.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor)
        ])
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        (control as? NSStackView)?.setHuggingPriority(.required, for: .horizontal)
        return row
    }

    static func group(_ rows: [NSView]) -> SettingsGlass {
        let glass = SettingsGlass()
        let stack = stack(spacing: 6)
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = NSBox()
                separator.boxType = .separator
                add(separator, to: stack)
            }
            add(row, to: stack)
        }
        fill(stack, in: glass.content, inset: 14)
        return glass
    }

    static func heading(_ title: String, symbol: String, color: NSColor) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        icon.contentTintColor = .white
        icon.wantsLayer = true
        icon.layer?.backgroundColor = color.cgColor
        icon.layer?.cornerRadius = 7
        icon.imageScaling = .scaleProportionallyDown
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let title = label(title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let row = NSStackView(views: [icon, title])
        row.spacing = 9
        row.alignment = .centerY
        return row
    }

    static func sectionTitle(_ text: String) -> NSTextField {
        let title = label(text, secondary: true)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        return title
    }

    static func page(title: String, subtitle: String) -> NSStackView {
        let stack = stack(spacing: 8)
        let heading = label(title, size: 28)
        heading.font = .systemFont(ofSize: 28, weight: .bold)
        add(heading, to: stack)
        add(label(subtitle, secondary: true), to: stack)
        return stack
    }

    static func scroll(_ page: NSView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let document = SettingsDocument()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        fill(page, in: document, inset: 20)
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        return scroll
    }
}

private final class SettingsDocument: NSView {
    override var isFlipped: Bool { true }
}
