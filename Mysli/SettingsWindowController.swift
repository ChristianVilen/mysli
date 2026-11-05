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
    let keepScreenOn = NSSwitch()
    let calendarReminders = NSSwitch()
    let teamsSpeakerNames = NSSwitch()
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
    private let onboarding: Onboarding?
    private var settingsContent: NSView?
    private(set) var onboardingView: OnboardingView?
    private let chooseFolder: Picker
    private let chooseContext: Picker
    private let present: @MainActor (NSWindow) -> Void
    private let activation: OrdinaryWindowActivation
    private let isWindowVisible: (NSWindow) -> Bool
    private var permissionsVisible = false
    private var visibilityObservers: [NSObjectProtocol] = []
    private(set) var selectedPage: SettingsPage = .general
    let pageButtons = SettingsPage.allCases.map { page in
        let button = NSButton(title: page.title, image: page.icon(size: 20), target: nil, action: nil)
        button.tag = page.rawValue
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .glass
        button.alignment = .left
        button.imagePosition = .imageLeading
        button.setAccessibilityLabel(page.title)
        return button
    }
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
            if window?.contentView !== onboardingView { window?.contentView = onboardingView }
            onboardingView?.render()
        } else {
            if window?.contentView !== settingsContent { window?.contentView = settingsContent }
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
            window?.contentView = settingsContent
            refresh()
            selectPage(.general)
            applyDisplayOptions(.current)
        }
        refreshPermissionsVisibility()
    }

    func windowWillClose(_ notification: Notification) {
        setPermissionsVisible(false)
        if let window { activation.close(window) }
    }

    func windowDidMiniaturize(_ notification: Notification) { refreshPermissionsVisibility() }
    func windowDidDeminiaturize(_ notification: Notification) { refreshPermissionsVisibility() }

    private func refreshPermissionsVisibility() {
        let needsPolling = onboarding?.isFinished == false ? onboarding?.step == .permissions : selectedPage == .permissions
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
        calendarReminders.isEnabled = settings.meetingsEnabled
        keepScreenOn.state = settings.keepDisplayAwake ? .on : .off
        calendarReminders.state = settings.calendarRecordingRemindersEnabled ? .on : .off
        teamsSpeakerNames.state = settings.teamsSpeakerNamesEnabled ? .on : .off
        let duration = settings.thumbnailDuration
        thumbnailDuration.removeAllItems()
        for choice in Self.thumbnailChoices {
            thumbnailDuration.addItem(withTitle: choice.title)
            thumbnailDuration.lastItem?.representedObject = choice.duration
        }
        if let item = thumbnailDuration.itemArray.first(where: { $0.representedObject as? Double == duration }) {
            thumbnailDuration.select(item)
        } else {
            thumbnailDuration.addItem(withTitle: "Custom (\(duration) seconds)")
            thumbnailDuration.lastItem?.representedObject = duration
            thumbnailDuration.select(thumbnailDuration.lastItem)
        }
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
            (chooseMeetingsFolder, #selector(folderClicked)), (chooseBackground, #selector(contextClicked)),
            (clearBackground, #selector(clearClicked)), (thumbnailDuration, #selector(durationChanged)),
            (summaryTool, #selector(toolChanged))
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
        keepScreenOn.setAccessibilityLabel("Keep screen on")
        calendarReminders.setAccessibilityLabel("Calendar recording reminders")
        teamsSpeakerNames.setAccessibilityLabel("Teams speaker names")
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
                    SettingsLayout.row("Teams speaker names", detail: "Experimental. After Stop, names remote speakers from the Teams app. Applies from the next recording.",
                                       control: teamsSpeakerNames)
                ])
            ]),
            .permissions: permissions,
            .help: helpPage
        ]
        let root = SettingsBackground()
        settingsContent = root
        window?.contentView = root
        let sidebar = SettingsGlass(radius: 16)
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)
        let brand = Self.brandHeader()
        let navigation = SettingsLayout.stack(spacing: 4)
        SettingsLayout.add(brand, to: navigation)
        navigation.setCustomSpacing(20, after: brand)
        for button in pageButtons {
            button.target = self
            button.action = #selector(pageClicked(_:))
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            SettingsLayout.add(button, to: navigation)
        }
        navigation.setCustomSpacing(16, after: pageButtons[SettingsPage.meetings.rawValue])
        navigation.translatesAutoresizingMaskIntoConstraints = false
        sidebar.content.addSubview(navigation)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            sidebar.widthAnchor.constraint(equalToConstant: 210),
            navigation.leadingAnchor.constraint(equalTo: sidebar.content.leadingAnchor, constant: 12),
            navigation.trailingAnchor.constraint(equalTo: sidebar.content.trailingAnchor, constant: -12),
            navigation.topAnchor.constraint(equalTo: sidebar.content.topAnchor, constant: 24)
        ])
        pages = contents.mapValues(SettingsLayout.scroll)
        for scroll in pages.values {
            scroll.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 2),
                scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: root.topAnchor),
                scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor)
            ])
        }
        window?.initialFirstResponder = launchAtLogin
        selectPage(.general)
        applyDisplayOptions(.current)
    }

    /// The app icon, the name, and the tagline at the top of the sidebar.
    private static func brandHeader() -> NSView {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.setAccessibilityElement(false)
        icon.widthAnchor.constraint(equalToConstant: 36).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 36).isActive = true
        let name = SettingsLayout.label("Mysli")
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        let words = SettingsLayout.stack([name, SettingsLayout.label("A daily mix of Mac tools", size: 11, secondary: true)], spacing: 1)
        let header = NSStackView(views: [icon, words])
        header.spacing = 8
        return header
    }

    @objc private func pageClicked(_ sender: NSButton) {
        guard let page = SettingsPage(rawValue: sender.tag) else { return }
        selectPage(page)
    }

    private func selectPage(_ page: SettingsPage) {
        selectedPage = page
        for (candidate, scroll) in pages { scroll.isHidden = candidate != page }
        for button in pageButtons {
            let selected = button.tag == page.rawValue
            button.state = selected ? .on : .off
            button.isBordered = selected
            button.contentTintColor = selected ? .controlAccentColor : .labelColor
        }
        updateKeyViewLoop()
        window?.makeFirstResponder(pageButtons[page.rawValue])
        refreshPermissionsVisibility()
    }

    private func updateKeyViewLoop() {
        let controls: [NSView] = switch selectedPage {
        case .general: [launchAtLogin]
        case .screenshots: [screenshotShortcuts, thumbnailDuration]
        case .clipboard: [clipboardHistory]
        case .windows: [windowTiling]
        case .keepAwake: [keepAwakeEnabled, keepScreenOn]
        case .meetings: [meetingsEnabled, chooseMeetingsFolder, summaryTool, chooseBackground, clearBackground, calendarReminders, teamsSpeakerNames]
        case .permissions: permissionsPage.controls
        case .help: helpPage.controls
        }
        let keyViews: [NSView] = pageButtons + controls + (guides[selectedPage]?.buttons ?? [])
        for (control, next) in zip(keyViews, keyViews.dropFirst() + [pageButtons[0]]) { control.nextKeyView = next }
    }

    func applyDisplayOptions(_ options: SettingsDisplayOptions) {
        func apply(in view: NSView) {
            (view as? SettingsBackground)?.apply(options)
            (view as? SettingsGlass)?.apply(options)
            for child in view.subviews { apply(in: child) }
        }
        for button in pageButtons { button.bezelStyle = options.reduceTransparency ? .push : .glass }
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

    @objc private func tilingChanged() {
        onToolChanged?(.windows, windowTiling.state == .on)
    }

    @objc private func clipboardChanged() {
        onToolChanged?(.clipboard, clipboardHistory.state == .on)
    }

    @objc private func calendarChanged() {
        onCalendarRemindersChanged?(calendarReminders.state == .on)
    }

    func showCalendarStatus(_ status: CalendarReminderController.Status) {
        refreshPermissionRequirements()
        calendarReminders.state = settings.calendarRecordingRemindersEnabled ? .on : .off
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
