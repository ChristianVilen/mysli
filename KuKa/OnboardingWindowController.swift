import Cocoa

/// One checklist row in the onboarding window: a live ❌/✅/– status, the
/// permission name, a one-sentence explanation of why it's needed, and a
/// Grant button. Pure view — `OnboardingWindowController` pushes status in
/// via `setStatus` and receives clicks via `onGrant`.
final class PermissionRowView: NSView {
    enum Status {
        case granted
        case missing
        /// An optional permission the user was never asked for.
        case notAsked
    }

    private let statusLabel = NSTextField(labelWithString: "❌")
    private let grantButton = NSButton(title: "Grant", target: nil, action: nil)

    /// Fired when the user clicks Grant.
    var onGrant: (() -> Void)?

    init(title: String, explanation: String, note: String? = nil) {
        super.init(frame: .zero)

        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 13)

        let explanationLabel = NSTextField(wrappingLabelWithString: explanation)
        explanationLabel.font = .systemFont(ofSize: 12)
        explanationLabel.textColor = .secondaryLabelColor

        var textViews: [NSView] = [titleLabel, explanationLabel]
        if let note {
            let noteLabel = NSTextField(wrappingLabelWithString: note)
            noteLabel.font = .systemFont(ofSize: 11)
            noteLabel.textColor = .tertiaryLabelColor
            textViews.append(noteLabel)
        }

        let textStack = NSStackView(views: textViews)
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3

        grantButton.target = self
        grantButton.action = #selector(grantClicked)
        grantButton.bezelStyle = .rounded
        grantButton.setContentHuggingPriority(.required, for: .horizontal)
        grantButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [statusLabel, textStack, grantButton])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setStatus(_ status: Status) {
        switch status {
        case .granted:
            statusLabel.stringValue = "✅"
            grantButton.title = "Granted"
        case .missing:
            statusLabel.stringValue = "❌"
            grantButton.title = "Grant"
        case .notAsked:
            statusLabel.stringValue = "–"
            grantButton.title = "Allow"
        }
        grantButton.isEnabled = status != .granted
    }

    @objc private func grantClicked() {
        onGrant?()
    }
}

