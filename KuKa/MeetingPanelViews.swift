import Cocoa

extension MeetingControlsPanel {
    enum Layout {
        static let cornerRadius: CGFloat = 18
        static let pillHeight: CGFloat = 42
        static let recordingWidth: CGFloat = 224
        static let startingWidth: CGFloat = 236
        static let pausedWidth: CGFloat = 292
        static let noticeWidth: CGFloat = 300
        /// The pill and the drawer while the drawer is open.
        static let openWidth: CGFloat = 380

        static let pillLeading: CGFloat = 13
        static let pillTrailing: CGFloat = 7
        static let statusSpacing: CGFloat = 7
        static let markSize: CGFloat = 13
        static let buttonSize: CGFloat = 28
        static let buttonSpacing: CGFloat = 6
        static let titledButtonPadding: CGFloat = 20
        static let noteTop: CGFloat = 36
        static let noteLeading: CGFloat = 33
        static let noteTrailing: CGFloat = 14
        static let noteBottom: CGFloat = 12

        static let headerHeight: CGFloat = 30
        static let gripHeight: CGFloat = 12
        static let rowInset: CGFloat = 14
        static let speakerColumn: CGFloat = 40
        static let columnGap: CGFloat = 8
        static let rowTopGap: CGFloat = 8
        static let continuationTopGap: CGFloat = 2
        static let rowBottomGap: CGFloat = 2
        static let speakerHeight: CGFloat = 15
        static let rowTimeHeight: CGFloat = 13
        static let pauseRowHeight: CGFloat = 34
        static let messageInset: CGFloat = 22
        static let returnToLiveBottom: CGFloat = 10
        static var transcriptTextWidth: CGFloat { openWidth - 2 * rowInset - speakerColumn - columnGap }

        static let textSize: CGFloat = 13
        static let fadeDuration: TimeInterval = 0.15
        static let resizeDuration: TimeInterval = 0.2
    }

    enum Colors {
        static let me = dynamic(light: NSColor(srgbRed: 0.04, green: 0.37, blue: 0.77, alpha: 1),
                                dark: NSColor(srgbRed: 0.37, green: 0.66, blue: 1, alpha: 1))
        static let them = dynamic(light: NSColor(srgbRed: 0.18, green: 0.48, blue: 0.39, alpha: 1),
                                  dark: NSColor(srgbRed: 0.39, green: 0.78, blue: 0.65, alpha: 1))
        /// The pill under Reduce Transparency, and the Return to live button.
        static let solid = dynamic(light: NSColor(srgbRed: 0.96, green: 0.96, blue: 0.96, alpha: 1),
                                   dark: NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1))
        /// Near-solid: the transcript is content, not a control, so it does not sit on glass.
        static let drawer = dynamic(light: NSColor(srgbRed: 0.96, green: 0.96, blue: 0.96, alpha: 0.95),
                                    dark: NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 0.95))
        static let button = dynamic(light: NSColor.black.withAlphaComponent(0.06), dark: NSColor.white.withAlphaComponent(0.09))
        static let buttonPressed = dynamic(light: NSColor.black.withAlphaComponent(0.16),
                                           dark: NSColor.white.withAlphaComponent(0.21))

        static func speaker(_ speaker: Speaker) -> NSColor { speaker.track == .microphone ? me : them }

        private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
            NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
        }
    }

    static func symbol(_ name: String, size: CGFloat, color: NSColor) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .bold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color])))
    }
}

/// A filled shape, drawn rather than set on the layer so it follows the appearance.
final class MeetingPanelFill: NSView {
    enum Rounded { case all, top, bottom, none }

    var color: NSColor { didSet { needsDisplay = true } }
    var rounded: Rounded { didSet { needsDisplay = true } }
    private let radius: CGFloat

    init(color: NSColor, radius: CGFloat = 0, rounded: Rounded = .all) {
        self.color = color
        self.radius = radius
        self.rounded = rounded
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        // The square corners lie outside the bounds, which clip them.
        let shape: NSRect
        switch rounded {
        case .all: shape = bounds
        case .top: shape = NSRect(x: bounds.minX, y: bounds.minY - radius, width: bounds.width, height: bounds.height + radius)
        case .bottom: shape = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height + radius)
        case .none: shape = bounds.insetBy(dx: -radius, dy: -radius)
        }
        color.setFill()
        NSBezierPath(roundedRect: shape, xRadius: radius, yRadius: radius).fill()
    }
}

