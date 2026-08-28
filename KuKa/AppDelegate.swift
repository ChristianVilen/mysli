import Cocoa

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkeyManager = HotkeyManager()
    private let settings = Settings()
    private let imageStore = ImageStore()
    private lazy var captureFlow = CaptureFlow(
        selection: SelectionSession(),
        capture: CaptureManager(store: imageStore),
        thumbnails: thumbnailStack,
        thumbnailDuration: { [settings] in settings.thumbnailDuration }
    )
    private lazy var thumbnailStack = ThumbnailStackManager(store: imageStore)
    private var editorWindow: EditorWindow?
    private let keepAwake = KeepAwakeController()
    private let windowTiling = WindowTilingController()
    private let clipboardHistory = ClipboardHistoryController()
    private lazy var clipboardPanel = ClipboardPanel(controller: clipboardHistory)
    private lazy var statusMenu = StatusMenu(settings: settings, keepAwake: keepAwake)
    private let permissions = PermissionsManager()
    /// Lazy so the probes can reference the types that own what they report:
    /// permission status is `PermissionsManager`'s, tap status is
    /// `HotkeyManager`'s. The closures capture those, not self, so there is
    /// no retain cycle.
    private lazy var hotkeyHealth = HotkeyHealthMonitor(
        isAccessibilityGranted: { [permissions] in permissions.accessibility },
        isTapDelivering: { [hotkeyManager] in hotkeyManager.isDelivering }
    )
    private var onboardingController: OnboardingWindowController?
    /// False in UI-test runs, where permission handling is skipped entirely
    /// (also keeps the warning badge off the status icon there).
    private var permissionHandlingEnabled = false

    func applicationWillTerminate(_ notification: Notification) {
        keepAwake.deactivate()
        clipboardHistory.disable()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || CommandLine.arguments.contains("--uitesting")
        setupMenuBar()
        setupThumbnailStack()
        setupKeepAwake()
        setupClipboardHistory()
        if !isTesting {
            setupPermissions()
            setupHotkeyHealthWatch()
            // Polling the real pasteboard during unit/UI test runs would
            // ingest whatever the developer happens to have copied, so this
            // stays behind the same isTesting gate as setupPermissions().
            if settings.clipboardHistoryEnabled {
                clipboardHistory.enable()
            }
        }
    }

    // MARK: - Permissions

    /// Wires `PermissionsManager` in as the single source of truth: the event
    /// tap starts the moment Accessibility is granted (no relaunch), and the
    /// onboarding window opens on launch while anything is missing.
    private func setupPermissions() {
        permissionHandlingEnabled = true
        permissions.onChange = { [weak self] in self?.permissionsChanged() }
        permissions.startMonitoring()
        // An accessory app rarely becomes active, so also re-check every time
        // the status menu opens — otherwise a revocation made in System
        // Settings would leave the warning badge stale until onboarding opens.
        statusMenu.onMenuWillOpen = { [weak self] in
            self?.permissions.refresh()
            self?.hotkeyHealth.refresh()
        }
        permissions.refresh()
        permissionsChanged()
        if !permissions.allGranted {
            showOnboarding(.welcome)
        }
    }

    /// Every hotkey-death cause is silent on its own (a starved tap logs
    /// nothing a user sees), so watch the health monitor and surface its
    /// state. Called behind the same isTesting gate as `setupPermissions()`:
    /// tests never poll the real session. The menu-open refresh lives in
    /// `setupPermissions()`'s `onMenuWillOpen` closure — it's a single
    /// callback slot shared by both.
    private func setupHotkeyHealthWatch() {
        hotkeyHealth.onChange = { [weak self] in self?.hotkeyHealthChanged() }
        hotkeyHealth.startMonitoring()
    }

    private func hotkeyHealthChanged() {
        statusMenu.updateHotkeyHealth(hotkeyHealth.state)
        updateStatusItemIcon()
    }

    private func permissionsChanged() {
        if permissions.accessibility && !hotkeyManager.isRunning {
            setupHotkey()
        }
        // After setupHotkey, so the tap probe sees the tap it just started.
        // Without this the menu would keep the "Hotkeys off" warning, and the
        // icon its red dot, until the health monitor's next 5s poll.
        hotkeyHealth.refresh()
        updateStatusItemIcon()
        onboardingController?.refreshRows()
    }

    private func showOnboarding(_ page: OnboardingWindowController.Page = .checklist) {
        if onboardingController == nil {
            onboardingController = OnboardingWindowController(permissions: permissions)
        }
        onboardingController?.show(page)
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusItemIcon()
        statusMenu.onTilingToggled = { [weak self] enabled in
            self?.hotkeyManager.tilingEnabled = enabled
        }
        statusMenu.onShowPermissions = { [weak self] in self?.showOnboarding() }
        statusItem.menu = statusMenu.menu
    }

    // MARK: - Clipboard History

    /// Binds the panel to the controller's callback slots and wires the menu
    /// toggle and screenshot-deletion hook. Called unconditionally from
    /// `applicationDidFinishLaunching` — unlike `clipboardHistory.enable()`,
    /// none of this touches the real pasteboard, so it doesn't need the
    /// `isTesting` gate. Binding here (rather than leaving `clipboardPanel`
    /// as an untouched lazy var) guarantees `bindController()` runs exactly
    /// once, before the panel could ever be shown.
    private func setupClipboardHistory() {
        clipboardPanel.bindController()

        statusMenu.onClipboardHistoryToggled = { [weak self] enabled in
            guard let self else { return }
            hotkeyManager.clipboardHistoryEnabled = enabled
            if enabled {
                clipboardHistory.enable()
            } else {
                clipboardHistory.disable()
                if clipboardPanel.isVisible {
                    clipboardPanel.dismiss()
                }
            }
        }

        imageStore.onDeletedHash = { [weak self] hash in
            self?.clipboardHistory.removeItem(hash: hash)
        }
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        // HotkeyManager always delivers actions via DispatchQueue.main.async,
        // so we're already on the main thread here — assumeIsolated documents
        // that instead of hopping through a Task, which would run the action
        // one runloop turn late and could reorder rapid key presses.
        hotkeyManager.onAction = { [weak self] action in
            guard let self else { return }
            MainActor.assumeIsolated {
                switch action {
                case .captureArea: self.startCapture(.interactive)
                case .captureFullScreen: self.startCapture(.fullScreen)
                case .tile(let tilingAction): self.windowTiling.tile(tilingAction)
                case .showClipboardHistory: self.toggleClipboardPanel()
                }
            }
        }
        hotkeyManager.tilingEnabled = settings.windowTilingEnabled
        hotkeyManager.clipboardHistoryEnabled = settings.clipboardHistoryEnabled
        hotkeyManager.start()
    }

    /// Shows the panel on the cursor's screen, or dismisses it if a second
    /// hotkey press catches it already open.
    private func toggleClipboardPanel() {
        if clipboardPanel.isVisible {
            clipboardPanel.dismiss()
        } else {
            clipboardPanel.show()
        }
    }

    // MARK: - Capture Flow

    private func startCapture(_ mode: CaptureFlow.Mode) {
        // Screen Recording can be revoked at any time, so re-check at press
        // time. A missing grant routes to the onboarding window (explanation
        // + Grant button) instead of capturing a black frame.
        permissions.refresh()
        guard permissions.screenRecording else {
            showOnboarding()
            return
        }
        // Read the ambient state at press time, before the Task hop
        let layout = SystemScreens().all
        let mouseLocation = NSEvent.mouseLocation
        Task { @MainActor in
            await self.captureFlow.start(mode, layout: layout, mouseLocation: mouseLocation)
        }
    }

    // MARK: - Thumbnail & Editor

    private func setupThumbnailStack() {
        thumbnailStack.onEdit = { [weak self] result in
            self?.openEditor(result: result)
        }
    }

    private func setupKeepAwake() {
        keepAwake.onStateChange = { [weak self] in self?.updateStatusItemIcon() }
    }

    private func openEditor(result: CaptureResult) {
        NSApp.activate(ignoringOtherApps: true)

        let editor = EditorWindow(image: result.image, fileURL: result.fileURL, store: imageStore)
        editorWindow = editor

        // Drop our reference once the window closes (Done/Delete/close button/Escape)
        // so the editor and its full-resolution image deallocate. A second
        // editor can be opened while one is up, so only clear the reference
        // if it still points at the editor that closed. `editor` must be
        // weak here: a strong capture in its own stored closure would be a
        // retain cycle.
        editor.onClose = { [weak self, weak editor] in
            if let editor, self?.editorWindow === editor {
                self?.editorWindow = nil
            }
            MemoryReclaim.schedule()
        }

        editor.makeKeyAndOrderFront(nil)
    }

    private func updateStatusItemIcon() {
        statusItem.button?.image = statusMenu.icon(
            keepAwakeActive: keepAwake.isActive,
            warning: statusWarning()
        )
    }

    /// Dead hotkeys win the corner over a missing permission — they are the
    /// more urgent state, and the menu spells out the cause. Orange is left
    /// for the one permission hotkey health can't see (Screen Recording); a
    /// missing Accessibility grant already shows as red through
    /// `hotkeyHealth`, because it means hotkeys are dead right now.
    private func statusWarning() -> StatusWarning? {
        guard permissionHandlingEnabled else { return nil }
        if hotkeyHealth.state != .healthy { return .hotkeysDead }
        if !permissions.screenRecording { return .screenRecordingMissing }
        return nil
    }
}
