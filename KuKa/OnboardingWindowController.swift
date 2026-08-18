import Cocoa

/// One checklist row in the onboarding window: a live ❌/✅ status, the
/// permission name, a one-sentence explanation of why it's needed, and a
/// Grant button. Pure view — `OnboardingWindowController` pushes status in
/// via `setGranted` and receives clicks via `onGrant`.
final class PermissionRowView: NSView {
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

    func setGranted(_ granted: Bool) {
        statusLabel.stringValue = granted ? "✅" : "❌"
        grantButton.isEnabled = !granted
        grantButton.title = granted ? "Granted" : "Grant"
    }

    @objc private func grantClicked() {
        onGrant?()
    }
}

/// The permission onboarding window: a short welcome page on first open at
/// launch, then one checklist row per needed permission. Reachable anytime
/// via the status menu's "Permissions…" item (which skips the welcome).
///
/// While the window is open the app temporarily becomes a regular app (Dock
/// icon, can take focus) so the window reliably comes to the front, and
/// `PermissionsManager` polls so a grant flips the row to ✅ live — no
/// relaunch. On close the app returns to being a menu-bar-only accessory.
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    /// Which page the window shows. `.welcome` is used only for the automatic
    /// open at launch; the "Permissions…" menu item and a blocked capture go
    /// straight to the checklist.
    enum Page {
        case welcome
        case checklist
    }

    private static let contentWidth: CGFloat = 480
    private static let contentPadding: CGFloat = 20

    private let permissions: PermissionsManager
    private let accessibilityRow: PermissionRowView
    private let screenRecordingRow: PermissionRowView
    private lazy var welcomePage = makeWelcomePage()
    private lazy var checklistPage = makeChecklistPage()

    init(permissions: PermissionsManager) {
        self.permissions = permissions

        accessibilityRow = PermissionRowView(
            title: "Accessibility (required)",
            explanation: "Lets Ku-Ka catch the ⇧⌘3 / ⇧⌘4 screenshot shortcuts and move windows for the tiling hotkeys."
        )
        screenRecordingRow = PermissionRowView(
            title: "Screen Recording (required)",
            explanation: "Lets Ku-Ka read the screen content to take screenshots.",
            note: "macOS may need you to quit and reopen Ku-Ka once before capture works, and will ask you to re-approve about once a month. That's a macOS rule, not a bug."
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
            "Ku-Ka lives in your menu bar: ⇧⌘3 / ⇧⌘4 take screenshots you can annotate, and hotkeys tile your windows.\n\nBefore the hotkeys can work, macOS needs your OK on two permissions. The next step walks you through them."
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
            "Ku-Ka needs two permissions to work. Grant each one below — the status updates here by itself once you allow it in System Settings."
        )
        header.font = .systemFont(ofSize: 13)

        let doneButton = NSButton(title: "Done", target: self, action: #selector(doneClicked))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [header, accessibilityRow, screenRecordingRow, doneButton])
        stack.alignment = .leading
        stack.spacing = 16
        let page = makePage(with: stack)
        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * Self.contentPadding),
            accessibilityRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * Self.contentPadding),
            screenRecordingRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * Self.contentPadding),
            doneButton.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -Self.contentPadding),
        ])
        return page
    }

    private func install(_ page: Page) {
        guard let window else { return }
        let view = page == .welcome ? welcomePage : checklistPage
        guard window.contentView !== view else { return }
        window.title = page == .welcome ? "Welcome to Ku-Ka" : "Ku-Ka Permissions"
        window.contentView = view
        // Size the window from the laid-out page so wrapped labels always fit.
        view.layoutSubtreeIfNeeded()
        window.setContentSize(view.fittingSize)
    }

    // MARK: - Showing

    func show(_ page: Page = .checklist) {
        install(page)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
        accessibilityRow.setGranted(permissions.accessibility)
        screenRecordingRow.setGranted(permissions.screenRecording)
    }

    @objc private func continueClicked() {
        install(.checklist)
        refreshRows()
    }

    @objc private func doneClicked() {
        close()
    }

    func windowWillClose(_ notification: Notification) {
        permissions.stopPolling()
        NSApp.setActivationPolicy(.accessory)
    }
}
