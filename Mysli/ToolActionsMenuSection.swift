import Cocoa

/// The menu groups of the tools that otherwise work only through their shortcuts.
@MainActor
final class ToolActionsMenuSection: NSObject, NSMenuItemValidation, MenuSection {
    var onCaptureArea: (() -> Void)?
    var onCaptureScreen: (() -> Void)?
    var onShowClipboardHistory: (() -> Void)?
    var onToolChanged: ((MysliTool, Bool) -> Void)?

    private let screenshotsOn: () -> Bool
    private let clipboardOn: () -> Bool
    private let tilingOn: () -> Bool
    private var groups: [(isEnabled: () -> Bool, items: [NSMenuItem])] = []
    private let captureAreaItem = NSMenuItem(title: "Capture Area", action: #selector(captureArea), keyEquivalent: "")
    private let captureScreenItem = NSMenuItem(title: "Capture Screen", action: #selector(captureScreen), keyEquivalent: "")
    private let clipboardItem = NSMenuItem(title: "Show Clipboard History", action: #selector(showClipboardHistory), keyEquivalent: "")
    private let tilingItem = NSMenuItem(title: "Window Tiling", action: #selector(toggleTiling), keyEquivalent: "")

    init(screenshotsOn: @escaping () -> Bool, clipboardOn: @escaping () -> Bool, tilingOn: @escaping () -> Bool) {
        self.screenshotsOn = screenshotsOn
        self.clipboardOn = clipboardOn
        self.tilingOn = tilingOn
        super.init()
        for item in [captureAreaItem, captureScreenItem, clipboardItem, tilingItem] { item.target = self }
    }

    func buildMenuSection(into menu: NSMenu) {
        let tools: [(MysliTool, () -> Bool, [NSMenuItem])] = [
            (.screenshots, screenshotsOn, [captureAreaItem, captureScreenItem]),
            (.clipboard, clipboardOn, [clipboardItem]),
            (.windows, tilingOn, [tilingItem])
        ]
        for (tool, isEnabled, actions) in tools {
            let items = [NSMenuItem.toolHeader(tool)] + actions + [.separator()]
            groups.append((isEnabled, items))
            items.forEach(menu.addItem)
        }
        menuWillOpen()
    }

    func menuWillOpen() {
        for group in groups {
            let hidden = !group.isEnabled()
            for item in group.items { item.isHidden = hidden }
        }
        let screenshots = screenshotsOn()
        show(screenshots ? .captureArea : nil, on: captureAreaItem)
        show(screenshots ? .captureFullScreen : nil, on: captureScreenItem)
        show(clipboardOn() ? .clipboardHistory : nil, on: clipboardItem)
        tilingItem.state = tilingOn() ? .on : .off
    }

    func menuTick() {}

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem !== clipboardItem || clipboardOn()
    }

    /// Shows the shortcut only while Mysli owns it. The global hotkey does the work, so the key
    /// equivalent here only labels the item.
    private func show(_ shortcut: HotkeyShortcut?, on item: NSMenuItem) {
        item.keyEquivalent = shortcut.map { $0.keycap.symbol.lowercased() } ?? ""
        item.keyEquivalentModifierMask = shortcut == nil ? [] : [.command, .shift]
    }

    @objc private func captureArea() { onCaptureArea?() }
    @objc private func captureScreen() { onCaptureScreen?() }
    @objc private func showClipboardHistory() { onShowClipboardHistory?() }
    @objc private func toggleTiling() { onToolChanged?(.windows, !tilingOn()) }
}
