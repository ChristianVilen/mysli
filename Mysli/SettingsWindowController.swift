import Cocoa

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let thumbnailChoices: [(title: String, duration: Double)] = [
        ("3 seconds", 3), ("5 seconds", 5), ("15 seconds", 15), ("Forever", 0)
    ]
    typealias Picker = @MainActor (NSWindow, URL?, @escaping (URL?) -> Void) -> Void
    let launchAtLogin = NSSwitch()
    let screenshotShortcuts = NSSwitch()
    let windowTiling = NSSwitch()
    let clipboardHistory = NSSwitch()
    let keepAwakeEnabled = NSSwitch()
    let meetingsEnabled = NSSwitch()
    let dictationEnabled = NSSwitch()
    let dictationNearbyText = NSSwitch()
    let dictationKey = NSPopUpButton()
    let dictationKeyboard = NSButton(title: "Open Keyboard Settings…", target: nil, action: nil)
    let keepScreenOn = NSSwitch()
    let calendarReminders = NSSwitch()
    let teamsSpeakerNames = NSSwitch()
    let calendarReminderTime = NSPopUpButton()
    let calendarReminderEvents = NSPopUpButton()
    let thumbnailDuration = NSPopUpButton()
    let summaryTool = NSPopUpButton()
    let chooseMeetingsFolder = NSButton(title: "Choose…", target: nil, action: nil)
    let chooseBackground = NSButton(title: "Choose…", target: nil, action: nil)
    let clearBackground = NSButton(title: "Clear", target: nil, action: nil)
    let loginError = NSTextField(wrappingLabelWithString: "")
    let calendarStatus = NSTextField(wrappingLabelWithString: "")
    private let folderPath = NSTextField(labelWithString: "")
    private let backgroundPath = NSTextField(labelWithString: "")
    private let settings: Settings
    let sidebar = SettingsSidebarController()
    private let onboarding: Onboarding?
    private let settingsContent = NSSplitViewController()
    private let pageContainer = SettingsBackground()
    private(set) var onboardingView: OnboardingView?
    private let chooseFolder: Picker
    private let chooseContext: Picker
    private let present: @MainActor (NSWindow) -> Void
    private let activation: OrdinaryWindowActivation
    private let isWindowVisible: (NSWindow) -> Bool
    private var permissionsVisible = false
    private var visibilityObservers: [NSObjectProtocol] = []
    private(set) var selectedPage: SettingsPage = .general
    private(set) var pages: [SettingsPage: NSScrollView] = [:]
    private(set) var guides: [SettingsPage: SettingsGuides] = [:]
    let permissionsPage: SettingsPermissionsView
    let helpPage: SettingsHelpView
    private var displayObserver: NSObjectProtocol?
    var onToolChanged: ((MysliTool, Bool) -> Void)?
    var onKeepScreenOnChanged: ((Bool) -> Void)?
    var onPermissionsVisibilityChanged: ((Bool) -> Void)?
    var onMeetingsFolderChanged: ((URL) -> Void)?
    var onCalendarRemindersChanged: ((Bool) -> Void)?
    var onCalendarReminderRulesChanged: (() -> Void)?
    var onDictationKeyChanged: (() -> Void)?
    var onDictationKeyboardSettings: (() -> Void)?

    init(settings: Settings,
         onboarding: Onboarding? = nil,
         permissionActions: PermissionActions = .inert,
         openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
         chooseFolder: @escaping Picker = SettingsWindowController.folderPicker,
         chooseContext: @escaping Picker = SettingsWindowController.contextPicker,
         present: @escaping @MainActor (NSWindow) -> Void = SettingsWindowController.presentWindow,
         activation: OrdinaryWindowActivation = .shared,
         isWindowVisible: @escaping (NSWindow) -> Bool = { $0.isVisible && !$0.isMiniaturized && !NSApp.isHidden }) {
        self.settings = settings
        self.onboarding = onboarding
        permissionsPage = SettingsPermissionsView(actions: permissionActions)
        helpPage = SettingsHelpView(openURL: openURL)
        self.chooseFolder = chooseFolder
        self.chooseContext = chooseContext
        self.present = present
        self.activation = activation
        self.isWindowVisible = isWindowVisible
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 700),
                                    styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        window.title = "Mysli"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 640, height: 420)
        super.init(window: window)
        window.delegate = self
        buildForm()
        if let onboarding, !onboarding.isFinished {
            let view = OnboardingView(model: onboarding, actions: permissionActions)
            view.onChange = { [weak self] in self?.onboardingChanged() }
            onboardingView = view
        }
        refreshPermissionRequirements()
        displayObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyDisplayOptions(.current) }
        }
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            visibilityObservers.append(NotificationCenter.default.addObserver(forName: name, object: NSApp, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshPermissionsVisibility() }
            })
        }
    }

    isolated deinit {
        if let displayObserver { NSWorkspace.shared.notificationCenter.removeObserver(displayObserver) }
        for observer in visibilityObservers { NotificationCenter.default.removeObserver(observer) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func presentWindow(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    func show(_ page: SettingsPage = .general) {
        loginError.stringValue = ""
        loginError.isHidden = true
        refresh()
        if let onboarding, !onboarding.isFinished {
            if window?.contentView !== onboardingView {
                window?.contentViewController = nil
                window?.contentView = onboardingView
            }
            onboardingView?.render()
        } else {
            if window?.contentViewController !== settingsContent { showSettingsContent() }
            selectPage(page)
        }
        guard let window else { return }
        activation.open(window)
        present(window)
        if onboarding?.isFinished == false { window.makeFirstResponder(onboardingView?.controls.first) }
        refreshPermissionsVisibility()
    }

    private func onboardingChanged() {
        if onboarding?.isFinished == true {
            showSettingsContent()
            refresh()
            selectPage(.general)
            applyDisplayOptions(.current)
        }
        refreshPermissionsVisibility()
    }

    private func showSettingsContent() {
        guard let window else { return }
        let size = window.contentLayoutRect.size
        settingsContent.view.setFrameSize(size)
        window.contentViewController = settingsContent
        window.setContentSize(size)
    }

    func windowWillClose(_ notification: Notification) {
        setPermissionsVisible(false)
        if let window { activation.close(window) }
    }

    func windowDidMiniaturize(_ notification: Notification) { refreshPermissionsVisibility() }
    func windowDidDeminiaturize(_ notification: Notification) { refreshPermissionsVisibility() }

    private func refreshPermissionsVisibility() {
        let needsPolling = onboarding?.isFinished == false ? onboarding?.step == .permissions
            : selectedPage == .permissions || selectedPage == .dictation
        setPermissionsVisible(needsPolling && window.map(isWindowVisible) == true)
    }

    private func setPermissionsVisible(_ visible: Bool) {
        guard visible != permissionsVisible else { return }
        permissionsVisible = visible
        onPermissionsVisibilityChanged?(visible)
    }

    func renderPermissions(_ snapshot: PermissionSnapshot) {
        refreshPermissionRequirements()
        permissionsPage.permissionList.render(snapshot)
        onboardingView?.renderPermissions(snapshot)
    }

    private func refreshPermissionRequirements() {
        permissionsPage.showRequired(settings.requiredPermissions, screenshotShortcuts: settings.screenshotShortcutsEnabled)
        if selectedPage == .permissions { updateKeyViewLoop() }
    }

    @discardableResult
    func showScreenshotSetupIfNeeded(issues: [HotkeyRegistrationIssue]) -> Bool {
        let conflicts = issues.filter { $0.shortcut.isScreenshot && $0.failure == .systemConflict }.map(\.shortcut)
        guard onboarding?.isFinished != false, !conflicts.isEmpty, !settings.didShowScreenshotShortcutSetup else { return false }
        permissionsPage.showShortcutConflicts(conflicts)
        show(.permissions)
        // The guidance shows only once, so keep the flag unset while the app is hidden or the window is minimized.
        guard permissionsVisible else { return false }
        permissionsPage.revealShortcutSetup()
        settings.didShowScreenshotShortcutSetup = true
        return true
    }

    /// Shows the saved preferences, also after the menu changed one while the window is open.
    func refresh() {
        refreshPermissionRequirements()
        launchAtLogin.state = settings.launchAtLogin ? .on : .off
        screenshotShortcuts.state = settings.screenshotShortcutsEnabled ? .on : .off
        windowTiling.state = settings.windowTilingEnabled ? .on : .off
        clipboardHistory.state = settings.clipboardHistoryEnabled ? .on : .off
        keepAwakeEnabled.state = settings.keepAwakeEnabled ? .on : .off
        meetingsEnabled.state = settings.meetingsEnabled ? .on : .off
        dictationEnabled.state = settings.dictationEnabled ? .on : .off
        dictationNearbyText.state = settings.dictationNearbyText ? .on : .off
        dictationKey.selectItem(at: settings.dictationKeyMode == .fn ? 0 : 1)
        calendarReminders.isEnabled = settings.meetingsEnabled
        keepScreenOn.state = settings.keepDisplayAwake ? .on : .off
        calendarReminders.state = settings.calendarRecordingRemindersEnabled ? .on : .off
        teamsSpeakerNames.state = settings.teamsSpeakerNamesEnabled ? .on : .off
        refreshCalendarReminderRules()
        let duration = settings.thumbnailDuration
        thumbnailDuration.removeAllItems()
        for choice in Self.thumbnailChoices {
            thumbnailDuration.addItem(withTitle: choice.title)
            thumbnailDuration.lastItem?.representedObject = choice.duration
        }
        Self.select(duration, in: thumbnailDuration, customTitle: "Custom (\(duration) seconds)")
        summaryTool.select(summaryTool.itemArray.first { $0.representedObject as? SummaryTool == settings.summaryTool })
        folderPath.stringValue = settings.meetingsFolder.path
        backgroundPath.stringValue = settings.meetingContextFile?.path ?? "None"
        folderPath.toolTip = folderPath.stringValue
        backgroundPath.toolTip = backgroundPath.stringValue
        folderPath.setAccessibilityValue(folderPath.stringValue)
        backgroundPath.setAccessibilityValue(backgroundPath.stringValue)
        clearBackground.isEnabled = settings.meetingContextFile != nil
    }

    private func buildForm() {
        for (control, action) in [
            (launchAtLogin, #selector(loginChanged)), (screenshotShortcuts, #selector(screenshotsChanged)),
            (windowTiling, #selector(tilingChanged)), (clipboardHistory, #selector(clipboardChanged)),
            (keepAwakeEnabled, #selector(keepAwakeChanged)), (meetingsEnabled, #selector(meetingsChanged)),
            (keepScreenOn, #selector(keepScreenOnChanged)), (calendarReminders, #selector(calendarChanged)), (teamsSpeakerNames, #selector(teamsChanged)),
            (calendarReminderTime, #selector(calendarReminderTimeChanged)),
            (calendarReminderEvents, #selector(calendarReminderEventsChanged)),
            (chooseMeetingsFolder, #selector(folderClicked)), (chooseBackground, #selector(contextClicked)),
            (clearBackground, #selector(clearClicked)), (thumbnailDuration, #selector(durationChanged)),
            (summaryTool, #selector(toolChanged)),
            (dictationEnabled, #selector(dictationChanged)), (dictationNearbyText, #selector(nearbyTextChanged)),
            (dictationKey, #selector(dictationKeyChanged)), (dictationKeyboard, #selector(openDictationKeyboard))
        ] as [(NSControl, Selector)] {
            control.target = self
            control.action = action
        }
        thumbnailDuration.setAccessibilityLabel("Show thumbnail for")
        launchAtLogin.setAccessibilityLabel("Launch at login")
        screenshotShortcuts.setAccessibilityLabel("Use Mysli for screenshots")
        windowTiling.setAccessibilityLabel("Enable window tiling")
        clipboardHistory.setAccessibilityLabel("Record clipboard history")
        keepAwakeEnabled.setAccessibilityLabel("Enable Keep Awake")
        meetingsEnabled.setAccessibilityLabel("Enable Meetings")
        dictationEnabled.setAccessibilityLabel("Enable Dictation and send dictated words to Claude")
        dictationNearbyText.setAccessibilityLabel("Send text near the cursor")
        dictationKey.setAccessibilityLabel("Dictation key")
        dictationKeyboard.setAccessibilityLabel("Open Keyboard Settings for Fn")
        dictationKey.addItems(withTitles: ["Fn / Globe", "Control + Option + D"])
        keepScreenOn.setAccessibilityLabel("Keep screen on")
        calendarReminders.setAccessibilityLabel("Calendar recording reminders")
        teamsSpeakerNames.setAccessibilityLabel("Teams speaker names")
        calendarReminderTime.setAccessibilityLabel("Remind me")
        calendarReminderEvents.setAccessibilityLabel("Remind for")
        for minutes in [0, 1, 2, 5] {
            calendarReminderTime.addItem(withTitle: minutes == 0 ? "At start"
                                         : "\(minutes) \(minutes == 1 ? "minute" : "minutes") before")
            calendarReminderTime.lastItem?.representedObject = minutes
        }
        for (title, needsLink) in [("All events", false), ("Only events with a video meeting link", true)] {
            calendarReminderEvents.addItem(withTitle: title)
            calendarReminderEvents.lastItem?.representedObject = needsLink
        }
        summaryTool.setAccessibilityLabel("Summary tool")
        chooseMeetingsFolder.setAccessibilityLabel("Choose meetings folder")
        chooseBackground.setAccessibilityLabel("Choose background file")
        clearBackground.setAccessibilityLabel("Clear background file")
        folderPath.setAccessibilityLabel("Meetings folder")
        backgroundPath.setAccessibilityLabel("Background file")
        for tool in SummaryTool.allCases {
            summaryTool.addItem(withTitle: tool.title)
            summaryTool.lastItem?.representedObject = tool
        }
        func column(_ views: [NSView]) -> NSView {
            let column = SettingsLayout.stack(spacing: 6)
            for view in views { SettingsLayout.add(view, to: column) }
            return column
        }
        func pathRow(_ title: String, path: NSTextField, buttons: [NSView]) -> NSView {
            column([SettingsLayout.row(title, control: NSStackView(views: buttons)), path])
        }
        func note(_ text: String) -> NSView { SettingsLayout.label(text, size: 11, secondary: true) }
        loginError.textColor = .systemRed
        loginError.isHidden = true
        calendarStatus.isHidden = true
        for label in [folderPath, backgroundPath] {
            label.lineBreakMode = .byTruncatingMiddle
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        for page in SettingsPage.allCases where !page.guides.isEmpty {
            guides[page] = SettingsGuides(page.guides)
        }
        func toolPage(_ page: SettingsPage, _ views: [NSView]) -> NSView {
            let content = SettingsLayout.page(title: page.title, subtitle: page.subtitle)
            for view in views { SettingsLayout.add(view, to: content) }
            if !page.shortcuts.isEmpty {
                SettingsLayout.add(SettingsLayout.sectionTitle("Shortcuts"), to: content)
                SettingsLayout.add(SettingsShortcuts.group(page.shortcuts), to: content)
            }
            if let guide = guides[page] {
                SettingsLayout.add(SettingsLayout.sectionTitle("Guide"), to: content)
                SettingsLayout.add(guide.view, to: content)
            }
            return content
        }
        let permissions = SettingsLayout.stack(spacing: 14)
        SettingsLayout.add(permissionsPage, to: permissions)
        if let guide = guides[.permissions] {
            SettingsLayout.add(SettingsLayout.sectionTitle("Guide"), to: permissions)
            SettingsLayout.add(guide.view, to: permissions)
        }
        let contents: [SettingsPage: NSView] = [
            .general: toolPage(.general, [
                SettingsLayout.group([column([SettingsLayout.row("Launch at login", control: launchAtLogin), loginError])])
            ]),
            .screenshots: toolPage(.screenshots, [SettingsLayout.group([
                SettingsLayout.row("Use Mysli for screenshots", detail: "When off, Shift + Command + 3 and 4 go back to macOS.",
                                   control: screenshotShortcuts),
                SettingsLayout.row("Show thumbnail for", control: thumbnailDuration)
            ])]),
            .clipboard: toolPage(.clipboard, [SettingsLayout.group([
                SettingsLayout.row("Clipboard history", detail: "Keep recent copies until you quit Mysli.", control: clipboardHistory)
            ])]),
            .windows: toolPage(.windows, [SettingsLayout.group([
                SettingsLayout.row("Window tiling", detail: "Move windows with Control + Option.", control: windowTiling)
            ])]),
            .keepAwake: toolPage(.keepAwake, [
                SettingsLayout.group([
                    SettingsLayout.row("Keep Awake", control: keepAwakeEnabled),
                    SettingsLayout.row("Keep screen on", detail: "The display stays awake too while a session runs.",
                                                         control: keepScreenOn)]),
                note("Start a session from the Mysli menu.")
            ]),
            .meetings: toolPage(.meetings, [
                SettingsLayout.group([
                    SettingsLayout.row("Meetings", control: meetingsEnabled),
                    pathRow("Meetings folder", path: folderPath, buttons: [chooseMeetingsFolder]),
                    SettingsLayout.row("Summary tool", control: summaryTool)
                ]),
                note("Automatic tries Antigravity, then Claude Code. An explicit choice uses only that tool. Changes apply when the next job starts."),
                SettingsLayout.group([pathRow("Background file", path: backgroundPath, buttons: [chooseBackground, clearBackground])]),
                note("The complete background file goes with the transcript. Automatic may send it to both providers on fallback. Clear keeps the file."),
                SettingsLayout.group([
                    column([SettingsLayout.row("Calendar reminders", detail: "Calendar events offer recording reminders. Mysli never starts or stops recording automatically.",
                                               control: calendarReminders), calendarStatus]),
                    SettingsLayout.row("Remind me", control: calendarReminderTime),
                    SettingsLayout.row("Remind for", detail: "A video meeting link is a Teams, Google Meet, or Zoom link in the event notes, location, or URL.",
                                       control: calendarReminderEvents),
                    SettingsLayout.row("Teams speaker names", detail: "Experimental. After Stop, names remote speakers from the Teams app. Applies from the next recording.",
                                       control: teamsSpeakerNames)
                ])
            ]),
            .dictation: toolPage(.dictation, [
                SettingsLayout.group([
                    SettingsLayout.row("Dictation", detail: "Send dictated words to Claude Haiku for polish, then paste them.", control: dictationEnabled),
                    SettingsLayout.row("Hold to dictate", control: dictationKey),
                    SettingsLayout.row("Send text near the cursor", detail: "Share up to 500 characters before the cursor with Claude. Secure fields are excluded.", control: dictationNearbyText)
                ]),
                note("Fn needs Input Monitoring. Both options need Microphone and Accessibility. Grant them on the Permissions page."),
                note("For Fn, set ‘Press 🌐 key to’ to ‘Do Nothing’ in Keyboard Settings. Mysli never changes this setting."),
                dictationKeyboard
            ]),
            .permissions: permissions,
            .help: helpPage
        ]
        let root = pageContainer
        pages = contents.mapValues(SettingsLayout.scroll)
        if let general = pages[.general] { SettingsLayout.fill(general, in: root) }
        let detail = NSViewController()
        detail.view = root
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = 210
        sidebarItem.maximumThickness = 260
        sidebarItem.holdingPriority = .defaultHigh
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 400
        settingsContent.splitView.isVertical = true
        settingsContent.splitView.dividerStyle = .thin
        settingsContent.addSplitViewItem(sidebarItem)
        settingsContent.addSplitViewItem(detailItem)
        showSettingsContent()
        sidebar.onSelect = { [weak self] page in
            guard let self, selectedPage != page else { return }
            selectPage(page)
        }
        window?.initialFirstResponder = launchAtLogin
        selectPage(.general)
        applyDisplayOptions(.current)
    }

    private func selectPage(_ page: SettingsPage) {
        let changed = selectedPage != page
        selectedPage = page
        for (candidate, scroll) in pages {
            scroll.isHidden = candidate != page
            if candidate != page { scroll.removeFromSuperview() }
        }
        if let scroll = pages[page], scroll.superview !== pageContainer { SettingsLayout.fill(scroll, in: pageContainer) }
        if changed { applyDisplayOptions(.current) }
        sidebar.select(page)
        updateKeyViewLoop()
        window?.makeFirstResponder(sidebar.tableView)
        refreshPermissionsVisibility()
    }

    private func updateKeyViewLoop() {
        let controls: [NSView] = switch selectedPage {
        case .general: [launchAtLogin]
        case .screenshots: [screenshotShortcuts, thumbnailDuration]
        case .clipboard: [clipboardHistory]
        case .windows: [windowTiling]
        case .keepAwake: [keepAwakeEnabled, keepScreenOn]
        case .meetings: [meetingsEnabled, chooseMeetingsFolder, summaryTool, chooseBackground, clearBackground, calendarReminders, calendarReminderTime, calendarReminderEvents, teamsSpeakerNames]
        case .dictation: [dictationEnabled, dictationKey, dictationNearbyText, dictationKeyboard]
        case .permissions: permissionsPage.controls
        case .help: helpPage.controls
        }
        let keyViews: [NSView] = [sidebar.tableView] + controls + (guides[selectedPage]?.buttons ?? [])
        for (control, next) in zip(keyViews, keyViews.dropFirst() + [sidebar.tableView]) { control.nextKeyView = next }
    }

    func applyDisplayOptions(_ options: SettingsDisplayOptions) {
        func apply(in view: NSView) {
            (view as? SettingsBackground)?.apply(options)
            (view as? SettingsGlass)?.apply(options)
            for child in view.subviews { apply(in: child) }
        }
        if let root = window?.contentView { apply(in: root) }
    }

    @objc private func loginChanged() {
        let failure = settings.setLaunchAtLogin(launchAtLogin.state == .on)
        loginError.stringValue = failure.map { "Could not change launch at login. \($0)" } ?? ""
        loginError.isHidden = failure == nil
        launchAtLogin.state = settings.launchAtLogin ? .on : .off
    }

    @objc private func screenshotsChanged() {
        onToolChanged?(.screenshots, screenshotShortcuts.state == .on)
    }

    @objc private func keepScreenOnChanged() {
        settings.keepDisplayAwake = keepScreenOn.state == .on
        onKeepScreenOnChanged?(settings.keepDisplayAwake)
    }

    @objc private func keepAwakeChanged() {
        onToolChanged?(.keepAwake, keepAwakeEnabled.state == .on)
    }

    @objc private func meetingsChanged() {
        onToolChanged?(.meetings, meetingsEnabled.state == .on)
    }

    @objc private func dictationChanged() {
        onToolChanged?(.dictation, dictationEnabled.state == .on)
    }

    @objc private func nearbyTextChanged() {
        settings.dictationNearbyText = dictationNearbyText.state == .on
    }

    @objc private func dictationKeyChanged() {
        settings.dictationKeyMode = dictationKey.indexOfSelectedItem == 0 ? .fn : .carbon
        refreshPermissionRequirements()
        onDictationKeyChanged?()
    }

    @objc private func openDictationKeyboard() { onDictationKeyboardSettings?() }

    @objc private func tilingChanged() {
        onToolChanged?(.windows, windowTiling.state == .on)
    }

    @objc private func clipboardChanged() {
        onToolChanged?(.clipboard, clipboardHistory.state == .on)
    }

    @objc private func calendarChanged() {
        onCalendarRemindersChanged?(calendarReminders.state == .on)
    }

    @objc private func calendarReminderTimeChanged() {
        guard let minutes = calendarReminderTime.selectedItem?.representedObject as? Int else { return }
        settings.calendarReminderLeadMinutes = minutes
        onCalendarReminderRulesChanged?()
    }

    @objc private func calendarReminderEventsChanged() {
        guard let needsLink = calendarReminderEvents.selectedItem?.representedObject as? Bool else { return }
        settings.calendarRemindersNeedVideoLink = needsLink
        onCalendarReminderRulesChanged?()
    }

    /// Selects the item that holds `value`. A saved value that no item holds gets its own item.
    private static func select<Value: Equatable>(_ value: Value, in menu: NSPopUpButton, customTitle: String) {
        if !menu.itemArray.contains(where: { $0.representedObject as? Value == value }) {
            menu.addItem(withTitle: customTitle)
            menu.lastItem?.representedObject = value
        }
        menu.select(menu.itemArray.first { $0.representedObject as? Value == value })
    }

    private func refreshCalendarReminderRules() {
        let lead = settings.calendarReminderLeadMinutes
        Self.select(lead, in: calendarReminderTime, customTitle: "\(lead) minutes before")
        Self.select(settings.calendarRemindersNeedVideoLink, in: calendarReminderEvents, customTitle: "")
        for control in [calendarReminderTime, calendarReminderEvents] {
            control.isEnabled = settings.meetingsEnabled && settings.calendarRecordingRemindersEnabled
        }
    }

    func showCalendarStatus(_ status: CalendarReminderController.Status) {
        refreshPermissionRequirements()
        calendarReminders.state = settings.calendarRecordingRemindersEnabled ? .on : .off
        refreshCalendarReminderRules()
        let text = switch status {
        case .off, .ready: ""
        case .requestingAccess: "Asking for Calendar access…"
        case .calendarAccessRequired: "Allow Calendar access for Mysli in System Settings > Privacy & Security > Calendars."
        case .notificationsRequired: "Allow notifications for Mysli in System Settings > Notifications."
        case .readFailed: "Mysli could not read your calendars. It tries again every minute."
        }
        calendarStatus.stringValue = text
        calendarStatus.isHidden = text.isEmpty
        calendarStatus.textColor = status == .requestingAccess ? .secondaryLabelColor : .systemRed
    }

    @objc private func teamsChanged() {
        settings.teamsSpeakerNamesEnabled = teamsSpeakerNames.state == .on
    }

    @objc private func durationChanged() {
        guard let duration = thumbnailDuration.selectedItem?.representedObject as? Double else { return }
        settings.thumbnailDuration = duration
    }

    @objc private func toolChanged() {
        guard let tool = summaryTool.selectedItem?.representedObject as? SummaryTool else { return }
        settings.summaryTool = tool
    }

    @objc private func folderClicked() {
        guard let window else { return }
        chooseFolder(window, settings.meetingsFolder) { [weak self] url in
            guard let self, let url else { return }
            settings.meetingsFolder = url
            refresh()
            onMeetingsFolderChanged?(url)
        }
    }

    @objc private func contextClicked() {
        guard let window else { return }
        chooseContext(window, settings.meetingContextFile) { [weak self] url in
            guard let self, let url else { return }
            settings.meetingContextFile = url
            refresh()
        }
    }

    @objc private func clearClicked() {
        settings.meetingContextFile = nil
        refresh()
    }

    static func folderPicker(_ window: NSWindow, _ current: URL?, _ completion: @escaping (URL?) -> Void) {
        pick(window, current: current, directory: true, completion: completion)
    }

    static func contextPicker(_ window: NSWindow, _ current: URL?, _ completion: @escaping (URL?) -> Void) {
        pick(window, current: current?.deletingLastPathComponent(), directory: false, completion: completion)
    }

    private static func pick(_ window: NSWindow, current: URL?, directory: Bool, completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = directory
        panel.canChooseFiles = !directory
        panel.canCreateDirectories = directory
        panel.allowsMultipleSelection = false
        panel.directoryURL = current
        panel.prompt = "Choose"
        panel.title = directory ? "Choose meetings folder" : "Choose background file"
        panel.beginSheetModal(for: window) { result in completion(result == .OK ? panel.url : nil) }
    }
}
