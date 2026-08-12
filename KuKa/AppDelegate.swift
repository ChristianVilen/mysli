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

    func applicationWillTerminate(_ notification: Notification) {
        keepAwake.deactivate()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || CommandLine.arguments.contains("--uitesting")
        if !isTesting {
            setupHotkey()
        }
        setupMenuBar()
        setupThumbnailStack()
        setupKeepAwake()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusItemIcon()
        statusMenu.onTilingToggled = { [weak self] enabled in
            self?.hotkeyManager.tilingEnabled = enabled
        }
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
        guard ScreenRecordingPermission.ensureGranted() else { return }
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
        statusItem.button?.image = statusMenu.icon(keepAwakeActive: keepAwake.isActive)
    }
}
