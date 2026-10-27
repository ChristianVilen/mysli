import Cocoa

@MainActor
final class RecordingAudioMeterView: NSView {
    private let microphoneIndicator = NSLevelIndicator()
    private let systemIndicator = NSLevelIndicator()

    init() {
        super.init(frame: .zero)
        let stack = NSStackView(views: [row("Microphone", indicator: microphoneIndicator, accessibilityLabel: "Microphone audio level"),
                                        row("Mac audio", indicator: systemIndicator, accessibilityLabel: "Mac audio level")])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        ])
        frame.size = fittingSize
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ levels: RecordingAudioLevels) {
        microphoneIndicator.doubleValue = levels.microphone
        systemIndicator.doubleValue = levels.system
    }

    private func row(_ title: String, indicator: NSLevelIndicator, accessibilityLabel: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.widthAnchor.constraint(equalToConstant: 80).isActive = true
        indicator.levelIndicatorStyle = .continuousCapacity
        indicator.minValue = 0
        indicator.maxValue = 1
        indicator.warningValue = 2
        indicator.criticalValue = 2
        indicator.isEditable = false
        indicator.controlSize = .small
        indicator.setAccessibilityLabel(accessibilityLabel)
        indicator.widthAnchor.constraint(equalToConstant: 132).isActive = true
        let row = NSStackView(views: [label, indicator])
        row.spacing = 10
        row.alignment = .centerY
        return row
    }
}
