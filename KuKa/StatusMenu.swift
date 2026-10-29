import Cocoa

/// The menu gives the details behind the status icon's warning dot.
enum StatusWarning {
    case shortcutsUnavailable
    case screenRecordingMissing
}

enum RecordingMark {
    case recording
    case paused
}

/// A feature's own group of menu items, ending with its own separator.
@MainActor
protocol MenuSection: AnyObject {
    func buildMenuSection(into menu: NSMenu)
    func menuWillOpen()
    /// Called once a second while the menu is open, so keep it cheap.
    func menuTick()
    func menuDidClose()
}

extension MenuSection {
    func menuDidClose() {}
}

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    var onTilingToggled: ((Bool) -> Void)?
    var onClipboardHistoryToggled: ((Bool) -> Void)?
    var onShowPermissions: (() -> Void)?
    var onOpenKeyboardSettings: (() -> Void)?
    /// Fired every time the menu opens, before it is shown.
    var onMenuWillOpen: (() -> Void)?

    private let settings: Settings
    private let sections: [MenuSection]
    private let onTrackingChange: (Bool) -> Void
    private var refreshTimer: Timer?
    private var launchAtLoginItem: NSMenuItem!
    private var windowTilingItem: NSMenuItem!
    private var clipboardHistoryItem: NSMenuItem!
    private var durationItems: [NSMenuItem] = []
    private var hotkeyWarningItems: [NSMenuItem] = []
    private var renderedHealth: HotkeyHealth?

    init(settings: Settings, sections: [MenuSection], onTrackingChange: @escaping (Bool) -> Void = { _ in }) {
        self.settings = settings
        self.sections = sections
        self.onTrackingChange = onTrackingChange
        super.init()
        build()
    }

    /// Separate corners let all three marks show at once. Recording and pause also have
    /// different shapes, so the state does not rely on colour alone.
    func icon(keepAwakeActive: Bool, recording: RecordingMark?, warning: StatusWarning?) -> NSImage {
        guard let base = NSImage(named: "MenuBarIcon") else {
            return NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Ku-Ka") ?? NSImage()
        }
        let size = NSSize(width: 18, height: 18)

        guard keepAwakeActive || recording != nil || warning != nil else {
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
            if let recording {
                let mark = NSRect(x: rect.maxX - 8, y: rect.maxY - 8, width: 7, height: 7)
                drawDot(mark, color: .systemRed)
                NSColor.white.setFill()
                switch recording {
                case .recording:
                    NSBezierPath(ovalIn: mark.insetBy(dx: 2.25, dy: 2.25)).fill()
                case .paused:
                    let bar = NSRect(x: mark.minX + 2, y: mark.minY + 1.75, width: 1, height: 3.5)
                    NSBezierPath(rect: bar).fill()
                    NSBezierPath(rect: bar.offsetBy(dx: 2, dy: 0)).fill()
                }
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

        for section in sections {
            section.buildMenuSection(into: menu)
        }

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
            "Thumbnail preview & annotation",
            "Meeting transcripts and summaries"
        ] {
            let item = NSMenuItem(title: feature, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.indentationLevel = 1
            menu.addItem(item)
        }

        menu.addItem(.separator())

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

    func menuWillOpen(_ menu: NSMenu) {
        onTrackingChange(true)
        onMenuWillOpen?()
        for section in sections { section.menuWillOpen() }
        refreshTimer?.invalidate()
        // .common mode: menu tracking runs the run loop in a mode where
        // default-mode timers do not fire.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                for section in self?.sections ?? [] { section.menuTick() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        for section in sections { section.menuDidClose() }
        onTrackingChange(false)
    }
}
