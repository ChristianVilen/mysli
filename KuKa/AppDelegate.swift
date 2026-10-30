import Cocoa
import UserNotifications

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
    private lazy var knownWords = KnownWordsFile(url: { [settings] in settings.knownWordsFile })
    private lazy var meetingRecorder = MeetingRecorder(
        permissions: permissions,
        root: { [settings] in settings.meetingsFolder },
        locale: { [settings] in settings.meetingLocale }
    )
    private lazy var meetingNotes = MeetingNotesController(
        recorder: meetingRecorder,
        root: { [settings] in settings.meetingsFolder },
        processor: MeetingProcessor(roomLabeller: SpeakerKitRoomLabeller(),
                                    summarizer: Summarizer(context: MeetingContextFile(url: { [settings] in settings.meetingContextFile })),
                                    knownWords: { [knownWords] in knownWords.read() },
                                    locale: { [settings] in settings.meetingLocale }),
        wordsToCheck: { [knownWords, settings] in
            WordReview.openQuestionCount(of: $0, in: settings.meetingsFolder, knownWords: knownWords.read())
        },
        setRoot: { [settings] in settings.meetingsFolder = $0 }
    )
    private lazy var meetingControlsPanel = MeetingControlsPanel(recorder: meetingRecorder, settings: settings)
    private(set) var calendarReminders: CalendarReminderController?
    private var calendarReminderStartup: Task<Void, Never>?
    private lazy var wordReview = WordReviewController(
        root: { [settings] in settings.meetingsFolder },
        knownWords: knownWords,
        isOrdinary: OrdinaryWords.spellChecker(language: { [settings] in settings.meetingLocale }),
        requestUpdate: { [weak self] in self?.meetingNotes.updateNotes($0) }
    )
    private lazy var wordReviewWindow = WordReviewWindowController(controller: wordReview)
    private lazy var statusMenu = StatusMenu(settings: settings, sections: [keepAwake, meetingNotes])
    private let permissions = PermissionsManager()
    private var onboardingController: OnboardingWindowController?
    /// False in UI-test runs, where permission handling is skipped entirely
    /// (also keeps the warning badge off the status icon there).
    private var permissionHandlingEnabled = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard meetingRecorder.phase.isCapturing else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Stop Recording and Quit?"
        alert.informativeText = "Ku-Ka is recording a meeting. If you quit, the recording stops, and Ku-Ka makes the notes the next time it opens."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.stop()
        keepAwake.deactivate()
        clipboardHistory.disable()
        calendarReminderStartup?.cancel()
        calendarReminders?.shutDown()
        SystemNotifier.shared.onCalendarReminder = nil
        meetingNotes.shutDown()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || CommandLine.arguments.contains("--uitesting")
        setupMenuBar()
        setupThumbnailStack()
        setupKeepAwake()
        setupClipboardHistory()
        setupMeetingNotes()
        if !isTesting {
            UNUserNotificationCenter.current().delegate = SystemNotifier.shared
            SystemNotifier.shared.onCheckWords = { [weak self] in self?.wordReviewWindow.show($0) }
            setupCalendarReminders()
            setupHotkey()
            setupPermissions()
            // Polling the real pasteboard during unit/UI test runs would
            // ingest whatever the developer happens to have copied, so this
            // stays behind the same isTesting gate as setupPermissions().
            if settings.clipboardHistoryEnabled {
                clipboardHistory.enable()
            }
            meetingNotes.resumeUnfinished()
        }
    }

    private func setupCalendarReminders() {
        let notifications = CalendarReminderNotifications()
        let controller = CalendarReminderController(source: EventKitCalendarSource(), notifications: notifications,
            recorder: meetingRecorder, driver: CalendarReminderDriver(), settings: settings,
            store: CalendarReminderStore(defaults: .standard))
        SystemNotifier.shared.onCalendarReminder = { [weak controller] action, token in
            await controller?.handle(action, token: token)
        }
        calendarReminderStartup = Task { [weak self] in
            guard !Task.isCancelled, let self else { return }
            self.calendarReminders = controller
            await controller.resume()
            await notifications.prepare()
        }
    }

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

    /// Binds callbacks once at launch, before presentation. Safe in tests: it does not read
    /// the real pasteboard, unlike `clipboardHistory.enable()`.
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

    private func toggleClipboardPanel() {
        if clipboardPanel.isVisible {
            clipboardPanel.dismiss()
        } else {
            clipboardPanel.show()
        }
    }

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

    private func setupThumbnailStack() {
        thumbnailStack.onEdit = { [weak self] result in
            self?.openEditor(result: result)
        }
    }

    private func setupKeepAwake() {
        keepAwake.onStateChange = { [weak self] in self?.updateStatus() }
    }

    /// Not behind the `isTesting` gate: binding the panel and the review window touches no
    /// hardware and no disk and writes no setting, and both stay hidden until they are needed.
    private func setupMeetingNotes() {
        meetingNotes.onStateChange = { [weak self] in
            self?.updateStatus()
            self?.calendarReminders?.recorderDidChange()
        }
        meetingRecorder.onShowPermissions = { [weak self] in self?.showOnboarding() }
        meetingNotes.onCheckWords = { [weak self] in self?.wordReviewWindow.show($0) }
        meetingControlsPanel.bindRecorder()
        wordReviewWindow.bindController()
    }

    private func openEditor(result: CaptureResult) {
        NSApp.activate(ignoringOtherApps: true)

        let editor = EditorWindow(image: result.image, fileURL: result.fileURL, store: imageStore)
        editorWindow = editor

        // Release the image when this editor closes, without clearing a newer editor.
        // Capture `editor` weakly to avoid a cycle through its stored closure.
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
        let phase = meetingRecorder.phase
        statusItem.button?.image = statusMenu.icon(
            keepAwakeActive: keepAwake.isActive,
            recording: phase.recordingMark,
            warning: warning
        )
        statusItem.button?.setAccessibilityLabel(phase.statusDescription.map { "Ku-Ka, \($0)" } ?? "Ku-Ka")
        statusItem.button?.toolTip = phase.statusDescription.map { "Ku-Ka: \($0)" }
        scheduleScreenshotSetup()
    }
}
