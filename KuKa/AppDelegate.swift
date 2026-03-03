import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkeyManager = HotkeyManager()
    private let captureManager = CaptureManager()
    private var overlayWindows: [OverlayWindow] = []
    private var escapeMonitor: Any?
    private var mouseTap: CFMachPort?
    private var mouseTapSource: CFRunLoopSource?
    private let thumbnailStack = ThumbnailStackManager()
    private var editorWindow: EditorWindow?
    private var launchAtLoginItem: NSMenuItem!
    private var durationItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || CommandLine.arguments.contains("--uitesting")
        if !isTesting {
            setupHotkey()
        }
        setupMenuBar()
        setupThumbnailStack()
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
        launchAtLoginItem.state = UserDefaults.standard.bool(forKey: "launchAtLogin") ? .on : .off
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

        // --- Features ---
        let featuresLabel = NSMenuItem(title: "Features", action: nil, keyEquivalent: "")
        featuresLabel.isEnabled = false
        menu.addItem(featuresLabel)

        for feature in [
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
        hotkeyManager.start()
    }

    // MARK: - Capture Flow

    private func startCapture() {
        guard overlayWindows.isEmpty else { return }

        var cursorScreenOverlay: OverlayWindow?
        let mouseLocation = NSEvent.mouseLocation

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

        for overlay in overlayWindows {
            overlay.orderFrontRegardless()
        }

        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.dismissOverlay() }
        }

        startMouseTap(cursorOverlay: cursorScreenOverlay)
    }

    private func startMouseTap(cursorOverlay: OverlayWindow?) {
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(
                (1 << CGEventType.leftMouseDown.rawValue) |
                (1 << CGEventType.leftMouseDragged.rawValue) |
                (1 << CGEventType.leftMouseUp.rawValue)
            ),
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                return appDelegate.handleMouseEvent(type: type, event: event)
            },
            userInfo: refcon
        ) else { return }

        mouseTap = tap
        _cursorOverlay = cursorOverlay
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        mouseTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private weak var _cursorOverlay: OverlayWindow?

    private func handleMouseEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let cursorOverlay = _cursorOverlay else {
            return Unmanaged.passUnretained(event)
        }

        // CGEvent uses top-left origin; convert to view coordinates (bottom-left origin)
        let cgPoint = event.location
        let screenFrame = cursorOverlay.frame
        let mainHeight = NSScreen.screens.first?.frame.height ?? screenFrame.height
        let viewPoint = NSPoint(
            x: cgPoint.x - screenFrame.origin.x,
            y: (mainHeight - cgPoint.y) - screenFrame.origin.y
        )

        switch type {
        case .leftMouseDown:
            cursorOverlay.selectionView.beginSelection(at: viewPoint)
            cursorOverlay.selectionView.needsDisplay = true
        case .leftMouseDragged:
            cursorOverlay.selectionView.updateDrag(to: viewPoint)
        case .leftMouseUp:
            DispatchQueue.main.async {
                cursorOverlay.selectionView.endSelection()
            }
        default:
            break
        }

        return nil
    }

    private func finishCapture(rect: CGRect, screen: NSScreen) {
        dismissOverlay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let result = self.captureManager.capture(rect: rect, screen: screen) else { return }
            self.showThumbnail(result: result, screen: screen)
        }
    }

    private func dismissOverlay() {
        removeEventMonitors()
        NSCursor.pop()
        for overlay in overlayWindows {
            overlay.orderOut(nil)
        }
        overlayWindows.removeAll()
        _cursorOverlay = nil
    }

    private func removeEventMonitors() {
        if let monitor = escapeMonitor { NSEvent.removeMonitor(monitor); escapeMonitor = nil }
        if let source = mouseTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            mouseTapSource = nil
        }
        if let tap = mouseTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            mouseTap = nil
        }
    }

    // MARK: - Thumbnail & Editor

    private func setupThumbnailStack() {
        thumbnailStack.onEdit = { [weak self] result in
            self?.openEditor(result: result)
        }
        thumbnailStack.onCombine = { [weak self] topImage, bottomImage in
            self?.captureManager.saveCombined(topImage: topImage, bottomImage: bottomImage)
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

    @objc private func openReportBug() {
        NSWorkspace.shared.open(URL(string: "https://github.com/ChristianVilen/ku-ka/issues/new?labels=bug")!)
    }

    @objc private func openSuggestFeature() {
        NSWorkspace.shared.open(URL(string: "https://github.com/ChristianVilen/ku-ka/issues/new?labels=enhancement")!)
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
