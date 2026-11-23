import Cocoa

@MainActor
final class OnboardingView: NSView {
    private static let choiceIconSize: CGFloat = 32
    private static let optionIconSize: CGFloat = 20
    private static let choiceSpacing: CGFloat = 12

    private struct Entrance {
        let view: NSView
        let delay: CFTimeInterval
        let duration: CFTimeInterval
        var rise: CGFloat = 0
        var scale: CGFloat = 1
    }

    let model: Onboarding
    let nextButton = NSButton(title: "", target: nil, action: nil)
    let backButton = NSButton(title: "Back", target: nil, action: nil)
    let skipButton = NSButton(title: "Skip setup", target: nil, action: nil)
    private(set) var toolButtons: [MysliTool: NSButton] = [:]
    let remindersButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let permissionList: PermissionListView
    var onChange: (() -> Void)?

    private let reduceMotion: () -> Bool
    private let welcome = NSView()
    private let tools = SettingsLayout.stack(spacing: 16)
    private let access = SettingsLayout.stack(spacing: 16)
    private lazy var remindersRow = choiceRow(
        title: "Calendar reminders", detail: "Offers to record when a calendar event starts. Mysli never records by itself.",
        needs: "Calendar, Notifications",
        icon: MysliTool.neutralIcon(symbolName: "calendar", size: Self.optionIconSize, description: "Calendar reminders"),
        iconSize: Self.optionIconSize, button: remindersButton)
    private var entrance: [Entrance] = []
    private var hasAppeared = false
    private var outgoing: CALayer?
    private let dots = NSStackView()
    private var dotWidths: [NSLayoutConstraint] = []
    private let progress = SmoothProgressIndicator()
    private let progressLabel = SettingsLayout.label("", size: 12, secondary: true)
    private let summaryToolMissing = SettingsLayout.label("", size: 11, secondary: true)
    private let dictationToolMissing = SettingsLayout.label("", size: 11, secondary: true)
    private let resumed = SettingsLayout.label("Welcome back. Your setup progress was saved. Continue here.", size: 12)
    private let resumedBanner = NSView()
    private var snapshot = PermissionSnapshot(accessibility: false, screenRecording: false, microphone: .notDetermined,
                                               calendar: .notDetermined, notifications: .notDetermined)

