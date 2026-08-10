import Cocoa

/// The inline Keep Awake panel embedded as a custom view in the status menu:
/// a status line, a row of duration chips, and a "Keep display awake"
/// checkbox. Pure view — it reports interactions through closures and holds
/// no session state; `KeepAwakeController` owns the state and pushes updates
/// into the exposed controls.
final class KeepAwakePanelView: NSView {
    let titleLabel = NSTextField(labelWithString: "Keep Awake")
    let durationControl: NSSegmentedControl
    let displayAwakeCheckbox: NSButton
    private let durations: [WakeDuration]

    /// Fired with the duration of the clicked chip.
    var onSelectDuration: ((WakeDuration) -> Void)?
    /// Fired with the checkbox's new on/off state.
    var onToggleDisplayAwake: ((Bool) -> Void)?

    init(presets: [(chip: String, duration: WakeDuration)]) {
        durations = presets.map(\.duration)
        durationControl = NSSegmentedControl(labels: presets.map(\.chip), trackingMode: .selectOne, target: nil, action: nil)
        displayAwakeCheckbox = NSButton(checkboxWithTitle: "Keep display awake", target: nil, action: nil)
        super.init(frame: .zero)

        titleLabel.font = .menuFont(ofSize: 13)
        titleLabel.textColor = .secondaryLabelColor

        durationControl.target = self
        durationControl.action = #selector(durationClicked(_:))
        durationControl.controlSize = .small
        durationControl.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        displayAwakeCheckbox.target = self
        displayAwakeCheckbox.action = #selector(displayAwakeToggled(_:))
        displayAwakeCheckbox.controlSize = .small
        displayAwakeCheckbox.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let stack = NSStackView(views: [titleLabel, durationControl, displayAwakeCheckbox])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
        ])
        frame.size = fittingSize
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Reflects a session's duration in the chips; nil clears the selection.
    func showSelection(_ duration: WakeDuration?) {
        durationControl.selectedSegment = durations.firstIndex { $0 == duration } ?? -1
    }

    /// Menu custom views don't auto-close the menu, so a chip click closes it
    /// explicitly — matching how a normal menu item click behaves.
    @objc func durationClicked(_ sender: NSSegmentedControl) {
        onSelectDuration?(durations[sender.selectedSegment])
        enclosingMenuItem?.menu?.cancelTracking()
    }

    /// The checkbox is a preference, not a command — the menu stays open.
    @objc func displayAwakeToggled(_ sender: NSButton) {
        onToggleDisplayAwake?(sender.state == .on)
    }
}
