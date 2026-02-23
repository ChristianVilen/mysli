import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkeyManager = HotkeyManager()
    private let captureManager = CaptureManager()
    private var overlayWindow: OverlayWindow?
    private var launchAtLoginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHotkey()
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
        guard overlayWindow == nil, let screen = NSScreen.main else { return }

        let overlay = OverlayWindow(screen: screen)
        overlayWindow = overlay

        overlay.selectionView.onSelection = { [weak self] rect in
            self?.finishCapture(rect: rect, screen: screen)
        }
        overlay.selectionView.onCancel = { [weak self] in
            self?.dismissOverlay()
        }

        overlay.makeKeyAndOrderFront(nil)
        overlay.makeFirstResponder(overlay.selectionView)
        NSCursor.crosshair.push()
    }

    private func finishCapture(rect: CGRect, screen: NSScreen) {
        dismissOverlay()
        // Small delay to let the overlay fully disappear before capturing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.captureManager.capture(rect: rect, screen: screen)
        }
    }

    private func dismissOverlay() {
        NSCursor.pop()
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
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
