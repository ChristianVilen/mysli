import Cocoa
import ServiceManagement
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkeyManager = HotkeyManager()
    private let captureManager = CaptureManager()
    private var overlayWindows: [OverlayWindow] = []
    private var thumbnailPanel: ThumbnailPanel?
    private var editorWindow: EditorWindow?
    private var launchAtLoginItem: NSMenuItem!
    private var durationItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || CommandLine.arguments.contains("--uitesting")
        if !isTesting {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            setupHotkey()
        }
        setupMenuBar()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Ku-Ka")
        }

        let menu = NSMenu()

        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = UserDefaults.standard.bool(forKey: "launchAtLogin") ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let durationLabel = NSMenuItem(title: "Thumbnail Duration", action: nil, keyEquivalent: "")
        durationLabel.isEnabled = false
        menu.addItem(durationLabel)

        let currentDuration = UserDefaults.standard.object(forKey: "thumbnailDuration") as? Double ?? 5.0
        for (title, tag) in [("3 Seconds", 3), ("5 Seconds", 5), ("Forever", 0)] {
            let item = NSMenuItem(title: title, action: #selector(changeDuration(_:)), keyEquivalent: "")
            item.target = self
            item.tag = tag
            item.state = Double(tag) == currentDuration ? .on : .off
            menu.addItem(item)
            durationItems.append(item)
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Ku-Ka", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyManager.onHotkey = { [weak self] in self?.startCapture() }
        hotkeyManager.start()
    }

    // MARK: - Capture Flow

    private func startCapture() {
        guard overlayWindows.isEmpty else { return }

        let mouseLocation = NSEvent.mouseLocation
        var cursorScreenOverlay: OverlayWindow?

        for screen in NSScreen.screens {
            let overlay = OverlayWindow(screen: screen)

            overlay.selectionView.onSelection = { [weak self] rect in
                self?.finishCapture(rect: rect, screen: screen)
            }
            overlay.selectionView.onCancel = { [weak self] in
                self?.dismissOverlay()
            }

            overlayWindows.append(overlay)

            if screen.frame.contains(mouseLocation) {
                cursorScreenOverlay = overlay
            }
        }

        NSApp.activate(ignoringOtherApps: true)

        for overlay in overlayWindows {
            if overlay === cursorScreenOverlay {
                overlay.makeKeyAndOrderFront(nil)
                overlay.makeFirstResponder(overlay.selectionView)
            } else {
                overlay.orderFront(nil)
            }
        }
    }

    private func finishCapture(rect: CGRect, screen: NSScreen) {
        dismissOverlay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let result = self.captureManager.capture(rect: rect, screen: screen) else { return }
            self.showThumbnail(result: result, screen: screen)
        }
    }

    private func dismissOverlay() {
        NSCursor.pop()
        for overlay in overlayWindows {
            overlay.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    // MARK: - Thumbnail & Editor

    private func showThumbnail(result: CaptureResult, screen: NSScreen) {
        let duration = UserDefaults.standard.object(forKey: "thumbnailDuration") as? Double ?? 5.0
        let panel = ThumbnailPanel(image: result.image, screen: screen, duration: duration)
        thumbnailPanel = panel

        panel.onEdit = { [weak self] in
            self?.thumbnailPanel = nil
            self?.openEditor(result: result)
        }
        panel.onDismiss = { [weak self] in
            self?.thumbnailPanel = nil
        }

        panel.orderFront(nil)
    }

    private func openEditor(result: CaptureResult) {
        NSApp.activate(ignoringOtherApps: true)

        let editor = EditorWindow(image: result.image)
        editorWindow = editor

        editor.onSave = { [weak self] annotatedImage in
            self?.captureManager.saveAnnotated(image: annotatedImage, to: result.fileURL)
            self?.editorWindow = nil
        }

        editor.makeKeyAndOrderFront(nil)
    }

    // MARK: - Thumbnail Duration

    @objc private func changeDuration(_ sender: NSMenuItem) {
        UserDefaults.standard.set(Double(sender.tag), forKey: "thumbnailDuration")
        for item in durationItems { item.state = .off }
        sender.state = .on
    }

    // MARK: - Launch at Login

    @objc private func toggleLaunchAtLogin() {
        let enabled = !UserDefaults.standard.bool(forKey: "launchAtLogin")
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
            launchAtLoginItem.state = enabled ? .on : .off
        } catch {
            NSLog("Launch at login toggle failed: \(error)")
        }
    }
}