/// Setup for permissions and screenshot shortcuts. The permission checklist
/// stays available through the menu; shortcut setup is shown automatically once.
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    /// Which page the window shows. `.welcome` is used only for the automatic
    /// open at launch; the "Permissions…" menu item and a blocked capture go
    /// straight to the checklist.
    enum Page {
        case welcome
        case checklist
        case screenshotShortcuts([HotkeyShortcut])
    }

    private static let contentWidth: CGFloat = 480
    private static let contentPadding: CGFloat = 20

    private let permissions: PermissionsManager
    private let settings: Settings
    private let activation: OrdinaryWindowActivation
    private let accessibilityRow: PermissionRowView
    private let screenRecordingRow: PermissionRowView
    private let microphoneRow: PermissionRowView
    private lazy var welcomePage = makeWelcomePage()
    private lazy var checklistPage = makeChecklistPage()
    var onClose: (() -> Void)?

    init(
        permissions: PermissionsManager,
        settings: Settings = Settings(),
        activation: OrdinaryWindowActivation = .shared
    ) {
        self.permissions = permissions
        self.settings = settings
        self.activation = activation

        accessibilityRow = PermissionRowView(
            title: "Accessibility (window tiling and paste)",
            explanation: "Lets Ku-Ka move windows and paste items from clipboard history."
        )
        screenRecordingRow = PermissionRowView(
            title: "Screen Recording (required)",
            explanation: "Lets Ku-Ka take screenshots and record the sound of a call for Meeting Notes.",
            note: "macOS may need you to quit and reopen Ku-Ka once before capture works, and will ask you to re-approve about once a month. That's a macOS rule, not a bug."
        )
        microphoneRow = PermissionRowView(
            title: "Microphone (Meeting Notes, optional)",
            explanation: "Lets Ku-Ka record your side of a meeting when you start a recording.",
            note: "The audio stays on this Mac. For the summary, Ku-Ka sends the transcript text to the AI tool you installed (agy or claude). agy keeps a copy in its history."
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        accessibilityRow.onGrant = { [weak self] in self?.permissions.requestAccessibility() }
        screenRecordingRow.onGrant = { [weak self] in self?.permissions.requestScreenRecording() }
        microphoneRow.onGrant = { [weak self] in
            Task { _ = await self?.permissions.requestMicrophone() }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Pages

    /// Wraps a stack in a fixed-width page view sized by its own content, so
    /// the window can be resized to fit whichever page is installed.
    private func makePage(with stack: NSStackView) -> NSView {
        stack.orientation = .vertical
        stack.edgeInsets = NSEdgeInsets(
            top: Self.contentPadding, left: Self.contentPadding,
            bottom: Self.contentPadding, right: Self.contentPadding
        )
        stack.translatesAutoresizingMaskIntoConstraints = false

        let page = NSView()
        page.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: page.topAnchor),
            stack.bottomAnchor.constraint(equalTo: page.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            page.widthAnchor.constraint(equalToConstant: Self.contentWidth),
        ])
        return page
    }

    private func makeWelcomePage() -> NSView {
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let title = NSTextField(labelWithString: "Welcome to Ku-Ka")
        title.font = .boldSystemFont(ofSize: 20)

        let body = NSTextField(wrappingLabelWithString:
            "Ku-Ka lives in your menu bar. Use ⇧⌘3 / ⇧⌘4 to take screenshots you can annotate, or use its shortcuts to move windows and open clipboard history.\n\nScreen Recording lets Ku-Ka take screenshots and record call audio for Meeting Notes. Accessibility lets it move windows and paste from clipboard history. The next step helps you grant these permissions."
        )
        body.font = .systemFont(ofSize: 13)
        body.alignment = .center

        let continueButton = NSButton(title: "Continue", target: self, action: #selector(continueClicked))
        continueButton.bezelStyle = .rounded
        continueButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [icon, title, body, continueButton])
        stack.alignment = .centerX
        stack.spacing = 12
        let page = makePage(with: stack)
        body.widthAnchor.constraint(
            equalTo: stack.widthAnchor, constant: -2 * Self.contentPadding
        ).isActive = true
        return page
    }

    private func makeChecklistPage() -> NSView {
        let header = NSTextField(wrappingLabelWithString:
            "Screen Recording is needed for screenshots and for Meeting Notes. Accessibility is needed for window tiling and automatic paste. Microphone is needed only for Meeting Notes. Grant the permissions for the features you use. The status updates after you allow each one in System Settings."
        )
        header.font = .systemFont(ofSize: 13)

        let doneButton = NSButton(title: "Done", target: self, action: #selector(doneClicked))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [header, accessibilityRow, screenRecordingRow, microphoneRow, doneButton])
        stack.alignment = .leading
        stack.spacing = 16
        let page = makePage(with: stack)
        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * Self.contentPadding),
            accessibilityRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * Self.contentPadding),
            screenRecordingRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * Self.contentPadding),
            microphoneRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * Self.contentPadding),
            doneButton.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -Self.contentPadding),
        ])
        return page
    }

    private func makeScreenshotSetupPage(shortcuts: [HotkeyShortcut]) -> NSView {
        let header = NSTextField(labelWithString: "Set up screenshot shortcuts")
        header.font = .boldSystemFont(ofSize: 20)
        let body = NSTextField(wrappingLabelWithString:
            "To let Ku-Ka use these keys, turn off their macOS shortcuts in System Settings → Keyboard → Keyboard Shortcuts → Screenshots."
        )
        body.font = .systemFont(ofSize: 13)
        let shortcutRows = shortcuts.map { shortcut in
            let name = shortcut == .captureFullScreen
                ? "Save picture of screen as a file"
                : "Save picture of selected area as a file"
            let row = NSTextField(wrappingLabelWithString: "\(shortcut.label)\n\(name)")
            row.font = .systemFont(ofSize: 13)
            return row
        }
        let note = NSTextField(wrappingLabelWithString:
            "Ku-Ka retries automatically within a few seconds. The warnings in its menu disappear when the shortcuts are ready.\n\nIf you quit Ku-Ka, turn these shortcuts back on in System Settings to use the macOS screenshot tool."
        )
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor

        let openSettings = NSButton(title: "Open Keyboard Settings…", target: self, action: #selector(openKeyboardSettingsClicked))
        openSettings.bezelStyle = .rounded
        openSettings.keyEquivalent = "\r"
        let later = NSButton(title: "Later", target: self, action: #selector(doneClicked))
        later.bezelStyle = .rounded
        let buttons = NSStackView(views: [later, openSettings])
        buttons.spacing = 8

        let stack = NSStackView(views: [header, body] + shortcutRows + [note, buttons])
        stack.alignment = .leading
        stack.spacing = 16
        let page = makePage(with: stack)
        for label in [body, note] + shortcutRows {
            label.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * Self.contentPadding).isActive = true
        }
        buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -Self.contentPadding).isActive = true
        return page
    }

    private func install(_ page: Page) {
        guard let window else { return }
        let view: NSView
        switch page {
        case .welcome:
            view = welcomePage
            window.title = "Welcome to Ku-Ka"
        case .checklist:
            view = checklistPage
            window.title = "Ku-Ka Permissions"
        case .screenshotShortcuts(let shortcuts):
            view = makeScreenshotSetupPage(shortcuts: shortcuts)
            window.title = "Ku-Ka Screenshot Setup"
        }
        guard window.contentView !== view else { return }
        window.contentView = view
        // Size the window from the laid-out page so wrapped labels always fit.
        view.layoutSubtreeIfNeeded()
        window.setContentSize(view.fittingSize)
    }

    // MARK: - Showing

    @discardableResult
    func showScreenshotSetupIfNeeded(issues: [HotkeyRegistrationIssue]) -> Bool {
        let conflicts = issues.filter { $0.shortcut.isScreenshot && $0.failure == .systemConflict }.map(\.shortcut)
        guard window?.isVisible != true,
              !conflicts.isEmpty, !settings.didShowScreenshotShortcutSetup else { return false }
        settings.didShowScreenshotShortcutSetup = true
        show(.screenshotShortcuts(conflicts))
        return true
    }

    func show(_ page: Page = .checklist) {
        install(page)
        if let window { activation.open(window) }
        if window?.isVisible != true {
            window?.center()
        }
        window?.level = .floating
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        refreshRows()
        permissions.startPolling()
    }

    func refreshRows() {
        accessibilityRow.setStatus(permissions.accessibility ? .granted : .missing)
        screenRecordingRow.setStatus(permissions.screenRecording ? .granted : .missing)
        switch permissions.microphone {
        case .granted: microphoneRow.setStatus(.granted)
        case .denied: microphoneRow.setStatus(.missing)
        case .notDetermined: microphoneRow.setStatus(.notAsked)
        }
    }

    @objc private func continueClicked() {
        install(.checklist)
        refreshRows()
    }

    @objc private func doneClicked() {
        close()
    }

    @objc private func openKeyboardSettingsClicked() {
        permissions.openSettings(.keyboardShortcuts)
    }

    func windowWillClose(_ notification: Notification) {
        permissions.stopPolling()
        if let window { activation.close(window) }
        onClose?()
    }
}
