import Cocoa
import ApplicationServices

@MainActor
final class DictationPanel: FloatingPanel {
    let meter = NSLevelIndicator()
    private let mark = NSImageView()
    private let progress = NSProgressIndicator()
    private let pill = NSView()
    private lazy var markLeading = mark.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 16)
    private let screenFrame: @MainActor () -> NSRect?
    private let reduceTransparency: () -> Bool
    private let reduceMotion: () -> Bool
    private var solid: Bool?
    private var presentation = DictationPresentation.disabled
    private var displayObserver: NSObjectProtocol?
    private(set) var stateSymbol = ""

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(screenFrame: @escaping @MainActor () -> NSRect? = DictationPanel.focusedScreenFrame,
         reduceTransparency: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency },
         reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.screenFrame = screenFrame
        self.reduceTransparency = reduceTransparency
        self.reduceMotion = reduceMotion
        super.init(contentRect: NSRect(x: 0, y: 0, width: 154, height: MeetingControlsPanel.Layout.pillHeight))
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        RecordingAudioMeterView.configure(meter, accessibilityLabel: "Dictation microphone level")
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = true
        for view in [mark, meter, progress] {
            view.translatesAutoresizingMaskIntoConstraints = false
            pill.addSubview(view)
        }
        NSLayoutConstraint.activate([
            markLeading,
            mark.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: 18), mark.heightAnchor.constraint(equalToConstant: 18),
            meter.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 10),
            meter.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -16),
            meter.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            progress.centerXAnchor.constraint(equalTo: pill.centerXAnchor, constant: 12),
            progress.centerYAnchor.constraint(equalTo: pill.centerYAnchor)
        ])
        displayObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { if let self { self.show(self.presentation) } }
        }
    }

    isolated deinit {
        if let displayObserver { NSWorkspace.shared.notificationCenter.removeObserver(displayObserver) }
    }

    func show(_ state: DictationPresentation) {
        let startsListening: Bool
        if case .listening = state {
            if case .listening = presentation { startsListening = false }
            else { startsListening = true }
        } else { startsListening = false }
        presentation = state
        let label: String
        var spinning = false
        meter.isHidden = true
        switch state {
        case .disabled, .idle:
            progress.stopAnimation(nil)
            orderOut(nil)
            return
        case .loading: stateSymbol = "arrow.down.circle"; label = "Preparing dictation"; spinning = true
        case .listening(let level, let warning):
            stateSymbol = warning ? "exclamationmark.triangle" : "mic.fill"
            label = warning ? "Dictation listening, ten seconds remaining" : "Dictation listening"
            meter.doubleValue = Double(level)
            meter.isHidden = false
        case .transcribing: stateSymbol = "waveform"; label = "Transcribing dictation"; spinning = true
        case .polishing: stateSymbol = "sparkles"; label = "Polishing dictation"; spinning = true
        case .unpolished: stateSymbol = "exclamationmark.triangle"; label = "Dictation pasted without polish"
        case .error: stateSymbol = "xmark.octagon"; label = "Dictation unavailable"
        }
        mark.image = NSImage(systemSymbolName: stateSymbol, accessibilityDescription: label)
        let width: CGFloat = !meter.isHidden ? 154 : spinning ? 96 : 64
        let center = frame.midX
        setFrame(NSRect(x: center - width / 2, y: frame.minY, width: width, height: frame.height), display: false)
        markLeading.constant = spinning || !meter.isHidden ? 16 : 23
        mark.contentTintColor = state == .error ? .systemRed : .labelColor
        progress.isHidden = !spinning
        if spinning && !reduceMotion() { progress.startAnimation(nil) }
        else { progress.stopAnimation(nil) }
        pill.setAccessibilityLabel(label)
        applyMaterial()
        if (!isVisible || startsListening), let screen = screenFrame() {
            setFrameOrigin(NSPoint(x: screen.midX - frame.width / 2, y: screen.minY + 24))
        }
        orderFrontRegardless()
    }

    private func applyMaterial() {
        let reduced = reduceTransparency()
        guard solid != reduced else { return }
        solid = reduced
        pill.removeFromSuperview()
        let background: NSView
        if reduced {
            background = MeetingPanelFill(color: MeetingControlsPanel.Colors.solid,
                                          radius: MeetingControlsPanel.Layout.cornerRadius)
            SettingsLayout.fill(pill, in: background)
        } else {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = MeetingControlsPanel.Layout.cornerRadius
            glass.contentView = pill
            background = glass
        }
        background.frame = NSRect(origin: .zero, size: frame.size)
        contentView = background
    }

    static func focusedScreenFrame() -> NSRect? {
        let screens = NSScreen.screens
        // The pill appears at press time, so it waits less for a slow app than tiling does.
        guard AXIsProcessTrusted(),
              let window = AccessibilityWindowControl(messagingTimeout: 0.1).focusedWindow(),
              let index = ScreenCoordinates.bestScreenIndex(for: window.frame, screenFrames: screens.map(\.frame)) else {
            return NSScreen.main?.visibleFrame ?? screens.first?.visibleFrame
        }
        return screens[index].visibleFrame
    }
}
