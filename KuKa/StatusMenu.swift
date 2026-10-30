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
    var onShowSettings: (() -> Void)?
    var onShowKuKa: (() -> Void)?
    var onShowPermissions: (() -> Void)?
    var onOpenKeyboardSettings: (() -> Void)?
    /// Fired every time the menu opens, before it is shown.
    var onMenuWillOpen: (() -> Void)?

    private let sections: [MenuSection]
    private var refreshTimer: Timer?
    private var hotkeyWarningItems: [NSMenuItem] = []
    private var renderedHealth: HotkeyHealth?

    init(sections: [MenuSection]) {
        self.sections = sections
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

    /// The menu bar while an ordinary window makes Ku-Ka a regular app. Without these items,
    /// Command-W, Command-Q, and copy and paste do nothing in Ku-Ka's windows.
    func applicationMenu() -> NSMenu {
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        let menus: [(title: String, items: [NSMenuItem])] = [
            ("Ku-Ka", [settingsItem(), .separator(),
                       NSMenuItem(title: "Quit Ku-Ka", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")]),
            ("File", [NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")]),
            ("Edit", [NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"), redo, .separator(),
                      NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
                      NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
                      NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
                      NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")])
        ]
        let mainMenu = NSMenu()
        for (title, items) in menus {
            let submenu = NSMenu(title: title)
            items.forEach(submenu.addItem)
            mainMenu.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = submenu
        }
        return mainMenu
    }

    private func settingsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        item.target = self
        return item
    }

    private func build() {
        let kuKa = NSMenuItem(title: "Ku-Ka…", action: #selector(showKuKa), keyEquivalent: "")
        kuKa.target = self
        menu.addItem(kuKa)
        menu.addItem(.separator())

        for section in sections {
            section.buildMenuSection(into: menu)
        }

        let permissionsItem = NSMenuItem(title: "Permissions…", action: #selector(showPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Ku-Ka", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        menu.delegate = self
    }

    @objc private func showSettings() { onShowSettings?() }
    @objc private func showKuKa() { onShowKuKa?() }

    @objc private func showPermissions() {
        onShowPermissions?()
    }

    func menuWillOpen(_ menu: NSMenu) {
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
    }
}
