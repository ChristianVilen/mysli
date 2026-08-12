import Cocoa

/// Owns the status-bar menu: builds it, handles its actions (writing through
/// Settings), keeps checkmarks in step, and renders the status-item icon.
/// Serves as the menu's delegate, forwarding open/close to KeepAwakeController.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    var onTilingToggled: ((Bool) -> Void)?

    private let settings: Settings
    private let keepAwake: KeepAwakeController
    private var launchAtLoginItem: NSMenuItem!
    private var windowTilingItem: NSMenuItem!
    private var durationItems: [NSMenuItem] = []

    init(settings: Settings, keepAwake: KeepAwakeController) {
        self.settings = settings
        self.keepAwake = keepAwake
        super.init()
        build()
    }

    /// The status-item image: the app icon, with an accent dot in the corner
    /// while a keep-awake session is active.
    func icon(keepAwakeActive: Bool) -> NSImage {
        guard let base = NSImage(named: "MenuBarIcon") else {
            return NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Ku-Ka") ?? NSImage()
        }
        let size = NSSize(width: 18, height: 18)

        guard keepAwakeActive else {
            let icon = (base.copy() as? NSImage) ?? base
            icon.size = size
            icon.isTemplate = false
            return icon
        }

        // Active: keep the normal icon and add a small accent dot (with a light
        // ring for contrast) in the bottom-right corner.
        let badged = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            let dot = NSRect(x: rect.maxX - 8, y: rect.minY + 1, width: 7, height: 7)
            let ring = dot.insetBy(dx: -1.5, dy: -1.5)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: ring).fill()
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        badged.isTemplate = false
        return badged
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

    @objc private func toggleLaunchAtLogin() {
        settings.setLaunchAtLogin(!settings.launchAtLogin)
        launchAtLoginItem.state = settings.launchAtLogin ? .on : .off
    }

    @objc private func openReportBug() {
        NSWorkspace.shared.open(URL(string: "https://github.com/ChristianVilen/ku-ka/issues/new?labels=bug")!)
    }

    @objc private func openSuggestFeature() {
        NSWorkspace.shared.open(URL(string: "https://github.com/ChristianVilen/ku-ka/issues/new?labels=enhancement")!)
    }

    // MARK: - Menu delegate (keep-awake countdown updates)

    func menuWillOpen(_ menu: NSMenu) {
        keepAwake.menuWillOpen()
    }

    func menuDidClose(_ menu: NSMenu) {
        keepAwake.menuDidClose()
    }
}