final class MeetingPanelButton: NSButton {
    private let fill: NSColor
    /// For a button that floats over the transcript, whose fill matches the drawer.
    private let floats: Bool

    init(fill: NSColor = MeetingControlsPanel.Colors.button, floats: Bool = false, target: AnyObject, action: Selector) {
        self.fill = fill
        self.floats = floats
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        imageHugsTitle = true
        title = ""
        translatesAutoresizingMaskIntoConstraints = false
        if floats {
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 10
            shadow.shadowOffset = NSSize(width: 0, height: -3)
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
            self.shadow = shadow
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.4 }
    }

    func configure(symbol: NSImage?, copy: MeetingPanelCopy.Button) {
        image = symbol
        imagePosition = copy.title == nil ? .imageOnly : .imageLeading
        attributedTitle = NSAttributedString(string: copy.title ?? "", attributes: [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        setAccessibilityLabel(copy.label)
        toolTip = copy.tooltip
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        let side = MeetingControlsPanel.Layout.buttonSize
        guard !title.isEmpty else { return NSSize(width: side, height: side) }
        return NSSize(width: super.intrinsicContentSize.width + MeetingControlsPanel.Layout.titledButtonPadding, height: side)
    }

    override func draw(_ dirtyRect: NSRect) {
        (isHighlighted ? MeetingControlsPanel.Colors.buttonPressed : fill).setFill()
        capsule.fill()
        if floats {
            NSColor.separatorColor.setStroke()
            let rim = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25),
                                   xRadius: bounds.height / 2, yRadius: bounds.height / 2)
            rim.lineWidth = 0.5
            rim.stroke()
        }
        super.draw(dirtyRect)
    }

    override func drawFocusRingMask() { capsule.fill() }
    override var focusRingMaskBounds: NSRect { bounds }

    private var capsule: NSBezierPath {
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
    }
}

/// Each state has its own shape, so the status does not rely on colour alone.
final class MeetingStatusMark: NSView {
    var status: MeetingControls.Status = .recording { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: MeetingControlsPanel.Layout.markSize, height: MeetingControlsPanel.Layout.markSize)
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSRect(x: (bounds.width - 13) / 2, y: (bounds.height - 13) / 2, width: 13, height: 13)
        switch status {
        case .starting:
            break
        case .recording:
            // The menu bar icon's mark: a red ring with a white centre.
            let ring = NSBezierPath(ovalIn: box.insetBy(dx: 1.75, dy: 1.75))
            NSColor.white.setFill()
            ring.fill()
            NSColor.systemRed.setStroke()
            ring.lineWidth = 3.5
            ring.stroke()
        case .paused:
            NSColor.secondaryLabelColor.setFill()
            for x in [box.minX + 1, box.minX + 8] {
                NSBezierPath(roundedRect: NSRect(x: x, y: box.minY, width: 4, height: 13), xRadius: 1.5, yRadius: 1.5).fill()
            }
        case .saved:
            MeetingControlsPanel.symbol("checkmark", size: 12, color: .systemGreen)?.draw(in: box)
        case .interrupted:
            MeetingControlsPanel.symbol("exclamationmark.triangle.fill", size: 12, color: .systemOrange)?.draw(in: box)
        }
    }
}

/// The transcript's top edge: rows fade out under the header instead of ending in a cut.
final class MeetingTranscriptFade: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let color = MeetingControlsPanel.Colors.drawer
        NSGradient(starting: color, ending: color.withAlphaComponent(0))?.draw(in: bounds, angle: -90)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Moves something by dragging and reports the offset from where the drag began, in screen
/// points. Ku-Ka is never the active app, so the first click must count.
class MeetingPanelDragView: NSView {
    var onBegan: (() -> Void)?
    var onMoved: ((CGSize) -> Void)?
    var onEnded: (() -> Void)?
    /// The pointer in screen coordinates. Not the event's window location: the window moves
    /// during the drag, so converting that through its current frame makes the drag jitter.
    var mouseLocation: () -> CGPoint = { NSEvent.mouseLocation }
    private var start: CGPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        start = mouseLocation()
        onBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = mouseLocation()
        onMoved?(CGSize(width: point.x - start.x, height: point.y - start.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        start = nil
        onEnded?()
    }
}

/// The pill's content. A press anywhere but on a button drags the panel, labels included.
final class MeetingPillView: MeetingPanelDragView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var view: NSView? = hit
        while let current = view, current !== self {
            if current is NSButton { return hit }
            view = current.superview
        }
        return self
    }
}

