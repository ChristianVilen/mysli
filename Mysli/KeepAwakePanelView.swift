import Cocoa

final class KeepAwakePanelView: NSView {
    let durationControl: NSSegmentedControl
    private let durations: [WakeDuration]

    /// Fired with the duration of the clicked chip.
    var onSelectDuration: ((WakeDuration) -> Void)?

    init(presets: [(chip: String, duration: WakeDuration)]) {
        durations = presets.map(\.duration)
        durationControl = NSSegmentedControl(labels: presets.map(\.chip), trackingMode: .selectOne, target: nil, action: nil)
        super.init(frame: .zero)

        durationControl.target = self
        durationControl.action = #selector(durationClicked(_:))
        durationControl.controlSize = .small
        durationControl.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        durationControl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(durationControl)
        NSLayoutConstraint.activate([
            durationControl.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            durationControl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            durationControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            durationControl.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
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

#if DEBUG
import SwiftUI

#Preview("Keep Awake · light", traits: .fixedLayout(width: 220, height: 44)) {
    keepAwakePreview(.aqua)
}

#Preview("Keep Awake · dark", traits: .fixedLayout(width: 220, height: 44)) {
    keepAwakePreview(.darkAqua, selected: KeepAwakeController.presets[1].duration)
}

@MainActor
private func keepAwakePreview(_ appearance: NSAppearance.Name, selected: WakeDuration? = nil) -> NSViewController {
    let view = KeepAwakePanelView(presets: KeepAwakeController.presets)
    view.showSelection(selected)
    let background = SettingsBackground()
    background.appearance = NSAppearance(named: appearance)
    background.apply(.init(reduceTransparency: true, increaseContrast: false))
    SettingsLayout.fill(view, in: background)
    return AppKitPreview.host(background, size: NSSize(width: 220, height: 44))
}
#endif