    init(model: Onboarding, actions: PermissionActions,
         reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.model = model
        self.reduceMotion = reduceMotion
        permissionList = PermissionListView(actions: actions, spacing: 12, inset: 14, reduceMotion: reduceMotion)
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
            scroll.autohidesScrollers = true
            scroll.wantsLayer = true
            if view === welcome, let document = scroll.documentView {
                document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor).isActive = true
            }
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
            MysliTool.allCases.flatMap { tool in
                [toolButtons[tool], tool == .meetings && remindersButton.isEnabled ? remindersButton : nil].compactMap { $0 }
            } + [backButton, nextButton]
        case .permissions:
            permissionList.controls.filter(\.isEnabled) + [backButton, nextButton]
        }
    }

    /// Only a window on screen animates. Test windows stay off screen, so a test that reads the progress bar
    /// straight after a change never sees it in motion.
    private var animates: Bool { window?.isVisible == true }

    func renderPermissions(_ snapshot: PermissionSnapshot) {
        self.snapshot = snapshot
        renderAccess(animated: animates && !access.isHiddenOrHasHiddenAncestor && !reduceMotion())
        updateKeyViewLoop()
    }

    func render() {
        for step in Onboarding.Step.allCases { page(for: step)?.isHidden = step != model.step }
        nextButton.title = switch model.step {
        case .welcome: "Get Started"
        case .tools: "Continue"
        case .permissions: "Finish"
        }
        backButton.isHidden = model.step == .welcome
        skipButton.isHidden = model.step != .welcome
        for (tool, button) in toolButtons { button.state = model.selectedTools.contains(tool) ? .on : .off }
        remindersButton.state = model.calendarReminders ? .on : .off
        remindersRow.isEnabled = model.selectedTools.contains(.meetings)
        let summaryNote = MissingToolNote.summary(for: model.summaryTool)
        summaryToolMissing.stringValue = summaryNote ?? ""
        summaryToolMissing.isHidden = summaryNote == nil
        let dictationNote = MissingToolNote.dictation()
        dictationToolMissing.stringValue = dictationNote ?? ""
        dictationToolMissing.isHidden = dictationNote == nil
        let step = Self.index(of: model.step)
        dots.setAccessibilityLabel("Step \(step + 1) of 3")
        for (index, dot) in dots.arrangedSubviews.enumerated() {
            dotWidths[index].constant = index == step ? 18 : 5
            dot.layer?.backgroundColor = Self.dotColor(active: index == step)
        }
        renderAccess()
        updateKeyViewLoop()
    }

    private static func index(of step: Onboarding.Step) -> Int { Onboarding.Step.allCases.firstIndex(of: step) ?? 0 }

    private static func dotColor(active: Bool) -> CGColor {
        (active ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).cgColor
    }

    private func page(for step: Onboarding.Step) -> NSScrollView? {
        switch step {
        case .welcome: welcome.enclosingScrollView
        case .tools: tools.enclosingScrollView
        case .permissions: access.enclosingScrollView
        }
    }

    private func buildWelcome() {
        let content = SettingsLayout.stack(spacing: 16)
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
        content.setCustomSpacing(20, after: tagline)
        let icons = NSStackView()
        icons.alignment = .top
        icons.spacing = 12
        icons.distribution = .fillEqually
        for tool in MysliTool.allCases {
            let square = NSImageView(image: tool.icon(size: 36))
            square.widthAnchor.constraint(equalToConstant: 36).isActive = true
            square.heightAnchor.constraint(equalToConstant: 36).isActive = true
            let label = NSTextField(labelWithString: tool.title)
            label.font = .systemFont(ofSize: 11)
            let column = SettingsLayout.stack([square, label], spacing: 8)
            column.alignment = .centerX
            icons.addArrangedSubview(column)
        }
        content.addArrangedSubview(icons)
        content.setCustomSpacing(16, after: icons)
        let detail = SettingsLayout.label("Choose the tools you want. Mysli asks only for the permissions those tools need. You can change everything later in Settings.")
        detail.alignment = .center
        content.addArrangedSubview(detail)
        let toolDelays: [CFTimeInterval] = [0.14, 0.185, 0.225, 0.26, 0.29, 0.315]
        entrance = [Entrance(view: icon, delay: 0, duration: 0.5, scale: 0.94),
                    Entrance(view: title, delay: 0.06, duration: 0.45, rise: 10),
                    Entrance(view: tagline, delay: 0.06, duration: 0.45, rise: 10)]
            + zip(icons.arrangedSubviews, toolDelays).map { Entrance(view: $0, delay: $1, duration: 0.4, rise: 8) }
            + [Entrance(view: detail, delay: 0.26, duration: 0.4)]
        for part in entrance { part.view.wantsLayer = true }
        content.translatesAutoresizingMaskIntoConstraints = false
        welcome.addSubview(content)
        NSLayoutConstraint.activate([
            content.centerYAnchor.constraint(equalTo: welcome.centerYAnchor),
            content.topAnchor.constraint(greaterThanOrEqualTo: welcome.topAnchor),
            content.bottomAnchor.constraint(lessThanOrEqualTo: welcome.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: welcome.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: welcome.trailingAnchor, constant: -16),
            detail.widthAnchor.constraint(lessThanOrEqualToConstant: 460)
        ])
    }

    private func buildTools() {
        SettingsLayout.add(SettingsLayout.page(title: "Choose your tools", subtitle: "Mysli turns off the tools you do not choose. You can turn them on later in Settings."), to: tools)
        remindersButton.target = self
        remindersButton.action = #selector(remindersChanged)
        remindersButton.setAccessibilityLabel("Calendar reminders")
        remindersRow.edgeInsets.left = Self.choiceIconSize + Self.choiceSpacing
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
            let missing: NSTextField? = switch tool {
            case .meetings: summaryToolMissing
            case .dictation: dictationToolMissing
            default: nil
            }
            let row = choiceRow(title: tool.title, detail: detail,
                                needs: needed.isEmpty ? "nothing" : needed.joined(separator: ", "),
                                icon: tool.icon(size: Self.choiceIconSize), button: button, missing: missing)
            if tool == .meetings {
                let meetings = SettingsLayout.stack(spacing: 4)
                for child in [row, remindersRow] { SettingsLayout.add(child, to: meetings) }
                rows.append(meetings)
            } else {
                rows.append(row)
            }
        }
        SettingsLayout.add(SettingsLayout.group(rows), to: tools)
    }

    private func choiceRow(title: String, detail: String, needs: String, icon: NSImage,
                           iconSize: CGFloat = OnboardingView.choiceIconSize, button: NSButton,
                           missing: NSTextField? = nil) -> ChoiceRow {
        let heading = SettingsLayout.label(title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        let copy = SettingsLayout.stack(spacing: 2)
        for label in [heading, SettingsLayout.label(detail, size: 12, secondary: true),
                      SettingsLayout.label("Needs: \(needs)", size: 11, secondary: true)] + [missing].compactMap({ $0 }) {
            SettingsLayout.add(label, to: copy)
        }
        let image = NSImageView(image: icon)
        image.imageScaling = .scaleProportionallyDown
        image.widthAnchor.constraint(equalToConstant: iconSize).isActive = true
        image.heightAnchor.constraint(equalToConstant: iconSize).isActive = true
        copy.setHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        copy.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        copy.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = ChoiceRow(views: [image, copy], checkbox: button)
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = Self.choiceSpacing
        row.setCustomSpacing(16, after: copy)
        row.edgeInsets = NSEdgeInsets(top: 3, left: 0, bottom: 3, right: 0)
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

    private func renderAccess(animated: Bool = false) {
        resumedBanner.isHidden = !model.wasResumed
        resumedBanner.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        let required = model.requiredPermissions.permissions
        permissionList.showRequired(model.requiredPermissions)
        permissionList.render(snapshot)
        let allowed = required.filter { snapshot.status(for: $0) == .granted }.count
        progress.maxValue = Double(max(1, required.count))
        let value = Double(required.isEmpty ? 1 : allowed)
        if animated, value != progress.doubleValue {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = Motion.easeInOut
                progress.animator().doubleValue = value
            }
        } else {
            progress.doubleValue = value
        }
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !hasAppeared else { return }
        hasAppeared = true
        // Unlike the other motion, this does not wait for the window to be on screen: the window
        // comes on screen in the same turn of the run loop, and the entrance starts with it.
        if model.step == .welcome, !reduceMotion() { playEntrance() }
    }

    private func playEntrance() {
        for part in entrance {
            guard let layer = part.view.layer else { continue }
            layer.animate("opacity", from: 0, duration: part.duration, delay: part.delay)
            if part.rise != 0 {
                let below = part.view.superview?.isFlipped == true ? part.rise : -part.rise
                layer.animate("transform.translation.y", from: below, duration: part.duration, delay: part.delay)
            }
            if part.scale != 1 {
                // The first layout comes later, so the view has no bounds yet.
                layer.animate("transform", from: layer.scaledAboutCenter(part.scale, size: part.view.fittingSize),
                              duration: part.duration, delay: part.delay)
            }
        }
    }

    @objc private func toolChanged(_ sender: NSButton) {
        model.setTool(MysliTool.allCases[sender.tag], enabled: sender.state == .on)
        render()
    }

    @objc private func remindersChanged() {
        model.setCalendarReminders(remindersButton.state == .on)
        render()
    }

    @objc private func advance() { changeStep(model.advance) }
    @objc private func back() { changeStep(model.back) }
    @objc private func skip() { changeStep(model.skip) }

    private func changeStep(_ change: () -> Void) {
        let from = model.step
        outgoing?.removeFromSuperlayer()
        outgoing = animates ? page(for: from)?.coveringPicture() : nil
        change()
        render()
        if model.isFinished || model.step == from {
            outgoing?.removeFromSuperlayer()
        } else if outgoing != nil {
            animateStep(from: from)
        }
        onChange?()
        window?.makeFirstResponder(controls.first)
    }

    private func animateStep(from: Onboarding.Step) {
        let still = reduceMotion()
        let shift: CGFloat = still ? 0 : Self.index(of: model.step) > Self.index(of: from) ? -16 : 16
        outgoing?.fadeAway(duration: still ? 0.15 : 0.16, dx: shift)
        let pages = Onboarding.Step.allCases.compactMap { page(for: $0)?.layer }
        for layer in pages + entrance.compactMap(\.view.layer) { layer.removeMotion() }
        guard let entering = page(for: model.step)?.layer else { return }
        entering.animate("opacity", from: 0, duration: still ? 0.15 : 0.24)
        guard !still else { return }
        entering.animate("transform.translation.x", from: -shift, duration: 0.24)
        animateDots(from: Self.index(of: from))
    }

    /// Call after `render()` and before the next layout, while the dots still have their old frames.
    private func animateDots(from old: Int) {
        let before = dots.arrangedSubviews.map { ($0.layer?.bounds, $0.layer?.position) }
        dots.layoutSubtreeIfNeeded()
        for (index, (dot, (bounds, position))) in zip(dots.arrangedSubviews, before).enumerated() {
            guard let layer = dot.layer, let bounds, let position else { continue }
            layer.animate("bounds", from: NSValue(rect: bounds), duration: 0.24, timing: Motion.easeInOut)
            layer.animate("position", from: NSValue(point: position), duration: 0.24, timing: Motion.easeInOut)
            layer.animate("backgroundColor", from: Self.dotColor(active: index == old), duration: 0.24, timing: Motion.easeInOut)
        }
    }
}

