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
    private lazy var statusMenu = StatusMenu(settings: settings, keepAwake: keepAwake)
    private let permissions = PermissionsManager()
    private var onboardingController: OnboardingWindowController?
    /// False in UI-test runs, where permission handling is skipped entirely
    /// (also keeps the warning badge off the status icon there).
    private var permissionHandlingEnabled = false

    func applicationWillTerminate(_ notification: Notification) {
        keepAwake.deactivate()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || CommandLine.arguments.contains("--uitesting")
        setupMenuBar()
        setupThumbnailStack()
        setupKeepAwake()
        if !isTesting {
            setupPermissions()
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
        statusMenu.onMenuWillOpen = { [weak self] in self?.permissions.refresh() }
        permissions.refresh()
        permissionsChanged()
        if !permissions.allGranted {
            showOnboarding(.welcome)
        }
    }

    private func permissionsChanged() {
        if permissions.accessibility && !hotkeyManager.isRunning {
            setupHotkey()
        }
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
                }
            }
        }
        hotkeyManager.tilingEnabled = settings.windowTilingEnabled
        hotkeyManager.start()
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
            permissionMissing: permissionHandlingEnabled && !permissions.allGranted
        )
    }
}
