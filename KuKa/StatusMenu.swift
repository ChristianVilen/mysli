import Cocoa

/// Owns the status-bar menu: builds it, handles its actions (writing through
/// Settings), keeps checkmarks in step, and renders the status-item icon.
/// Serves as the menu's delegate, forwarding open/close to KeepAwakeController.
@MainActor
/// What the status icon's bottom-left warning corner shows. At most one, and
/// red beats orange: dead hotkeys are the more urgent state, and the menu
/// spells out the cause anyway.
enum StatusWarning {
    case hotkeysDead
    case screenRecordingMissing
}

final class StatusMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    var onTilingToggled: ((Bool) -> Void)?
    var onClipboardHistoryToggled: ((Bool) -> Void)?
    /// Fired when the user picks "Permissions…" — AppDelegate opens the
    /// onboarding window.
    var onShowPermissions: (() -> Void)?
    /// Fired every time the menu opens, before it is shown.
    var onMenuWillOpen: (() -> Void)?

    private let settings: Settings
    private let keepAwake: KeepAwakeController
    private var launchAtLoginItem: NSMenuItem!
    private var windowTilingItem: NSMenuItem!
    private var clipboardHistoryItem: NSMenuItem!
    private var durationItems: [NSMenuItem] = []
    private var hotkeyWarningItems: [NSMenuItem] = []

    init(settings: Settings, keepAwake: KeepAwakeController) {
        self.settings = settings
        self.keepAwake = keepAwake
        super.init()
        build()
    }

    /// The status-item image: the app icon, plus a small dot (with a light
    /// ring for contrast) per active state — Keep Awake gets the accent dot
    /// in the bottom-right, and `warning` gets the bottom-left corner.
    /// Separate corners so both can show at once.
    func icon(keepAwakeActive: Bool, warning: StatusWarning?) -> NSImage {
        guard let base = NSImage(named: "MenuBarIcon") else {
            return NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Ku-Ka") ?? NSImage()
        }
        let size = NSSize(width: 18, height: 18)

        guard keepAwakeActive || warning != nil else {
            let icon = (base.copy() as? NSImage) ?? base
            icon.size = size
            icon.isTemplate = false
            return icon
        }

        let badged = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            func drawDot(_ dot: NSRect, color: NSColor) {
                let ring = dot.insetBy(dx: -1.5, dy: -1.5)
                NSColor.white.setFill()
                NSBezierPath(ovalIn: ring).fill()
                color.setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
            if keepAwakeActive {
                drawDot(NSRect(x: rect.maxX - 8, y: rect.minY + 1, width: 7, height: 7), color: .controlAccentColor)
            }
            let corner = NSRect(x: rect.minX + 1, y: rect.minY + 1, width: 7, height: 7)
            switch warning {
            case .hotkeysDead: drawDot(corner, color: .systemRed)
            case .screenRecordingMissing: drawDot(corner, color: .systemOrange)
            case nil: break
            }
            return true
        }
        badged.isTemplate = false
        return badged
    }

    /// Show or clear the hotkey-health warning at the top of the menu: why
    /// hotkeys are dead, and the one thing the user can do about it. Rebuilt
    /// on every call, so a repeated state never duplicates and a changed
    /// cause replaces the old lines.
    func updateHotkeyHealth(_ health: HotkeyHealth) {
        for item in hotkeyWarningItems { menu.removeItem(item) }
        hotkeyWarningItems = []

        let title: String, remedy: String
        switch health {
        case .healthy:
            return
        case .noPermission:
            title = "⚠️ Hotkeys off — Accessibility permission missing"
            remedy = "Grant it under Permissions… below"
        case .tapDead:
            title = "⚠️ Hotkeys stopped working"
            remedy = "Quit and reopen Ku-Ka to fix"
        case .secureInputStuck(let holderName):
            title = "⚠️ Hotkeys blocked by \(holderName ?? "another app")"
            remedy = "Lock and unlock the screen to fix"
        }

        let warning = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        warning.isEnabled = false
        let hint = NSMenuItem(title: remedy, action: nil, keyEquivalent: "")
        hint.isEnabled = false
        hint.indentationLevel = 1

        hotkeyWarningItems = [warning, hint, .separator()]
        for (index, item) in hotkeyWarningItems.enumerated() {
            menu.insertItem(item, at: index)
        }
    }

    // MARK: - Build

    private func build() {
        let settingsLabel = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsLabel.isEnabled = false
        menu.addItem(settingsLabel)

        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = settings.launchAtLogin ? .on : .off
        menu.addItem(launchAtLoginItem)

        windowTilingItem = NSMenuItem(title: "Window Tiling", action: #selector(toggleWindowTiling), keyEquivalent: "")
        windowTilingItem.target = self
        windowTilingItem.state = settings.windowTilingEnabled ? .on : .off
        menu.addItem(windowTilingItem)

        clipboardHistoryItem = NSMenuItem(title: "Clipboard History", action: #selector(toggleClipboardHistory), keyEquivalent: "")
        clipboardHistoryItem.target = self
        clipboardHistoryItem.state = settings.clipboardHistoryEnabled ? .on : .off
        menu.addItem(clipboardHistoryItem)

        menu.addItem(.separator())

        let durationLabel = NSMenuItem(title: "Thumbnail Duration", action: nil, keyEquivalent: "")
        durationLabel.isEnabled = false
        menu.addItem(durationLabel)

        let currentDuration = settings.thumbnailDuration
        for (title, tag) in [("3 Seconds", 3), ("5 Seconds", 5), ("15 Seconds", 15), ("Forever", 0)] {
            let item = NSMenuItem(title: title, action: #selector(changeDuration(_:)), keyEquivalent: "")
            item.target = self
            item.tag = tag
            item.state = Double(tag) == currentDuration ? .on : .off
            menu.addItem(item)
            durationItems.append(item)
        }

        menu.addItem(.separator())

        // --- Keep Awake ---
        keepAwake.buildMenuSection(into: menu)

        menu.addItem(.separator())

        // --- Features ---
        let featuresLabel = NSMenuItem(title: "Features", action: nil, keyEquivalent: "")
        featuresLabel.isEnabled = false
        menu.addItem(featuresLabel)

        for feature in [
            "⌘⇧3 to capture full screen",
            "⌘⇧4 to capture selected area",
            "⌘⇧C to open clipboard history",
            "Multi-monitor support",
            "Auto-save to ~/Screenshots/",
            "Copy to clipboard",
            "Thumbnail preview & annotation"
        ] {
            let item = NSMenuItem(title: feature, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.indentationLevel = 1
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // --- Links ---
        let permissionsItem = NSMenuItem(title: "Permissions…", action: #selector(showPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        let reportBug = NSMenuItem(title: "Report a Bug…", action: #selector(openReportBug), keyEquivalent: "")
        reportBug.target = self
        menu.addItem(reportBug)

        let suggestFeature = NSMenuItem(title: "Suggest a Feature…", action: #selector(openSuggestFeature), keyEquivalent: "")
        suggestFeature.target = self
        menu.addItem(suggestFeature)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Ku-Ka", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        menu.delegate = self
    }

    // MARK: - Actions

    @objc private func changeDuration(_ sender: NSMenuItem) {
        settings.thumbnailDuration = Double(sender.tag)
        for item in durationItems { item.state = .off }
        sender.state = .on
    }

    @objc private func toggleWindowTiling() {
        let enabled = !settings.windowTilingEnabled
        settings.windowTilingEnabled = enabled
        windowTilingItem.state = enabled ? .on : .off
        onTilingToggled?(enabled)
    }

    @objc private func toggleClipboardHistory() {
        let enabled = !settings.clipboardHistoryEnabled
        settings.clipboardHistoryEnabled = enabled
        clipboardHistoryItem.state = enabled ? .on : .off
        onClipboardHistoryToggled?(enabled)
    }

    @objc private func toggleLaunchAtLogin() {
        settings.setLaunchAtLogin(!settings.launchAtLogin)
        launchAtLoginItem.state = settings.launchAtLogin ? .on : .off
    }

    @objc private func showPermissions() {
        onShowPermissions?()
    }

    @objc private func openReportBug() {
        NSWorkspace.shared.open(URL(string: "https://github.com/ChristianVilen/ku-ka/issues/new?labels=bug")!)
    }

    @objc private func openSuggestFeature() {
        NSWorkspace.shared.open(URL(string: "https://github.com/ChristianVilen/ku-ka/issues/new?labels=enhancement")!)
    }

    // MARK: - Menu delegate (keep-awake countdown updates)

    func menuWillOpen(_ menu: NSMenu) {
        onMenuWillOpen?()
        keepAwake.menuWillOpen()
    }

    func menuDidClose(_ menu: NSMenu) {
        keepAwake.menuDidClose()
    }
}
