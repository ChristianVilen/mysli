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
        if !isVisible, let screen = screenFrame() {
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
        // AX uses top-left desktop coordinates. A failed read falls back to the main screen.
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else {
            return NSScreen.main?.visibleFrame ?? screens.first?.visibleFrame
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        _ = AXUIElementSetMessagingTimeout(element, 0.1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return NSScreen.main?.visibleFrame ?? screens.first?.visibleFrame
        }
        let window = unsafeBitCast(value, to: AXUIElement.self)
        _ = AXUIElementSetMessagingTimeout(window, 0.1)
        var position: CFTypeRef?
        var size: CFTypeRef?
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID(),
              AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &extent) else {
            return NSScreen.main?.visibleFrame ?? screens.first?.visibleFrame
        }
        let frame = ScreenCoordinates.flipVertical(CGRect(origin: point, size: extent),
            primaryScreenHeight: screens.first?.frame.maxY ?? 0)
        if let index = ScreenCoordinates.bestScreenIndex(for: frame, screenFrames: screens.map(\.frame)) {
            return screens[index].visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? screens.first?.visibleFrame
    }
}
