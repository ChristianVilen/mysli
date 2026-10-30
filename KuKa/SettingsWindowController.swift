import Cocoa

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let thumbnailChoices: [(title: String, duration: Double)] = [
        ("3 seconds", 3), ("5 seconds", 5), ("15 seconds", 15), ("Forever", 0)
    ]
    typealias Picker = @MainActor (NSWindow, URL?, @escaping (URL?) -> Void) -> Void
    let launchAtLogin = NSSwitch()
    let windowTiling = NSSwitch()
    let clipboardHistory = NSSwitch()
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
    private let chooseFolder: Picker
    private let chooseContext: Picker
    private let present: (NSWindow) -> Void
    private let activation: OrdinaryWindowActivation
    private let isWindowVisible: (NSWindow) -> Bool
    private var permissionsVisible = false
    private var visibilityObservers: [NSObjectProtocol] = []
    private(set) var selectedPage: SettingsPage = .settings
    let pageButtons = SettingsPage.allCases.map { page in
        let button = NSButton(title: page.title, image: NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil)!, target: nil, action: nil)
        button.tag = page.rawValue
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .glass
        button.alignment = .left
        button.imagePosition = .imageLeading
        button.setAccessibilityLabel(page.title)
        return button
    }
    private var pages: [SettingsPage: NSScrollView] = [:]
    let instructions = SettingsInstructionsView()
    let permissionsPage: SettingsPermissionsView
    let helpPage: SettingsHelpView
    private var displayObserver: NSObjectProtocol?
    var onTilingChanged: ((Bool) -> Void)?
    var onClipboardChanged: ((Bool) -> Void)?
    var onPermissionsVisibilityChanged: ((Bool) -> Void)?
    var onMeetingsFolderChanged: ((URL) -> Void)?
    var onCalendarRemindersChanged: ((Bool) -> Void)?

    init(settings: Settings,
         permissionActions: PermissionActions = .inert,
         openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
         chooseFolder: @escaping Picker = SettingsWindowController.folderPicker,
         chooseContext: @escaping Picker = SettingsWindowController.contextPicker,
         present: @escaping (NSWindow) -> Void = SettingsWindowController.presentWindow,
         activation: OrdinaryWindowActivation = .shared,
         isWindowVisible: @escaping (NSWindow) -> Bool = { $0.isVisible && !$0.isMiniaturized && !NSApp.isHidden }) {
        self.settings = settings
        permissionsPage = SettingsPermissionsView(actions: permissionActions)
        helpPage = SettingsHelpView(openURL: openURL)
        self.chooseFolder = chooseFolder
        self.chooseContext = chooseContext
        self.present = present
        self.activation = activation
        self.isWindowVisible = isWindowVisible
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 700),
                                    styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        window.title = "Ku-Ka"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 640, height: 420)
        super.init(window: window)
        window.delegate = self
        buildForm()
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

    func show(_ page: SettingsPage = .settings) {
        loginError.stringValue = ""
        loginError.isHidden = true
        refresh()
        selectPage(page)
        guard let window else { return }
        activation.open(window)
        present(window)
        refreshPermissionsVisibility()
    }

    func windowWillClose(_ notification: Notification) {
        setPermissionsVisible(false)
        if let window { activation.close(window) }
    }

    func windowDidMiniaturize(_ notification: Notification) { refreshPermissionsVisibility() }
    func windowDidDeminiaturize(_ notification: Notification) { refreshPermissionsVisibility() }

    private func refreshPermissionsVisibility() {
        setPermissionsVisible(selectedPage == .permissions && window.map(isWindowVisible) == true)
    }

    private func setPermissionsVisible(_ visible: Bool) {
        guard visible != permissionsVisible else { return }
        permissionsVisible = visible
        onPermissionsVisibilityChanged?(visible)
    }

    func renderPermissions(_ snapshot: PermissionSnapshot) { permissionsPage.render(snapshot) }

    @discardableResult
    func showScreenshotSetupIfNeeded(issues: [HotkeyRegistrationIssue]) -> Bool {
        let conflicts = issues.filter { $0.shortcut.isScreenshot && $0.failure == .systemConflict }.map(\.shortcut)
        guard !conflicts.isEmpty, !settings.didShowScreenshotShortcutSetup else { return false }
        permissionsPage.showShortcutConflicts(conflicts)
        show(.permissions)
        guard permissionsVisible else { return false }
        permissionsPage.revealShortcutSetup()
        settings.didShowScreenshotShortcutSetup = true
        return true
    }

    private func refresh() {
        launchAtLogin.state = settings.launchAtLogin ? .on : .off
        windowTiling.state = settings.windowTilingEnabled ? .on : .off
        clipboardHistory.state = settings.clipboardHistoryEnabled ? .on : .off
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
            (launchAtLogin, #selector(loginChanged)), (windowTiling, #selector(tilingChanged)),
            (clipboardHistory, #selector(clipboardChanged)),
            (calendarReminders, #selector(calendarChanged)), (teamsSpeakerNames, #selector(teamsChanged)),
            (chooseMeetingsFolder, #selector(folderClicked)), (chooseBackground, #selector(contextClicked)),
            (clearBackground, #selector(clearClicked)), (thumbnailDuration, #selector(durationChanged)),
            (summaryTool, #selector(toolChanged))
        ] as [(NSControl, Selector)] {
            control.target = self
            control.action = action
        }
        thumbnailDuration.setAccessibilityLabel("Show thumbnail for")
        launchAtLogin.setAccessibilityLabel("Launch at login")
        windowTiling.setAccessibilityLabel("Enable window tiling")
        clipboardHistory.setAccessibilityLabel("Record clipboard history")
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
        let content = SettingsLayout.page(title: "Settings", subtitle: "Make Ku-Ka work your way.")
        func add(_ view: NSView) { SettingsLayout.add(view, to: content) }
        func column(_ views: [NSView]) -> NSView {
            let column = SettingsLayout.stack(spacing: 6)
            for view in views { SettingsLayout.add(view, to: column) }
            return column
        }
        func pathRow(_ title: String, path: NSTextField, buttons: [NSView]) -> NSView {
            column([SettingsLayout.row(title, control: NSStackView(views: buttons)), path])
        }
        add(SettingsLayout.heading("General", symbol: "gearshape.fill", color: .systemBlue))
        add(SettingsLayout.group([
            column([SettingsLayout.row("Launch at login", control: launchAtLogin), loginError]),
            SettingsLayout.row("Window tiling", detail: "Move windows with Control + Option.", control: windowTiling),
            SettingsLayout.row("Clipboard history", detail: "Keep recent copies until you quit Ku-Ka.", control: clipboardHistory)
        ]))
        loginError.textColor = .systemRed
        loginError.isHidden = true
        add(SettingsLayout.heading("Screenshots", symbol: "camera.fill", color: .systemPurple))
        add(SettingsLayout.group([SettingsLayout.row("Show thumbnail for", control: thumbnailDuration)]))
        add(SettingsLayout.heading("Meeting notes", symbol: "waveform", color: .systemOrange))
        add(SettingsLayout.group([
            pathRow("Meetings folder", path: folderPath, buttons: [chooseMeetingsFolder]),
            SettingsLayout.row("Summary tool", control: summaryTool)
        ]))
        add(SettingsLayout.label("Automatic tries Antigravity, then Claude Code. An explicit choice uses only that tool. Changes apply when the next job starts.", size: 11, secondary: true))
        add(SettingsLayout.group([pathRow("Background file", path: backgroundPath, buttons: [chooseBackground, clearBackground])]))
        add(SettingsLayout.label("The complete background file goes with the transcript. Automatic may send it to both providers on fallback. Clear keeps the file.", size: 11, secondary: true))
        add(SettingsLayout.group([
            column([SettingsLayout.row("Calendar reminders", detail: "Calendar events offer recording reminders. Ku-Ka never starts or stops recording automatically.",
                                       control: calendarReminders), calendarStatus]),
            SettingsLayout.row("Teams speaker names", detail: "Experimental. After Stop, names remote speakers from the Teams app. Applies from the next recording.",
                               control: teamsSpeakerNames)
        ]))
        calendarStatus.isHidden = true
        add(SettingsLayout.label("Changes save automatically", size: 11, secondary: true))
        for label in [folderPath, backgroundPath] {
            label.lineBreakMode = .byTruncatingMiddle
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        let root = SettingsBackground()
        window?.contentView = root
        let sidebar = SettingsGlass(radius: 16)
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)
        let brand = SettingsLayout.heading("Ku-Ka", symbol: "viewfinder", color: .systemBlue)
        let navigation = SettingsLayout.stack(spacing: 8)
        SettingsLayout.add(brand, to: navigation)
        navigation.setCustomSpacing(24, after: brand)
        for button in pageButtons {
            button.target = self
            button.action = #selector(pageClicked(_:))
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            SettingsLayout.add(button, to: navigation)
        }
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
        pages = [.settings: SettingsLayout.scroll(content), .instructions: SettingsLayout.scroll(instructions),
                 .permissions: SettingsLayout.scroll(permissionsPage), .help: SettingsLayout.scroll(helpPage)]
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
        selectPage(.settings)
        applyDisplayOptions(.current)
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
        let controls: [NSView]
        switch page {
        case .settings:
            controls = [launchAtLogin, windowTiling, clipboardHistory, thumbnailDuration,
                        chooseMeetingsFolder, summaryTool, chooseBackground, clearBackground, calendarReminders,
                        teamsSpeakerNames]
        case .instructions:
            controls = instructions.guideButtons
        case .permissions:
            controls = permissionsPage.controls
        case .help:
            controls = helpPage.controls
        }
        let keyViews: [NSView] = pageButtons + controls
        for (control, next) in zip(keyViews, keyViews.dropFirst() + [pageButtons[0]]) { control.nextKeyView = next }
        window?.makeFirstResponder(pageButtons[page.rawValue])
        refreshPermissionsVisibility()
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

    @objc private func tilingChanged() {
        settings.windowTilingEnabled = windowTiling.state == .on
        onTilingChanged?(settings.windowTilingEnabled)
    }

    @objc private func clipboardChanged() {
        settings.clipboardHistoryEnabled = clipboardHistory.state == .on
        onClipboardChanged?(settings.clipboardHistoryEnabled)
    }

    @objc private func calendarChanged() {
        onCalendarRemindersChanged?(calendarReminders.state == .on)
    }

    func showCalendarStatus(_ status: CalendarReminderController.Status) {
        calendarReminders.state = settings.calendarRecordingRemindersEnabled ? .on : .off
        let text = switch status {
        case .off, .ready: ""
        case .requestingAccess: "Asking for Calendar access…"
        case .calendarAccessRequired: "Allow Calendar access for Ku-Ka in System Settings > Privacy & Security > Calendars."
        case .notificationsRequired: "Allow notifications for Ku-Ka in System Settings > Notifications."
        case .readFailed: "Ku-Ka could not read your calendars. It tries again every minute."
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
