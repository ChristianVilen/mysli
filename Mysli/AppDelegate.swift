import Cocoa
import UserNotifications

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let launchDate = Date()
    private let logFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Mysli", isDirectory: true)
    private lazy var logFiles = LogFiles(folder: logFolder, onFailure: { LogOutput.shared.reportFileFailure($0) })
    private lazy var logWindow = LogWindowController(
        reader: LogFileReader(folder: logFolder), launchDate: launchDate,
        deleteLogs: { [logFiles] in try await logFiles.deleteAll() }
    )
    private var statusItem: NSStatusItem!
    private let hotkeyManager = HotkeyManager()
    private let settings = Settings()
    private lazy var tools = ToolController(settings: settings,
        applyEffect: { [weak self] in self?.applyToolEffect($0, enabled: $1) },
        setCalendarReminders: { [weak self] in await self?.calendarReminders?.setEnabled($0) })
    private let imageStore = ImageStore()
    private lazy var captureFlow = CaptureFlow(
        selection: SelectionSession(),
        capture: CaptureManager(store: imageStore),
        thumbnails: thumbnailStack,
        thumbnailDuration: { [settings] in settings.thumbnailDuration }
    )
    private lazy var thumbnailStack = ThumbnailStackManager(store: imageStore)
    private var editorWindow: EditorWindow?
    private lazy var keepAwake = KeepAwakeController(keepDisplayAwake: settings.keepDisplayAwake)
    private let windowTiling = WindowTilingController()
    private let clipboardHistory = ClipboardHistoryController()
    private lazy var clipboardPanel = ClipboardPanel(controller: clipboardHistory)
    private lazy var knownWords = KnownWordsFile(url: { [settings] in settings.knownWordsFile })
    private let whisperTranscriber = WhisperKitTranscriber()
    private lazy var meetingRecorder = MeetingRecorder(
        permissions: permissions,
        root: { [settings] in settings.meetingsFolder },
        locale: { [settings] in settings.meetingLocale },
        teamsSpeakerNamesEnabled: { [settings] in settings.teamsSpeakerNamesEnabled }
    )
    private lazy var meetingNotes = MeetingNotesController(
        recorder: meetingRecorder,
        root: { [settings] in settings.meetingsFolder },
        processor: MeetingProcessor(transcribers: [whisperTranscriber, SpeechTranscriberAdapter()],
                                    roomLabeller: SpeakerKitRoomLabeller(),
                                    summarizer: Summarizer(context: MeetingContextFile(url: { [settings] in settings.meetingContextFile })),
                                    knownWords: { [knownWords] in knownWords.read() },
                                    locale: { [settings] in settings.meetingLocale }),
        wordsToCheck: { [knownWords, settings] in
            WordReview.openQuestionCount(of: $0, in: settings.meetingsFolder, knownWords: knownWords.read())
        },
        summaryTool: { [settings] in settings.summaryTool }
    )
    private lazy var meetingControlsPanel = MeetingControlsPanel(recorder: meetingRecorder, settings: settings)
    private lazy var notesHosting = MeetingNotesHosting(panel: meetingControlsPanel, recorder: meetingRecorder,
                                                        notes: meetingNotes)
    private(set) var calendarReminders: CalendarReminderController?
    private var calendarReminderStartup: Task<Void, Never>?
    private lazy var wordReview = WordReviewController(
        root: { [settings] in settings.meetingsFolder },
        knownWords: knownWords,
        isOrdinary: OrdinaryWords.spellChecker(language: { [settings] in settings.meetingLocale }),
        requestUpdate: { [weak self] in self?.meetingNotes.updateNotes($0) }
    )
    private lazy var wordReviewWindow = WordReviewWindowController(controller: wordReview)
    private lazy var toolActions = ToolActionsMenuSection(
        screenshotsOn: { [unowned self] in settings.screenshotShortcutsEnabled },
        clipboardOn: { [unowned self] in settings.clipboardHistoryEnabled },
        tilingOn: { [unowned self] in settings.windowTilingEnabled })
    private lazy var statusMenu = StatusMenu(sections: [
        toolActions,
        EnabledMenuSection(keepAwake, isEnabled: { [settings] in settings.keepAwakeEnabled }),
        EnabledMenuSection(meetingNotes, isEnabled: { [settings] in settings.meetingsEnabled })
    ])
    private lazy var onboarding = Onboarding(settings: settings, defaults: .standard)
    private lazy var settingsWindow = SettingsWindowController(settings: settings, onboarding: onboarding, permissionActions: .init(
        accessibility: { [weak self] in self?.permissions.requestAccessibility() },
        screenRecording: { [weak self] in self?.permissions.requestScreenRecording() },
        microphone: { [weak self] in Task { _ = await self?.permissions.requestMicrophone() } },
        calendar: { [weak self] in Task { await self?.permissions.requestCalendar() } },
        notifications: { [weak self] in Task { await self?.permissions.requestNotifications() } },
        keyboardSettings: { [weak self] in self?.permissions.openSettings(.keyboardShortcuts) }))
    private lazy var calendarSource = EventKitCalendarSource()
    private lazy var permissions = PermissionsManager(
        calendarAccess: { [unowned self] in calendarSource.authorization },
        requestCalendarAccess: { [unowned self] in await calendarSource.requestAccess() },
        notificationAccess: {
            NotificationAccess(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
        },
        requestNotificationAccess: {
            (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) == true
        })
    // False until setupPermissions() reads the grants. Hotkey setup calls updateStatus() before that,
    // and grants that were not read yet must not show warnings or open screenshot setup.
    private var permissionHandlingEnabled = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if meetingNotes.hasUnsavedTypedNotes {
            let alert = NSAlert()
            alert.messageText = "Some meeting notes are not saved"
            alert.informativeText = "Keep editing to retry the save or copy your draft. Quit without saving discards the unsaved text."
            if meetingRecorder.phase.isCapturing {
                alert.informativeText += " The recording also stops, and processing resumes when Mysli opens again."
            }
            alert.addButton(withTitle: "Keep editing")
            alert.addButton(withTitle: "Quit without saving")
            NSApp.activate()
            if alert.runModal() == .alertSecondButtonReturn { return .terminateNow }
            for meeting in meetingNotes.unsavedNotesMeetings { openTypedNotes(meeting) }
            return .terminateCancel
        }
        guard meetingRecorder.phase.isCapturing else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Stop Recording and Quit?"
        alert.informativeText = "Mysli is recording a meeting. If you quit, the recording stops, and Mysli makes the notes the next time it opens."
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
        if !logFiles.flush(timeout: 2) {
            LogOutput.shared.reportFileFailure(POSIXError(.ETIMEDOUT))
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LogOutput.shared.enableFiles(logFiles)
        Log.app.notice("Mysli launched")
        setupMenuBar()
        setupThumbnailStack()
        setupKeepAwake()
        setupClipboardHistory()
        setupMeetingNotes()
        UNUserNotificationCenter.current().delegate = SystemNotifier.shared
        SystemNotifier.shared.onCheckWords = { [weak self] in self?.wordReviewWindow.show($0) }
        setupCalendarReminders()
        setupHotkey()
        onboarding.onApplyChoices = { [weak self] in self?.tools.apply($0) }
        setupPermissions()
        if settings.clipboardHistoryEnabled {
            clipboardHistory.enable()
        }
        if settings.meetingsEnabled { meetingNotes.resumeUnfinished() }
    }

    private func setupCalendarReminders() {
        let notifications = CalendarReminderNotifications()
        let controller = CalendarReminderController(source: calendarSource, notifications: notifications,
            recorder: meetingRecorder, driver: CalendarReminderDriver(), settings: settings,
            store: CalendarReminderStore(defaults: .standard))
        SystemNotifier.shared.onCalendarReminder = { [weak controller] action, token in
            await controller?.handle(action, token: token)
        }
        controller.onStatusChange = { [weak self, weak controller] in
            guard let controller else { return }
            self?.settingsWindow.showCalendarStatus(controller.status)
            self?.permissions.refresh()
        }
        calendarReminders = controller
        calendarReminderStartup = Task { [weak self] in
            guard !Task.isCancelled, let self else { return }
            await self.calendarReminders?.resume()
            await notifications.prepare()
        }
    }

    private func setupPermissions() {
        permissionHandlingEnabled = true
        permissions.onChange = { [weak self] in self?.permissionsChanged() }
        permissions.startMonitoring()
        // An accessory app rarely becomes active, so also re-check every time
        // the status menu opens — otherwise a revocation made in System
        // Settings would leave the warning badge stale until Permissions opens.
        statusMenu.onMenuWillOpen = { [weak self] in
            self?.permissions.refresh()
            self?.hotkeyManager.refresh()
            self?.updateStatus()
        }
        Task {
            await permissions.refreshAndWait()
            permissionsChanged()
            switch onboarding.launchDestination(for: permissions.snapshot) {
            case .onboarding: settingsWindow.show()
            case .permissions: settingsWindow.show(.permissions)
            case .none: break
            }
        }
    }

    private func applyToolEffect(_ tool: MysliTool, enabled: Bool) {
        switch tool {
        case .screenshots: hotkeyManager.screenshotsEnabled = enabled
        case .windows: hotkeyManager.tilingEnabled = enabled
        case .clipboard:
            hotkeyManager.clipboardHistoryEnabled = enabled
            if enabled {
                clipboardHistory.enable()
            } else {
                clipboardHistory.disable()
                if clipboardPanel.isVisible { clipboardPanel.dismiss() }
            }
        case .keepAwake:
            if !enabled { keepAwake.deactivate() }
        case .meetings:
            if enabled { meetingNotes.resumeUnfinished() }
        }
    }

    private func permissionsChanged() {
        updateStatus()
        settingsWindow.renderPermissions(permissions.snapshot)
        // A calendar grant from the Permissions page lets reminders that wait for access start.
        Task { await calendarReminders?.refresh() }
    }

    private func showScreenshotSetupIfNeeded() {
        guard permissionHandlingEnabled, !settings.didShowScreenshotShortcutSetup,
              hotkeyManager.issues.contains(where: { $0.shortcut.isScreenshot && $0.failure == .systemConflict }) else { return }
        settingsWindow.showScreenshotSetupIfNeeded(issues: hotkeyManager.issues)
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
        statusMenu.onShowSettings = { [weak self] in
            self?.settingsWindow.show()
            Task { await self?.calendarReminders?.refresh() }
        }
        statusItem.menu = statusMenu.menu
        NSApp.mainMenu = statusMenu.applicationMenu()
        tools.onChange = { [weak self] in
            guard let self else { return }
            settingsWindow.refresh()
            permissions.refresh()
            permissionsChanged()
        }
        let changeTool: (MysliTool, Bool) -> Void = { [weak self] in self?.tools.setEnabled($0, enabled: $1) }
        settingsWindow.onToolChanged = changeTool
        toolActions.onToolChanged = changeTool
        toolActions.onCaptureArea = { [weak self] in self?.startCapture(.interactive) }
        toolActions.onCaptureScreen = { [weak self] in self?.startCapture(.fullScreen) }
        toolActions.onShowClipboardHistory = { [weak self] in self?.toggleClipboardPanel() }
        settingsWindow.onCalendarRemindersChanged = { [weak self] enabled in
            self?.tools.setCalendarReminders(enabled)
        }
        settingsWindow.onCalendarReminderRulesChanged = { [weak self] in
            Task { await self?.calendarReminders?.refresh() }
        }
        settingsWindow.onPermissionsVisibilityChanged = { [weak self] visible in
            guard let self else { return }
            if visible {
                permissions.refresh()
                permissionsChanged()
                permissions.startPolling()
            } else {
                permissions.stopPolling()
            }
        }
        settingsWindow.onMeetingsFolderChanged = { [weak self] _ in self?.meetingNotes.meetingsFolderChanged() }
        statusMenu.onShowLog = { [weak self] in self?.logWindow.show() }
        statusMenu.onOpenKeyboardSettings = { [weak self] in self?.permissions.openSettings(.keyboardShortcuts) }
    }

    private func setupClipboardHistory() {
        clipboardPanel.bindController()

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
        hotkeyManager.screenshotsEnabled = settings.screenshotShortcutsEnabled
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
        // time so a missing grant opens Permissions instead of capturing a black frame.
        permissions.refresh()
        guard permissions.screenRecording else {
            settingsWindow.show(.permissions)
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
        keepAwake.onDisplayAwakeChanged = { [weak self] enabled in
            self?.settings.keepDisplayAwake = enabled
            self?.settingsWindow.refresh()
        }
        settingsWindow.onKeepScreenOnChanged = { [weak self] in self?.keepAwake.setDisplayAwake($0) }
    }

    private func setupMeetingNotes() {
        meetingNotes.onStateChange = { [weak self] in
            self?.updateStatus()
            self?.calendarReminders?.recorderDidChange()
            self?.notesHosting.activeMeetingChanged()
        }
        meetingRecorder.onShowPermissions = { [weak self] in self?.settingsWindow.show(.permissions) }
        meetingNotes.onCheckWords = { [weak self] in self?.wordReviewWindow.show($0) }
        meetingNotes.onOpenTypedNotes = { [weak self] in self?.openTypedNotes($0) }
        meetingControlsPanel.onWriteNotes = { [weak self] in self?.meetingNotes.openCurrentTypedNotes() }
        meetingControlsPanel.bindRecorder()
        wordReviewWindow.bindController()
    }

    private func openTypedNotes(_ meeting: MeetingFolder) {
        do {
            try notesHosting.open(meeting)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not open meeting notes"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            NSApp.activate()
            alert.runModal()
        }
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
            ? HotkeyHealth(accessibilityMissing: settings.requiredPermissions.permissions.contains(.accessibility)
                           && !permissions.accessibility, issues: hotkeyManager.issues)
            : .healthy
        statusMenu.updateHotkeyHealth(health)
        settingsWindow.permissionsPage.showShortcutConflicts(
            hotkeyManager.issues.filter { $0.shortcut.isScreenshot && $0.failure == .systemConflict }.map(\.shortcut))
        let warning: StatusWarning?
        if health != .healthy {
            warning = .shortcutsUnavailable
        } else if permissionHandlingEnabled && settings.requiredPermissions.permissions.contains(.screenRecording)
                    && !permissions.screenRecording {
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
        statusItem.button?.setAccessibilityLabel(phase.statusDescription.map { "Mysli, \($0)" } ?? "Mysli")
        statusItem.button?.toolTip = phase.statusDescription.map { "Mysli: \($0)" }
        scheduleScreenshotSetup()
    }
}