final class MeetingDrawerGrip: MeetingPanelDragView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        let handle = NSRect(x: bounds.midX - 17, y: bounds.midY - 2, width: 34, height: 4)
        NSBezierPath(roundedRect: handle, xRadius: 2, yRadius: 2).fill()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }
}

final class TranscriptSpeechCell: NSTableCellView {
    private typealias Layout = MeetingControlsPanel.Layout

    private let speakerLabel = NSTextField.makeLabel(size: 11.5, weight: .semibold)
    private let timeLabel = NSTextField.makeLabel(size: 10.5, weight: .medium, color: .tertiaryLabelColor, digits: true)
    private let speechLabel = NSTextField.makeWrappingLabel(size: Layout.textSize)
    private var topGap = Layout.rowTopGap

    init() {
        super.init(frame: .zero)
        for label in [speakerLabel, timeLabel, speechLabel] { addSubview(label) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    func configure(speaker: Speaker, at time: TimeInterval, text: String, isFinal: Bool, isContinuation: Bool) {
        speakerLabel.stringValue = speaker.label
        speakerLabel.textColor = MeetingControlsPanel.Colors.speaker(speaker)
        timeLabel.stringValue = RecordedTime.format(time)
        speakerLabel.isHidden = isContinuation
        timeLabel.isHidden = isContinuation
        speechLabel.stringValue = MeetingPanelCopy.speech(text, isFinal: isFinal)
        speechLabel.textColor = isFinal ? .labelColor : .secondaryLabelColor
        topGap = isContinuation ? Layout.continuationTopGap : Layout.rowTopGap
        needsLayout = true
    }

    override func layout() {
        super.layout()
        speakerLabel.frame = NSRect(x: Layout.rowInset, y: topGap, width: Layout.speakerColumn, height: Layout.speakerHeight)
        timeLabel.frame = NSRect(x: Layout.rowInset, y: topGap + Layout.speakerHeight,
                                 width: Layout.speakerColumn, height: Layout.rowTimeHeight)
        speechLabel.frame = NSRect(x: Layout.rowInset + Layout.speakerColumn + Layout.columnGap, y: topGap,
                                   width: Layout.transcriptTextWidth, height: bounds.height - topGap - Layout.rowBottomGap)
    }

    static func height(text: String, isFinal: Bool, isContinuation: Bool) -> CGFloat {
        measuring.stringValue = MeetingPanelCopy.speech(text, isFinal: isFinal)
        let textHeight = measuring.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: Layout.transcriptTextWidth,
                                                                    height: .greatestFiniteMagnitude)).height
        let labels = isContinuation ? 0 : Layout.speakerHeight + Layout.rowTimeHeight
        let top = isContinuation ? Layout.continuationTopGap : Layout.rowTopGap
        return top + ceil(max(textHeight, labels)) + Layout.rowBottomGap
    }

    private static let measuring = NSTextField.makeWrappingLabel(size: Layout.textSize)
}

final class TranscriptPauseCell: NSTableCellView {
    private let label = NSTextField.makeLabel(size: 11, weight: .semibold, color: .secondaryLabelColor, digits: true)

    init() {
        super.init(frame: .zero)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(at time: TimeInterval, duration: TimeInterval?) {
        label.stringValue = MeetingPanelCopy.pauseRow(at: time, duration: duration)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        label.sizeToFit()
        label.frame.origin = NSPoint(x: ((bounds.width - label.frame.width) / 2).rounded(),
                                     y: ((bounds.height - label.frame.height) / 2).rounded())
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset = MeetingControlsPanel.Layout.rowInset
        let y = label.frame.midY.rounded() + 0.25
        NSColor.separatorColor.setFill()
        NSRect(x: inset, y: y, width: max(0, label.frame.minX - 8 - inset), height: 0.5).fill()
        NSRect(x: label.frame.maxX + 8, y: y, width: max(0, bounds.width - inset - label.frame.maxX - 8), height: 0.5).fill()
    }
}
