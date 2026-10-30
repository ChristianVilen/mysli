import Cocoa

final class KeepAwakePanelView: NSView {
    let titleLabel = NSTextField(labelWithString: "Keep Awake")
    let durationControl: NSSegmentedControl
    private let durations: [WakeDuration]

    /// Fired with the duration of the clicked chip.
    var onSelectDuration: ((WakeDuration) -> Void)?

    init(presets: [(chip: String, duration: WakeDuration)]) {
        durations = presets.map(\.duration)
        durationControl = NSSegmentedControl(labels: presets.map(\.chip), trackingMode: .selectOne, target: nil, action: nil)
        super.init(frame: .zero)

        titleLabel.font = .menuFont(ofSize: 13)
        titleLabel.textColor = .secondaryLabelColor

        durationControl.target = self
        durationControl.action = #selector(durationClicked(_:))
        durationControl.controlSize = .small
        durationControl.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let stack = NSStackView(views: [titleLabel, durationControl])
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
}
