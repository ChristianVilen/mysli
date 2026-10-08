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
    private var onboardingController: OnboardingWindowController?
    /// False in UI-test runs, where permission handling is skipped entirely
    /// (also keeps the warning badge off the status icon there).
    private var permissionHandlingEnabled = false

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.stop()
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
            setupHotkey()
            setupPermissions()
            // Polling the real pasteboard during unit/UI test runs would
            // ingest whatever the developer happens to have copied, so this
            // stays behind the same isTesting gate as setupPermissions().
            if settings.clipboardHistoryEnabled {
                clipboardHistory.enable()
            }
        }
    }

    // MARK: - Permissions

    /// Refresh permissions and show onboarding while a grant is missing.
    private func setupPermissions() {
        permissionHandlingEnabled = true
        permissions.onChange = { [weak self] in self?.permissionsChanged() }
        permissions.startMonitoring()
        // An accessory app rarely becomes active, so also re-check every time
        // the status menu opens — otherwise a revocation made in System
        // Settings would leave the warning badge stale until onboarding opens.
        statusMenu.onMenuWillOpen = { [weak self] in
            self?.permissions.refresh()
            self?.hotkeyManager.refresh()
            self?.updateStatus()
        }
        permissions.refresh()
        permissionsChanged()
        if !permissions.allGranted {
            showOnboarding(.welcome)
        }
    }

    private func permissionsChanged() {
        updateStatus()
        onboardingController?.refreshRows()
    }

    private func showOnboarding(_ page: OnboardingWindowController.Page = .checklist) {
        onboarding().show(page)
    }

    private func onboarding() -> OnboardingWindowController {
        if onboardingController == nil {
            let controller = OnboardingWindowController(permissions: permissions, settings: settings)
            controller.onClose = { [weak self] in
                self?.scheduleScreenshotSetup()
            }
            onboardingController = controller
        }
        return onboardingController!
    }

    private func showScreenshotSetupIfNeeded() {
        guard permissionHandlingEnabled, !settings.didShowScreenshotShortcutSetup,
              hotkeyManager.issues.contains(where: { $0.shortcut.isScreenshot && $0.failure == .systemConflict }) else { return }
        onboarding().showScreenshotSetupIfNeeded(issues: hotkeyManager.issues)
    }

    private func scheduleScreenshotSetup() {
        guard permissionHandlingEnabled, !settings.didShowScreenshotShortcutSetup else { return }
        // Default mode waits for menu tracking and window-close handling to finish.
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated { self?.showScreenshotSetupIfNeeded() }
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatus()
        statusMenu.onTilingToggled = { [weak self] enabled in
            self?.hotkeyManager.tilingEnabled = enabled
        }
        statusMenu.onShowPermissions = { [weak self] in self?.showOnboarding() }
        statusMenu.onOpenKeyboardSettings = { [weak self] in self?.permissions.openSettings(.keyboardShortcuts) }
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
        hotkeyManager.onChange = { [weak self] in self?.updateStatus() }
        hotkeyManager.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .captureArea: self.startCapture(.interactive)
            case .captureFullScreen: self.startCapture(.fullScreen)
            case .tile(let tilingAction): self.windowTiling.tile(tilingAction)
            case .showClipboardHistory: self.toggleClipboardPanel()
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
        keepAwake.onStateChange = { [weak self] in self?.updateStatus() }
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

    private func updateStatus() {
        let health = permissionHandlingEnabled
            ? HotkeyHealth(accessibilityMissing: !permissions.accessibility, issues: hotkeyManager.issues)
            : .healthy
        statusMenu.updateHotkeyHealth(health)
        let warning: StatusWarning?
        if health != .healthy {
            warning = .shortcutsUnavailable
        } else if permissionHandlingEnabled && !permissions.screenRecording {
            warning = .screenRecordingMissing
        } else {
            warning = nil
        }
        statusItem.button?.image = statusMenu.icon(
            keepAwakeActive: keepAwake.isActive,
            warning: warning
        )
        scheduleScreenshotSetup()
    }
}
