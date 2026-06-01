import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkeyManager = HotkeyManager()
    private let captureManager = CaptureManager()
    private let scrollWheelManager = ScrollWheelManager()
    private var overlayWindows: [OverlayWindow] = []
    private let thumbnailStack = ThumbnailStackManager()
    private var editorWindow: EditorWindow?
    private var launchAtLoginItem: NSMenuItem!
    private var durationItems: [NSMenuItem] = []
    private var scrollInvertItem: NSMenuItem!
    private var scrollAccelItem: NSMenuItem!
    private var linesPerTickItems: [NSMenuItem] = []

    private let scrollInvertKey = "scrollInversionEnabled"
    private let scrollAccelKey = "scrollDisableAcceleration"
    private let scrollLinesKey = "scrollLinesPerTick"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || CommandLine.arguments.contains("--uitesting")
        if !isTesting {
            setupHotkey()
            setupScrollWheel()
        }
        setupMenuBar()
        setupThumbnailStack()
    }

    private func setupScrollWheel() {
        let defaults = UserDefaults.standard
        scrollWheelManager.settings = ScrollTransformSettings(
            invert: defaults.bool(forKey: scrollInvertKey),
            disableAcceleration: defaults.bool(forKey: scrollAccelKey),
            linesPerTick: (defaults.object(forKey: scrollLinesKey) as? Int) ?? 3
        )
        if scrollWheelManager.settings.invert || scrollWheelManager.settings.disableAcceleration {
            scrollWheelManager.start()
        }
    }

    private func updateScrollManagerRunning() {
        let needed = scrollWheelManager.settings.invert || scrollWheelManager.settings.disableAcceleration
        if needed && !scrollWheelManager.isRunning {
            scrollWheelManager.start()
        } else if !needed && scrollWheelManager.isRunning {
            scrollWheelManager.stop()
        } else {
            scrollWheelManager.reload()
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let icon = NSImage(named: "MenuBarIcon") {
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Ku-Ka")
            }
        }

        let menu = NSMenu()

        // --- Settings ---
        let settingsLabel = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsLabel.isEnabled = false
        menu.addItem(settingsLabel)

        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let durationLabel = NSMenuItem(title: "Thumbnail Duration", action: nil, keyEquivalent: "")
        durationLabel.isEnabled = false
        menu.addItem(durationLabel)

        let currentDuration = UserDefaults.standard.object(forKey: "thumbnailDuration") as? Double ?? 5.0
        for (title, tag) in [("3 Seconds", 3), ("5 Seconds", 5), ("15 Seconds", 15), ("Forever", 0)] {
            let item = NSMenuItem(title: title, action: #selector(changeDuration(_:)), keyEquivalent: "")
            item.target = self
            item.tag = tag
            item.state = Double(tag) == currentDuration ? .on : .off
            menu.addItem(item)
            durationItems.append(item)
        }

        menu.addItem(.separator())

        // --- Scroll Wheel ---
        let scrollLabel = NSMenuItem(title: "Scroll Wheel", action: nil, keyEquivalent: "")
        scrollLabel.isEnabled = false
        menu.addItem(scrollLabel)

        let defaults = UserDefaults.standard
        scrollInvertItem = NSMenuItem(title: "Invert Mouse Scroll Direction", action: #selector(toggleScrollInvert), keyEquivalent: "")
        scrollInvertItem.target = self
        scrollInvertItem.state = defaults.bool(forKey: scrollInvertKey) ? .on : .off
        menu.addItem(scrollInvertItem)

        scrollAccelItem = NSMenuItem(title: "Disable Scroll Acceleration", action: #selector(toggleScrollAcceleration), keyEquivalent: "")
        scrollAccelItem.target = self
        scrollAccelItem.state = defaults.bool(forKey: scrollAccelKey) ? .on : .off
        menu.addItem(scrollAccelItem)

        let linesItem = NSMenuItem(title: "Lines Per Tick", action: nil, keyEquivalent: "")
        let linesMenu = NSMenu()
        let currentLines = (defaults.object(forKey: scrollLinesKey) as? Int) ?? 3
        for tag in [1, 3, 5, 7, 10] {
            let item = NSMenuItem(title: "\(tag)", action: #selector(changeLinesPerTick(_:)), keyEquivalent: "")
            item.target = self
            item.tag = tag
            item.state = tag == currentLines ? .on : .off
            linesMenu.addItem(item)
            linesPerTickItems.append(item)
        }
        linesItem.submenu = linesMenu
        menu.addItem(linesItem)

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

        statusItem.menu = menu
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyManager.onHotkey = { [weak self] in self?.startCapture() }
        hotkeyManager.onFullScreenHotkey = { [weak self] in self?.startFullScreenCapture() }
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
            overlay.selectionView.onWindowSelection = { [weak self] windowID in
                self?.finishWindowCapture(windowID: windowID, screen: screen)
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

    private func startFullScreenCapture() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else { return }
        guard let result = captureManager.captureFullScreen(screen: screen) else { return }
        FlashView.flash(on: screen)
        showThumbnail(result: result, screen: screen)
    }

    private func finishCapture(rect: CGRect, screen: NSScreen) {
        dismissOverlay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let result = self.captureManager.capture(rect: rect, screen: screen) else { return }
            self.showThumbnail(result: result, screen: screen)
        }
    }

    private func finishWindowCapture(windowID: CGWindowID, screen: NSScreen) {
        dismissOverlay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let result = self.captureManager.captureWindow(windowID: windowID, screen: screen) else { return }
            self.showThumbnail(result: result, screen: screen)
        }
    }

    private func dismissOverlay() {
        NSCursor.pop()
        for overlay in overlayWindows {
            overlay.close()
        }
        overlayWindows.removeAll()
    }

    // MARK: - Thumbnail & Editor

    private func setupThumbnailStack() {
        thumbnailStack.onEdit = { [weak self] result in
            self?.openEditor(result: result)
        }
        thumbnailStack.onCombine = { [weak self] topImage, bottomImage in
            self?.captureManager.saveCombined(topImage: topImage, bottomImage: bottomImage)
        }
        thumbnailStack.onDelete = { [weak self] result in
            self?.captureManager.deleteScreenshot(at: result.fileURL)
        }
    }

    private func showThumbnail(result: CaptureResult, screen: NSScreen) {
        let duration = UserDefaults.standard.object(forKey: "thumbnailDuration") as? Double ?? 5.0
        thumbnailStack.add(image: result.image, result: result, screen: screen, duration: duration)
    }

    private func openEditor(result: CaptureResult) {
        NSApp.activate(ignoringOtherApps: true)

        let editor = EditorWindow(image: result.image)
        editorWindow = editor

        editor.onSave = { [weak self] annotatedImage in
            self?.captureManager.saveAnnotated(image: annotatedImage, to: result.fileURL)
        }

        editor.onDelete = { [weak self] in
            self?.captureManager.deleteScreenshot(at: result.fileURL)
        }

        // Drop our reference once the window closes (Done/Delete/close button/Escape)
        // so the editor and its full-resolution image deallocate. Closing only
        // ever replaces this one editor, so clear it unconditionally.
        editor.onClose = { [weak self] in self?.editorWindow = nil }

        editor.makeKeyAndOrderFront(nil)
    }

    // MARK: - Thumbnail Duration

    @objc private func changeDuration(_ sender: NSMenuItem) {
        UserDefaults.standard.set(Double(sender.tag), forKey: "thumbnailDuration")
        for item in durationItems { item.state = .off }
        sender.state = .on
    }

    // MARK: - Scroll Wheel

    @objc private func toggleScrollInvert() {
        let new = !UserDefaults.standard.bool(forKey: scrollInvertKey)
        UserDefaults.standard.set(new, forKey: scrollInvertKey)
        scrollInvertItem.state = new ? .on : .off
        scrollWheelManager.settings.invert = new
        updateScrollManagerRunning()
    }

    @objc private func toggleScrollAcceleration() {
        let new = !UserDefaults.standard.bool(forKey: scrollAccelKey)
        UserDefaults.standard.set(new, forKey: scrollAccelKey)
        scrollAccelItem.state = new ? .on : .off
        scrollWheelManager.settings.disableAcceleration = new
        updateScrollManagerRunning()
    }

    @objc private func changeLinesPerTick(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: scrollLinesKey)
        for item in linesPerTickItems { item.state = .off }
        sender.state = .on
        scrollWheelManager.settings.linesPerTick = sender.tag
        if scrollWheelManager.isRunning { scrollWheelManager.reload() }
    }

    @objc private func openReportBug() {
        NSWorkspace.shared.open(URL(string: "https://github.com/ChristianVilen/ku-ka/issues/new?labels=bug")!)
    }

    @objc private func openSuggestFeature() {
        NSWorkspace.shared.open(URL(string: "https://github.com/ChristianVilen/ku-ka/issues/new?labels=enhancement")!)
    }

    // MARK: - Launch at Login

    @objc private func toggleLaunchAtLogin() {
        let isCurrentlyEnabled = SMAppService.mainApp.status == .enabled
        do {
            if isCurrentlyEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } catch {
            NSLog("Launch at login toggle failed: \(error)")
        }
    }
}