/// A tool row whose whole area toggles its checkbox. The checkbox stays the only control for VoiceOver and the keyboard.
private final class ChoiceRow: NSStackView {
    private let checkbox: NSButton

    init(views: [NSView], checkbox: NSButton) {
        self.checkbox = checkbox
        super.init(frame: .zero)
        for view in views + [checkbox] { addArrangedSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var isEnabled: Bool {
        get { checkbox.isEnabled }
        set {
            checkbox.isEnabled = newValue
            for view in arrangedSubviews where view !== checkbox { view.alphaValue = newValue ? 1 : 0.4 }
        }
    }

    /// The indent of an option row lies below the icon of its parent, so it is not part of the target.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit.isDescendant(of: checkbox) { return hit }
        return convert(point, from: superview).x >= edgeInsets.left ? self : nil
    }

    override func mouseDown(with event: NSEvent) { checkbox.highlight(checkbox.isEnabled) }

    override func mouseUp(with event: NSEvent) {
        checkbox.highlight(false)
        guard checkbox.isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        checkbox.performClick(nil)
    }
}

/// `animator()` moves `doubleValue` only when the class names an animation for it.
private final class SmoothProgressIndicator: NSProgressIndicator {
    override static func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
        key == "doubleValue" ? CABasicAnimation() : super.defaultAnimation(forKey: key)
    }
}
