import Cocoa

@MainActor
final class OnboardingView: NSView {
    let model: Onboarding
    let nextButton = NSButton(title: "", target: nil, action: nil)
    let backButton = NSButton(title: "Back", target: nil, action: nil)
    let skipButton = NSButton(title: "Skip setup", target: nil, action: nil)
    private(set) var toolButtons: [MysliTool: NSButton] = [:]
    let remindersButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let permissionList: PermissionListView
    var onChange: (() -> Void)?

    private let welcome = NSView()
    private let tools = SettingsLayout.stack(spacing: 16)
    private let access = SettingsLayout.stack(spacing: 16)
    private let dots = NSStackView()
    private var dotWidths: [NSLayoutConstraint] = []
    private let progress = NSProgressIndicator()
    private let progressLabel = SettingsLayout.label("", size: 12, secondary: true)
    private let resumed = SettingsLayout.label("Welcome back. Your setup progress was saved. Continue here.", size: 12)
    private let resumedBanner = NSView()
    private var snapshot = PermissionSnapshot(accessibility: false, screenRecording: false, microphone: .notDetermined,
                                               calendar: .notDetermined, notifications: .notDetermined)

    init(model: Onboarding, actions: PermissionActions) {
        self.model = model
        permissionList = PermissionListView(actions: actions, spacing: 12, inset: 14)
        super.init(frame: .zero)
        SettingsLayout.fill(SettingsBackground(), in: self)
        buildWelcome()
        buildTools()
        buildAccess()
        let footer = NSView()
        addSubview(footer)
        footer.translatesAutoresizingMaskIntoConstraints = false
        let rule = NSBox()
        rule.boxType = .separator
        footer.addSubview(rule)
        rule.translatesAutoresizingMaskIntoConstraints = false
        for (button, action) in [(nextButton, #selector(advance)), (backButton, #selector(back)), (skipButton, #selector(skip))] {
            button.target = self
            button.action = action
            button.bezelStyle = .push
            button.controlSize = .large
            button.translatesAutoresizingMaskIntoConstraints = false
            footer.addSubview(button)
        }
        nextButton.bezelColor = .controlAccentColor
        nextButton.tintProminence = .primary
        skipButton.isBordered = false
        skipButton.contentTintColor = .controlAccentColor
        dots.spacing = 5
        dots.alignment = .centerY
        dots.translatesAutoresizingMaskIntoConstraints = false
        dots.setAccessibilityElement(true)
        dots.setAccessibilityRole(.group)
        footer.addSubview(dots)
        for _ in Onboarding.Step.allCases {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3
            dots.addArrangedSubview(dot)
            let width = dot.widthAnchor.constraint(equalToConstant: 5)
            width.isActive = true
            dot.heightAnchor.constraint(equalToConstant: 5).isActive = true
            dotWidths.append(width)
        }
        for view in [welcome, tools, access] {
            let scroll = SettingsLayout.scroll(view)
            scroll.translatesAutoresizingMaskIntoConstraints = false
            addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 48),
                scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -48),
                scroll.topAnchor.constraint(equalTo: topAnchor, constant: 12),
                scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12)
            ])
        }
        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 64),
            rule.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            rule.topAnchor.constraint(equalTo: footer.topAnchor),
            backButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 24),
            backButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            skipButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 24),
            skipButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            nextButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -24),
            nextButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            nextButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 92),
            dots.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
            dots.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])
        render()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var controls: [NSView] {
        switch model.step {
        case .welcome: [skipButton, nextButton]
        case .tools:
            MysliTool.allCases.compactMap { toolButtons[$0] }
                + (remindersButton.isEnabled ? [remindersButton] : []) + [backButton, nextButton]
        case .permissions:
            permissionList.controls.filter(\.isEnabled) + [backButton, nextButton]
        }
    }

    func renderPermissions(_ snapshot: PermissionSnapshot) {
        self.snapshot = snapshot
        renderAccess()
        updateKeyViewLoop()
    }

    func render() {
        let views: [(Onboarding.Step, NSView)] = [(.welcome, welcome), (.tools, tools), (.permissions, access)]
        for (step, view) in views { view.enclosingScrollView?.isHidden = step != model.step }
        nextButton.title = switch model.step {
        case .welcome: "Get Started"
        case .tools: "Continue"
        case .permissions: "Finish"
        }
        backButton.isHidden = model.step == .welcome
        skipButton.isHidden = model.step != .welcome
        for (tool, button) in toolButtons { button.state = model.selectedTools.contains(tool) ? .on : .off }
        remindersButton.state = model.calendarReminders ? .on : .off
        remindersButton.isEnabled = model.selectedTools.contains(.meetings)
        let step = Onboarding.Step.allCases.firstIndex(of: model.step) ?? 0
        dots.setAccessibilityLabel("Step \(step + 1) of 3")
        for (index, dot) in dots.arrangedSubviews.enumerated() {
            dotWidths[index].constant = index == step ? 18 : 5
            dot.layer?.backgroundColor = (index == step ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).cgColor
        }
        renderAccess()
        updateKeyViewLoop()
    }

    private func buildWelcome() {
        let content = SettingsLayout.stack(spacing: 18)
        content.alignment = .centerX
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 96).isActive = true
        content.addArrangedSubview(icon)
        let title = SettingsLayout.label("Welcome to Mysli", size: 28)
        title.font = .systemFont(ofSize: 28, weight: .bold)
        content.addArrangedSubview(title)
        let tagline = SettingsLayout.label("A daily mix of Mac tools.", secondary: true)
        content.addArrangedSubview(tagline)
        content.setCustomSpacing(6, after: title)
        content.setCustomSpacing(28, after: tagline)
        let icons = NSStackView()
        icons.spacing = 12
        icons.distribution = .fillEqually
        icons.widthAnchor.constraint(equalToConstant: 440).isActive = true
        for tool in MysliTool.allCases {
            let square = NSImageView(image: tool.icon(size: 36))
            square.widthAnchor.constraint(equalToConstant: 36).isActive = true
            square.heightAnchor.constraint(equalToConstant: 36).isActive = true
            let column = SettingsLayout.stack([square, SettingsLayout.label(tool.title, size: 11)], spacing: 8)
            column.alignment = .centerX
            icons.addArrangedSubview(column)
        }
        content.addArrangedSubview(icons)
        content.setCustomSpacing(24, after: icons)
        let detail = SettingsLayout.label("Choose the tools you want. Mysli asks only for the permissions those tools need. You can change everything later in Settings.")
        detail.alignment = .center
        content.addArrangedSubview(detail)
        content.translatesAutoresizingMaskIntoConstraints = false
        welcome.addSubview(content)
        NSLayoutConstraint.activate([
            welcome.heightAnchor.constraint(greaterThanOrEqualToConstant: 480),
            content.centerYAnchor.constraint(equalTo: welcome.centerYAnchor),
            content.leadingAnchor.constraint(equalTo: welcome.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: welcome.trailingAnchor, constant: -16),
            detail.widthAnchor.constraint(lessThanOrEqualToConstant: 460)
        ])
    }

    private func buildTools() {
        SettingsLayout.add(SettingsLayout.page(title: "Choose your tools", subtitle: "Mysli turns off the tools you do not choose. You can turn them on later in Settings."), to: tools)
        var rows: [NSView] = []
        for (index, tool) in MysliTool.allCases.enumerated() {
            let detail = switch tool {
            case .screenshots: "Capture with Shift + Command + 3 and 4, then draw, crop, or combine."
            case .clipboard: "Search and paste recent copies with Shift + Command + C."
            case .windows: "Tile windows with Control + Option and the arrow keys."
            case .keepAwake: "Keep the Mac awake for a set time."
            case .meetings: "Record calls into transcripts and summaries on this Mac."
            case .dictation: "Hold a key to dictate. Send the words to Claude, then paste them."
            }
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toolChanged(_:)))
            button.tag = index
            button.setAccessibilityLabel(tool.title)
            toolButtons[tool] = button
            let needed = RequiredPermissions(tools: [tool], calendarReminders: false).permissions.map(\.title)
            rows.append(choiceRow(title: tool.title, detail: detail,
                                  needs: needed.isEmpty ? "nothing" : needed.joined(separator: ", "),
                                  icon: tool.icon(size: 32), button: button))
        }
        remindersButton.target = self
        remindersButton.action = #selector(remindersChanged)
        remindersButton.setAccessibilityLabel("Calendar reminders")
        let reminders = choiceRow(title: "Calendar reminders", detail: "Offers to record when a calendar event starts. Mysli never records by itself.",
                                  needs: "Calendar, Notifications",
                                  icon: MysliTool.neutralIcon(symbolName: "calendar", size: 28, description: "Calendar reminders"),
                                  button: remindersButton, indent: 24)
        rows.append(reminders)
        SettingsLayout.add(SettingsLayout.group(rows), to: tools)
    }

    private func choiceRow(title: String, detail: String, needs: String, icon: NSImage, button: NSButton, indent: CGFloat = 0) -> NSView {
        let heading = SettingsLayout.label(title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        let copy = SettingsLayout.stack(spacing: 2)
        for label in [heading, SettingsLayout.label(detail, size: 12),
                      SettingsLayout.label("Needs: \(needs)", size: 11, secondary: true)] {
            SettingsLayout.add(label, to: copy)
        }
        let image = NSImageView(image: icon)
        image.imageScaling = .scaleProportionallyDown
        image.widthAnchor.constraint(equalToConstant: 32).isActive = true
        image.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let row = NSView()
        for child in [image, copy, button] {
            child.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(child)
        }
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: indent),
            image.topAnchor.constraint(equalTo: copy.topAnchor),
            copy.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 12),
            copy.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
            copy.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -8),
            copy.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -16),
            button.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            button.centerYAnchor.constraint(equalTo: heading.centerYAnchor)
        ])
        copy.setHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        copy.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        copy.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return row
    }

    private func buildAccess() {
        resumed.textColor = .controlAccentColor
        let resumeIcon = NSImageView(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)!)
        resumeIcon.contentTintColor = .controlAccentColor
        resumeIcon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        let bannerRow = NSStackView(views: [resumeIcon, resumed])
        bannerRow.spacing = 8
        resumedBanner.wantsLayer = true
        resumedBanner.layer?.cornerRadius = 8
        SettingsLayout.fill(bannerRow, in: resumedBanner, inset: 10)
        SettingsLayout.add(resumedBanner, to: access)
        SettingsLayout.add(SettingsLayout.page(title: "Allow access", subtitle: "Only for the tools you chose. Each row updates when you allow it in System Settings."), to: access)
        progress.style = .bar
        progress.isIndeterminate = false
        progress.setAccessibilityLabel("Permissions allowed")
        let progressRow = NSStackView(views: [progress, progressLabel])
        progressRow.spacing = 12
        progressLabel.setContentHuggingPriority(.required, for: .horizontal)
        SettingsLayout.add(progressRow, to: access)
        SettingsLayout.add(permissionList, to: access)
        SettingsLayout.add(SettingsLayout.label("You can finish now and allow the rest later. Settings shows what is missing on its Permissions page.", size: 12, secondary: true), to: access)
    }

    private func renderAccess() {
        resumedBanner.isHidden = !model.wasResumed
        resumedBanner.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        let required = model.requiredPermissions.permissions
        permissionList.showRequired(model.requiredPermissions)
        permissionList.render(snapshot)
        let allowed = required.filter { snapshot.status(for: $0) == .granted }.count
        progress.maxValue = Double(max(1, required.count))
        progress.doubleValue = Double(required.isEmpty ? 1 : allowed)
        progressLabel.stringValue = required.isEmpty ? "No access needed" : "\(allowed) of \(required.count) allowed"
    }

    private func updateKeyViewLoop() {
        let views = controls
        for (view, next) in zip(views, views.dropFirst() + views.prefix(1)) { view.nextKeyView = next }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        render()
    }

    @objc private func toolChanged(_ sender: NSButton) {
        model.setTool(MysliTool.allCases[sender.tag], enabled: sender.state == .on)
        render()
    }

    @objc private func remindersChanged() {
        model.setCalendarReminders(remindersButton.state == .on)
        render()
    }

    @objc private func advance() { model.advance(); changedStep() }
    @objc private func back() { model.back(); changedStep() }
    @objc private func skip() { model.skip(); changedStep() }

    private func changedStep() {
        render()
        onChange?()
        window?.makeFirstResponder(controls.first)
    }
}
