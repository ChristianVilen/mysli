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
    private let summaryToolMissing = SettingsNote()
    private let dictationToolMissing = SettingsNote()
    private let folderPath = NSTextField(labelWithString: "")
    private let backgroundPath = NSTextField(labelWithString: "")
    private let settings: Settings
    let sidebar = SettingsSidebarController()
    private let onboarding: Onboarding?
    private let content = NSViewController()
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
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 640, height: 420)
        super.init(window: window)
        window.delegate = self
        content.view = NSView(frame: window.contentLayoutRect)
        window.contentViewController = content
        buildForm()
        if let onboarding, !onboarding.isFinished {
            let view = OnboardingView(model: onboarding, actions: permissionActions)
            view.onChange = { [weak self] in self?.onboardingChanged() }
            onboardingView = view
        } else {
            installCurrentContent()
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
        installCurrentContent()
        if let onboarding, !onboarding.isFinished {
            onboardingView?.render()
        } else {
            sidebar.clearSearch()
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
            installCurrentContent()
            refresh()
            selectPage(.general)
            applyDisplayOptions(.current)
        }
        refreshPermissionsVisibility()
    }

    private func installCurrentContent() {
        if let onboardingView, !onboardingView.model.isFinished {
            if onboardingView.superview == nil { SettingsLayout.fill(onboardingView, in: content.view) }
            return
        }
        guard settingsContent.parent == nil else { return }
        onboardingView?.removeFromSuperview()
        content.addChild(settingsContent)
        SettingsLayout.fill(settingsContent.view, in: content.view)
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
        let previous = permissionsPage.controls
        permissionsPage.showRequired(settings.requiredPermissions, screenshotShortcuts: settings.screenshotShortcutsEnabled)
        if sidebar.isSearching, !previous.elementsEqual(permissionsPage.controls, by: { $0 === $1 }) {
            sidebar.refreshSearchResults()
        }
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
        let summaryNote = MissingToolNote.summary(for: settings.summaryTool)
        summaryToolMissing.stringValue = summaryNote ?? ""
        summaryToolMissing.isHidden = summaryNote == nil
        let dictationNote = MissingToolNote.dictation()
        dictationToolMissing.stringValue = dictationNote ?? ""
        dictationToolMissing.isHidden = dictationNote == nil
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
        var destinations: [SettingsSearchDestination] = []
        func row(_ page: SettingsPage, _ title: String, detail: String? = nil, value: NSTextField? = nil,
                 control: NSView, focus: NSView? = nil, keywords: [String] = []) -> NSView {
            let view = value.map { SettingsLayout.row(title, value: $0, control: control) }
                ?? SettingsLayout.row(title, detail: detail, control: control)
            destinations.append(.init(item: .init(page: page, title: title, detail: detail ?? "", keywords: keywords),
                                      view: view, control: focus ?? control))
            return view
        }
        func pathRow(_ page: SettingsPage, _ title: String, path: NSTextField, buttons: [NSButton], keywords: [String]) -> NSView {
            row(page, title, value: path, control: NSStackView(views: buttons), focus: buttons.first, keywords: keywords)
        }
        let note = SettingsLayout.note
        loginError.textColor = .systemRed
        loginError.isHidden = true
        calendarStatus.isHidden = true
        for page in SettingsPage.allCases where !page.guides.isEmpty {
            guides[page] = SettingsGuides(page.guides)
        }
        func toolPage(_ page: SettingsPage, _ views: [NSView]) -> NSView {
            let content = SettingsLayout.page(title: page.title, subtitle: page.subtitle)
            for view in views { SettingsLayout.add(view, to: content) }
            if !page.shortcuts.isEmpty {
                SettingsLayout.add(SettingsLayout.sectionTitle("Shortcuts"), to: content)
                let shortcuts = page.shortcuts.map { title, keys in
                    let view = SettingsShortcuts.row(title, shortcuts: keys)
                    let names = keys.flatMap { $0.modifierKeycaps + [$0.keycap] }.map(\.name)
                    destinations.append(.init(item: .init(page: page, title: title, keywords: names), view: view))
                    return view
                }
                SettingsLayout.add(SettingsLayout.group(shortcuts), to: content)
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
        let dictationKeyboardHelp = "For Fn, set ‘Press 🌐 key to’ to ‘Do Nothing’ in Keyboard Settings. Mysli never changes this setting."
        destinations.append(.init(item: .init(page: .dictation, title: dictationKeyboard.title,
                                              detail: dictationKeyboardHelp),
                                  view: dictationKeyboard, control: dictationKeyboard))
        let contents: [SettingsPage: NSView] = [
            .general: toolPage(.general, [
                SettingsLayout.group([column([row(.general, "Launch at login", control: launchAtLogin,
                                                                keywords: ["startup start automatically boot"]), loginError])])
            ]),
            .screenshots: toolPage(.screenshots, [SettingsLayout.group([
                row(.screenshots, "Use Mysli for screenshots", detail: "When off, Shift + Command + 3 and 4 go back to macOS.",
                                   control: screenshotShortcuts, keywords: ["screen capture hotkey"]),
                row(.screenshots, "Show thumbnail for", control: thumbnailDuration, keywords: ["preview duration timeout seconds forever"])
            ])]),
            .clipboard: toolPage(.clipboard, [SettingsLayout.group([
                row(.clipboard, "Clipboard history", detail: "Keep recent copies until you quit Mysli.", control: clipboardHistory,
                                   keywords: ["copy paste"])
            ])]),
            .windows: toolPage(.windows, [SettingsLayout.group([
                row(.windows, "Window tiling", detail: "Move windows with Control + Option.", control: windowTiling,
                                   keywords: ["arrange resize snap maximize center"])
            ])]),
            .keepAwake: toolPage(.keepAwake, [
                SettingsLayout.group([
                    row(.keepAwake, "Keep Awake", control: keepAwakeEnabled, keywords: ["sleep prevent caffeine caffeinate"]),
                    row(.keepAwake, "Keep screen on", detail: "The display stays awake too while a session runs.",
                                                         control: keepScreenOn, keywords: ["display sleep"])]),
                note("Start a session from the Mysli menu.")
            ]),
            .meetings: toolPage(.meetings, [
                SettingsLayout.group([
                    row(.meetings, "Meetings", control: meetingsEnabled, keywords: ["recording call audio transcript"]),
                    pathRow(.meetings, "Meetings folder", path: folderPath, buttons: [chooseMeetingsFolder], keywords: ["save location path directory"]),
                    row(.meetings, "Summary tool", control: summaryTool, keywords: ["ai provider claude antigravity automatic agy"])
                ]),
                summaryToolMissing,
                note("Automatic tries Antigravity, then Claude Code. An explicit choice uses only that tool. Changes apply when the next job starts."),
                SettingsLayout.group([pathRow(.meetings, "Background file", path: backgroundPath, buttons: [chooseBackground, clearBackground],
                                             keywords: ["context summary information"])]),
                note("The complete background file goes with the transcript. Automatic may send it to both providers on fallback. Clear keeps the file."),
                SettingsLayout.group([
                    column([row(.meetings, "Calendar reminders", detail: "Calendar events offer recording reminders. Mysli never starts or stops recording automatically.",
                                               control: calendarReminders, keywords: ["schedule notifications alerts"]), calendarStatus]),
                    row(.meetings, "Remind me", control: calendarReminderTime, keywords: ["calendar reminder time minutes before start"]),
                    row(.meetings, "Remind for", detail: "A video meeting link is a Teams, Google Meet, or Zoom link in the event notes, location, or URL.",
                                       control: calendarReminderEvents, keywords: ["calendar reminders filter events teams zoom google meet video link"]),
                    row(.meetings, "Teams speaker names", detail: "Experimental. After Stop, names remote speakers from the Teams app. Applies from the next recording.",
                                       control: teamsSpeakerNames, keywords: ["people participants identify recognition"])
                ])
            ]),
            .dictation: toolPage(.dictation, [
                SettingsLayout.group([
                    row(.dictation, "Dictation", detail: "Send dictated words to Claude Haiku for polish, then paste them.",
                                       control: dictationEnabled, keywords: ["voice speech microphone"]),
                    row(.dictation, "Hold to dictate", control: dictationKey, keywords: ["fn globe key keyboard shortcut hotkey"]),
                    row(.dictation, "Send text near the cursor", detail: "Share up to 500 characters before the cursor with Claude. Secure fields are excluded.",
                                       control: dictationNearbyText, keywords: ["preceding nearby context privacy"])
                ]),
                dictationToolMissing,
                note("Fn needs Input Monitoring. Both options need Microphone and Accessibility. Grant them on the Permissions page."),
                note(dictationKeyboardHelp),
                SettingsLayout.trailing(dictationKeyboard)
            ]),
            .permissions: permissions,
            .help: helpPage
        ]
        for page in SettingsPage.allCases {
            guard let content = contents[page] else { continue }
            if !destinations.contains(where: { $0.item.page == page && $0.item.title == page.title }) {
                destinations.append(.init(item: .init(page: page, title: page.title, detail: page.subtitle, kind: .page), view: content))
            }
            for guide in guides[page]?.guides ?? [] {
                destinations.append(.init(item: .init(page: page, title: guide.button.title, detail: guide.body.stringValue, kind: .guide),
                                                view: guide.button, control: guide.button, reveal: {
                    if guide.body.isHidden { guide.button.performClick(nil) }
                }))
            }
        }
        sidebar.catalog = destinations + permissionsPage.searchDestinations + helpPage.searchDestinations
        sidebar.onSearchChanged = { [weak self] in self?.updateKeyViewLoop() }
        let root = pageContainer
        pages = contents.mapValues { SettingsLayout.scroll($0, maxWidth: SettingsLayout.pageMaxWidth) }
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
        sidebar.onSelect = { [weak self] row in
            guard let self else { return }
            switch row {
            case .page(let page):
                if selectedPage != page { selectPage(page) }
            case .result(let destination):
                revealSearchResult(destination)
            }
        }
        window?.initialFirstResponder = launchAtLogin
        selectPage(.general)
        applyDisplayOptions(.current)
    }

    private func selectPage(_ page: SettingsPage, focusSidebar: Bool = true) {
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
        if focusSidebar { sidebar.tableView.window?.makeFirstResponder(sidebar.tableView) }
        refreshPermissionsVisibility()
    }

    private func revealSearchResult(_ destination: SettingsSearchDestination) {
        selectPage(destination.item.page, focusSidebar: false)
        destination.reveal?()
        settingsContent.view.layoutSubtreeIfNeeded()
        if !destination.view.isHiddenOrHasHiddenAncestor {
            destination.view.scrollToVisible(destination.view.bounds.insetBy(dx: 0, dy: -16))
        }
        let focus = destination.control
        let window = sidebar.tableView.window
        if let focus, !focus.isHiddenOrHasHiddenAncestor, focus.acceptsFirstResponder {
            window?.makeFirstResponder(focus)
        } else {
            window?.makeFirstResponder(sidebar.tableView)
        }
    }

    @objc func focusSettingsSearch(_ sender: Any?) {
        guard let window = sidebar.searchField.window else { return }
        window.makeFirstResponder(sidebar.searchField)
        sidebar.searchField.selectText(nil)
    }

    override func cancelOperation(_ sender: Any?) {
        guard sidebar.isSearching else { return super.cancelOperation(sender) }
        sidebar.clearSearch()
        focusSettingsSearch(sender)
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
        let navigation: [NSView] = [sidebar.searchField] + (sidebar.tableView.numberOfRows > 0 ? [sidebar.tableView] : [])
        let keyViews = navigation + controls + (guides[selectedPage]?.buttons ?? [])
        for (control, next) in zip(keyViews, keyViews.dropFirst() + [sidebar.searchField]) { control.nextKeyView = next }
    }

    func applyDisplayOptions(_ options: SettingsDisplayOptions) {
        func apply(in view: NSView) {
            (view as? SettingsBackground)?.apply(options)
            (view as? SettingsGlass)?.apply(options)
            for child in view.subviews { apply(in: child) }
        }
        apply(in: settingsContent.view)
        if let onboardingView { apply(in: onboardingView) }
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
        let summaryNote = MissingToolNote.summary(for: tool)
        summaryToolMissing.stringValue = summaryNote ?? ""
        summaryToolMissing.isHidden = summaryNote == nil
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

#if DEBUG
extension SettingsWindowController {
    func makePreview(retaining defaults: PreviewDefaults, page: SettingsPage = .general, query: String? = nil,
                     openFirstResult: Bool = false) -> NSViewController {
        let size = content.view.frame.size
        window?.contentViewController = nil
        let host = AppKitPreview.host(NSView(), size: size, retaining: [self, defaults] as NSArray)
        host.addChild(content)
        SettingsLayout.fill(content.view, in: host.view)
        installCurrentContent()
        if onboarding?.isFinished == false { return host }
        refresh()
        selectPage(page, focusSidebar: false)
        if let query {
            sidebar.searchField.stringValue = query
            sidebar.refreshSearchResults()
            if openFirstResult, let action = sidebar.tableView.action {
                NSApp.sendAction(action, to: sidebar.tableView.target, from: sidebar.tableView)
            }
        }

        return host
    }

    func makeSidebarPreview(retaining defaults: PreviewDefaults) -> NSViewController {
        sidebar.onSelect = nil
        if let item = settingsContent.splitViewItem(for: sidebar) { settingsContent.removeSplitViewItem(item) }
        return AppKitPreview.host(sidebar.view, size: NSSize(width: 230, height: 460), retaining: [self, defaults] as NSArray)
    }
}
#endif
