import Cocoa

/// The menu gives the details behind the status icon's warning dot.
enum StatusWarning {
    case shortcutsUnavailable
    case screenRecordingMissing
}

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    var onTilingToggled: ((Bool) -> Void)?
    var onClipboardHistoryToggled: ((Bool) -> Void)?
    /// Fired when the user picks "Permissions…" — AppDelegate opens the
    /// onboarding window.
    var onShowPermissions: (() -> Void)?
    var onOpenKeyboardSettings: (() -> Void)?
    /// Fired every time the menu opens, before it is shown.
    var onMenuWillOpen: (() -> Void)?

    private let settings: Settings
    private let keepAwake: KeepAwakeController
    private var launchAtLoginItem: NSMenuItem!
    private var windowTilingItem: NSMenuItem!
    private var clipboardHistoryItem: NSMenuItem!
    private var durationItems: [NSMenuItem] = []
    private var hotkeyWarningItems: [NSMenuItem] = []
    private var renderedHealth: HotkeyHealth?

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
            case .shortcutsUnavailable: drawDot(corner, color: .systemRed)
            case .screenRecordingMissing: drawDot(corner, color: .systemOrange)
            case nil: break
            }
            return true
        }
        badged.isTemplate = false
        return badged
    }

    /// Rebuild warnings so recovery removes only the resolved problems.
    func updateHotkeyHealth(_ health: HotkeyHealth) {
        guard health != renderedHealth else { return }
        renderedHealth = health
        for item in hotkeyWarningItems { menu.removeItem(item) }
        hotkeyWarningItems = []

        func addLine(_ title: String, indented: Bool = false) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.indentationLevel = indented ? 1 : 0
            hotkeyWarningItems.append(item)
        }
        if health.accessibilityMissing {
            addLine("⚠️ Window tiling and paste need Accessibility permission")
            addLine("Grant it under Permissions… below", indented: true)
        }
        for issue in health.issues {
            switch issue.failure {
            case .systemConflict:
                addLine("⚠️ \(issue.shortcut.label) is used by macOS")
            case .systemLookupFailed:
                addLine("⚠️ \(issue.shortcut.label) could not be checked")
            case .registrationFailed:
                addLine("⚠️ \(issue.shortcut.label) could not be registered")
            case .releaseFailed:
                addLine("⚠️ \(issue.shortcut.label) could not be released")
            }
        }
        let conflicts = health.issues.filter { $0.failure == .systemConflict }
        if !conflicts.isEmpty {
            addLine("Keyboard Settings → Keyboard Shortcuts", indented: true)
            if conflicts.contains(where: { $0.shortcut.isScreenshot }) {
                addLine("In Screenshots, turn off the matching macOS shortcut", indented: true)
            }
            if conflicts.contains(where: { !$0.shortcut.isScreenshot }) {
                addLine("Turn off or change the matching macOS shortcut", indented: true)
            }
            let settings = NSMenuItem(title: "Open Keyboard Settings…", action: #selector(openKeyboardSettings), keyEquivalent: "")
            settings.target = self
            hotkeyWarningItems.append(settings)
        }
        if health.issues.contains(where: { $0.failure != .systemConflict }) {
            addLine("Ku-Ka will retry automatically", indented: true)
        }
        guard !hotkeyWarningItems.isEmpty else { return }
        hotkeyWarningItems.append(.separator())
        for (index, item) in hotkeyWarningItems.enumerated() {
            menu.insertItem(item, at: index)
        }
    }

    // MARK: - Build

    @objc private func openKeyboardSettings() { onOpenKeyboardSettings?() }

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
