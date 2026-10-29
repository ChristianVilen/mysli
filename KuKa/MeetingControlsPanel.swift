import Carbon.HIToolbox
import Cocoa

/// Reads recording state from `recorder.controls` and owns only presentation.
/// Writes `Settings` only when a user drag or resize ends: tests run in the app with the
/// user's defaults, so launch and automatic moves must not write them.
///
/// It never calls `NSApp.activate` and never makes itself key when it appears, so the meeting
/// app keeps the keyboard. Unlike `ClipboardPanel`, it does not close on `resignKey`.
final class MeetingControlsPanel: FloatingPanel {
    private struct Placement {
        let frame: CGRect
        let pillHeight: CGFloat
        let pillTopRight: CGPoint
        /// Where the drawer is, or would be when it opens.
        let drawerAbove: Bool
    }

    private struct Shape: Equatable {
        let status: MeetingControls.Status
        let isTranscriptOpen: Bool
        let liveStatus: LiveTranscript.Status?
    }

    private let recorder: MeetingRecorder
    private let settings: Settings
    private let screens: Screens
    private let announce: (String, NSAccessibilityPriorityLevel) -> Void
    private let displayOptions: () -> (reduceMotion: Bool, reduceTransparency: Bool)

    /// Used only to announce changes; button actions read the recorder.
    private var announcedStatus: MeetingControls.Status?
    /// Reused during drag, resize, and screen changes to avoid rebuilding transcript rows.
    private var drawnShape: Shape?
    private var placement: Placement?
    private var targetFrame: CGRect?
    private var dragStart: CGPoint?
    private var dragCorner: CGPoint?
    private var resizeStart: (height: CGFloat, drawerAbove: Bool)?
    private var resizeHeight: CGFloat?

    private let root = RootView()
    private var pillBackground: NSView?
    private let pill = MeetingPillView()
    private let spinner = NSProgressIndicator()
    private let mark = MeetingStatusMark()
    private let timeLabel = NSTextField.makeLabel(size: 13, weight: .semibold, digits: true)
    private let wordLabel = NSTextField.makeLabel(size: 13, weight: .semibold)
    private lazy var pauseButton = MeetingPanelButton(target: self, action: #selector(pauseClicked))
    private lazy var stopButton = MeetingPanelButton(target: self, action: #selector(stopClicked))
    private lazy var closeButton = MeetingPanelButton(target: self, action: #selector(closeClicked))
    private lazy var transcriptButton = MeetingPanelButton(target: self, action: #selector(transcriptClicked))
    private let buttonSeparator = MeetingPanelFill(color: .separatorColor, rounded: .none)
    private let noteLabel = NSTextField.makeWrappingLabel(size: 12, color: .secondaryLabelColor)
    private let drawer: MeetingTranscriptDrawer

    init(recorder: MeetingRecorder, settings: Settings, screens: Screens = SystemScreens(),
         announce: @escaping (String, NSAccessibilityPriorityLevel) -> Void = MeetingControlsPanel.postAnnouncement,
         displayOptions: @escaping () -> (reduceMotion: Bool, reduceTransparency: Bool) = MeetingControlsPanel.systemDisplayOptions,
         mouseLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation }) {
        self.recorder = recorder
        self.settings = settings
        self.screens = screens
        self.announce = announce
        self.displayOptions = displayOptions
        drawer = MeetingTranscriptDrawer(mouseLocation: mouseLocation, reduceMotion: { displayOptions().reduceMotion })
        super.init(contentRect: NSRect(x: 0, y: 0, width: Layout.recordingWidth, height: Layout.pillHeight))
        pill.mouseLocation = mouseLocation
        // Ku-Ka never activates, and an NSPanel hides when its app deactivates.
        hidesOnDeactivate = false
        // A click on Pause or Stop leaves the keyboard with the meeting app.
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        autorecalculatesKeyViewLoop = true

        buildPill()
        drawer.onHide = { [weak self] in self?.recorder.dismissControls() }
        drawer.onResizeBegan = { [weak self] in self?.resizeBegan() }
        drawer.onResizeMoved = { [weak self] in self?.resizeMoved(by: $0) }
        drawer.onResizeEnded = { [weak self] in self?.resizeEnded() }
        root.wantsLayer = true
        root.layer?.cornerRadius = Layout.cornerRadius
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        contentView = root
        // A zero frame would break every inner constraint until the first layout.
        drawer.frame = root.bounds
        root.addSubview(drawer)
        root.drawer = drawer
        applyAccessibilityDisplay()

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    /// Claims both recorder slots for the panel. The owner calls this once, at launch, before any
    /// meeting.
    func bindRecorder() {
        recorder.onControlsChange = { [weak self] in self?.reload() }
        recorder.onControlsRequest = { [weak self] in self?.handle($0) }
    }

    /// For keyboard use after Show Meeting Controls. A click on a button never makes it key.
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        recorder.setTranscriptOpen(false)
    }

    /// End returns to live from any control. Keys a control does not use come here.
    override func keyDown(with event: NSEvent) {
        guard Int(event.keyCode) == kVK_End else { return super.keyDown(with: event) }
        drawer.returnToLive()
    }

    static func postAnnouncement(_ text: String, priority: NSAccessibilityPriorityLevel) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: priority.rawValue])
    }

    static func systemDisplayOptions() -> (reduceMotion: Bool, reduceTransparency: Bool) {
        (NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
         NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    }

    /// Only a new `Shape` needs layout; ticks and new text update their views directly.
    func reload() {
        let controls = recorder.controls
        if let announcement = MeetingPanelCopy.announcement(from: announcedStatus, to: controls?.status) {
            announce(announcement.text, announcement.priority)
        }
        announcedStatus = controls?.status
        guard let controls else { return disappear() }

        let wasOpen = !drawer.isHidden
        let isAppearing = !isVisible
        renderTime(controls.recordedTime)
        drawer.showBehind(controls.preview?.behind)
        let shape = Shape(status: controls.status, isTranscriptOpen: controls.isTranscriptOpen,
                          liveStatus: controls.preview?.status)
        if isAppearing || shape != drawnShape {
            drawnShape = shape
            render(shape)
            relayout(shape, animated: !isAppearing && !displayOptions().reduceMotion)
        }
        drawer.showRows(controls.preview?.rows ?? [])
        if controls.isTranscriptOpen, !wasOpen { drawer.opened() }
        if isAppearing { appear() }
    }

    private func renderTime(_ recorded: TimeInterval?) {
        guard let recorded else { return }
        let time = RecordedTime.format(recorded)
        guard time != timeLabel.stringValue else { return }
        timeLabel.stringValue = time
        timeLabel.setAccessibilityLabel(MeetingPanelCopy.timeLabel(recorded))
    }

    private func render(_ shape: Shape) {
        let status = shape.status
        let isStarting = status == .starting
        let isPaused = status == .paused
        let showsTime = isPaused || status == .recording
        let isRecorder = isStarting || showsTime
        mark.status = status
        spinner.isHidden = !isStarting
        mark.isHidden = isStarting
        if isStarting, !displayOptions().reduceMotion { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }

        timeLabel.isHidden = !showsTime
        timeLabel.textColor = isPaused ? .secondaryLabelColor : .labelColor
        wordLabel.show(MeetingPanelCopy.word(for: status))

        for view in [pauseButton, stopButton, transcriptButton, buttonSeparator] { view.isHidden = !isRecorder }
        closeButton.isHidden = isRecorder
        pauseButton.isEnabled = !isStarting
        stopButton.isEnabled = !isStarting
        transcriptButton.isEnabled = !isStarting
        pauseButton.configure(symbol: isPaused ? Self.symbol("circle.fill", size: 9, color: .systemRed)
                                               : Self.symbol("pause.fill", size: 12, color: .labelColor),
                              copy: MeetingPanelCopy.pauseButton(isPaused: isPaused))

        noteLabel.show(MeetingPanelCopy.note(for: status))

        drawer.isHidden = !shape.isTranscriptOpen
        drawer.showMessage(for: shape.liveStatus)
    }

    private func pillSize(for shape: Shape) -> CGSize {
        guard !shape.isTranscriptOpen else { return CGSize(width: Layout.openWidth, height: Layout.pillHeight) }
        switch shape.status {
        case .starting: return CGSize(width: Layout.startingWidth, height: Layout.pillHeight)
        case .recording: return CGSize(width: Layout.recordingWidth, height: Layout.pillHeight)
        case .paused: return CGSize(width: Layout.pausedWidth, height: Layout.pillHeight)
        case .saved, .interrupted:
            let width = Layout.noticeWidth - Layout.noteLeading - Layout.noteTrailing
            let note = noteLabel.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude))
            return CGSize(width: Layout.noticeWidth, height: Layout.noteTop + ceil(note.height) + Layout.noteBottom)
        }
    }

    private var drawerHeight: CGFloat {
        resizeHeight ?? MeetingPanelPlacement.clampedDrawerHeight(CGFloat(settings.meetingTranscriptHeight))
    }

    private func placement(for shape: Shape) -> Placement? {
        let size = pillSize(for: shape)
        let layout = screens.all
        guard let corner = MeetingPanelPlacement.pillTopRight(saved: dragCorner ?? settings.meetingControlsTopRight,
                                                              pillSize: size, screens: layout) else { return nil }
        let open = MeetingPanelPlacement.frame(pillTopRight: corner, pillSize: size, drawerHeight: drawerHeight, screens: layout)
        let frame = shape.isTranscriptOpen
            ? open.frame
            : MeetingPanelPlacement.frame(pillTopRight: corner, pillSize: size, drawerHeight: nil, screens: layout).frame
        return Placement(frame: frame, pillHeight: size.height, pillTopRight: corner, drawerAbove: open.drawerAbove)
    }

    private func relayout(_ shape: Shape, animated: Bool) {
        guard let placement = placement(for: shape) else { return }
        apply(placement, isOpen: shape.isTranscriptOpen, animated: animated)
    }

    private func apply(_ placement: Placement, isOpen: Bool, animated: Bool) {
        self.placement = placement
        let above = placement.drawerAbove
        root.pillHeight = placement.pillHeight
        root.drawerAbove = above
        drawer.setAbovePill(above)
        (pillBackground as? NSGlassEffectView)?.cornerRadius = isOpen ? 0 : Layout.cornerRadius
        (pillBackground as? MeetingPanelFill)?.rounded = isOpen ? (above ? .bottom : .top) : .all
        let points = isOpen != above ? "chevron.up" : "chevron.down"
        transcriptButton.configure(symbol: Self.symbol(points, size: 11, color: .labelColor),
                                   copy: MeetingPanelCopy.transcriptButton(isOpen: isOpen))

        setFrame(placement.frame, animated: animated)
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
        invalidateShadow()
    }

    private func setFrame(_ frame: CGRect, animated: Bool) {
        guard frame != targetFrame else { return }
        targetFrame = frame
        drawer.ignoringScroll { setFrame(frame, display: true, animate: animated) }
    }

    /// Reduce Motion: the frame changes at once, and only the drawer fades.
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval {
        displayOptions().reduceMotion ? 0 : Layout.resizeDuration
    }

    private func appear() {
        setAlphaImmediately(0)
        orderFrontRegardless()
        fadeIn(duration: Layout.fadeDuration)
    }

    private func disappear() {
        guard isVisible else { return }
        orderOut(nil)
        setAlphaImmediately(1)
        dragStart = nil
        dragCorner = nil
        resizeStart = nil
        resizeHeight = nil
    }

    private func handle(_ request: MeetingControlsRequest) {
        switch request {
        case .focus:
            makeKeyAndOrderFront(nil)
        case .restoreDefaultPosition:
            settings.meetingControlsTopRight = nil
            guard isVisible, let drawnShape else { return }
            relayout(drawnShape, animated: !displayOptions().reduceMotion)
        }
    }

    @objc private func pauseClicked() { recorder.togglePause() }
    @objc private func stopClicked() { recorder.stopRecording() }
    @objc private func closeClicked() { recorder.dismissControls() }

    @objc private func transcriptClicked() { recorder.toggleTranscript() }

    private func dragBegan() {
        dragStart = placement?.pillTopRight
    }

    private func dragMoved(by offset: CGSize) {
        guard let dragStart, let drawnShape else { return }
        dragCorner = CGPoint(x: dragStart.x + offset.width, y: dragStart.y + offset.height)
        relayout(drawnShape, animated: false)
    }

    /// Saves the corner as placed, so on a screen. A click without a move saves nothing.
    private func dragEnded() {
        dragStart = nil
        guard dragCorner != nil else { return }
        dragCorner = nil
        if let corner = placement?.pillTopRight { settings.meetingControlsTopRight = corner }
    }

    private func resizeBegan() {
        guard let placement else { return }
        resizeStart = (drawerHeight, placement.drawerAbove)
    }

    /// Keeps the drawer on its side: a height that would flip it is not taken.
    private func resizeMoved(by offset: CGSize) {
        guard let start = resizeStart, let drawnShape else { return }
        let previous = resizeHeight
        resizeHeight = MeetingPanelPlacement.clampedDrawerHeight(start.height + (start.drawerAbove ? offset.height : -offset.height))
        guard let placement = placement(for: drawnShape), placement.drawerAbove == start.drawerAbove else {
            resizeHeight = previous
            return
        }
        apply(placement, isOpen: drawnShape.isTranscriptOpen, animated: false)
    }

    private func resizeEnded() {
        resizeStart = nil
        guard let height = resizeHeight else { return }
        resizeHeight = nil
        settings.meetingTranscriptHeight = Double(height)
    }

    @objc private func screensChanged() {
        guard isVisible, let drawnShape else { return }
        relayout(drawnShape, animated: false)
    }

    @objc private func displayOptionsChanged() {
        applyAccessibilityDisplay()
        guard isVisible else { return }
        drawnShape = nil
        reload()
    }

    private func applyAccessibilityDisplay() {
        let solid = displayOptions().reduceTransparency
        if let pillBackground, solid == (pillBackground is MeetingPanelFill) { return }
        (pillBackground as? NSGlassEffectView)?.contentView = nil
        pill.removeFromSuperview()
        pillBackground?.removeFromSuperview()
        let background: NSView
        if solid {
            background = MeetingPanelFill(color: Colors.solid, radius: Layout.cornerRadius)
            background.addSubview(pill)
        } else {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = Layout.cornerRadius
            glass.contentView = pill
            background = glass
        }
        background.frame = NSRect(x: 0, y: 0, width: root.bounds.width, height: root.pillHeight)
        root.addSubview(background)
        root.pill = background
        pillBackground = background
        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            pill.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            pill.topAnchor.constraint(equalTo: background.topAnchor),
            pill.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        if let placement { apply(placement, isOpen: !drawer.isHidden, animated: false) }
    }

    private func buildPill() {
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.onBegan = { [weak self] in self?.dragBegan() }
        pill.onMoved = { [weak self] in self?.dragMoved(by: $0) }
        pill.onEnded = { [weak self] in self?.dragEnded() }

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = true
        spinner.setAccessibilityElement(false)
        wordLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let status = NSStackView(views: [spinner, mark, timeLabel, wordLabel])
        status.orientation = .horizontal
        status.spacing = Layout.statusSpacing
        status.detachesHiddenViews = true
        status.translatesAutoresizingMaskIntoConstraints = false

        stopButton.configure(symbol: Self.symbol("stop.fill", size: 11, color: .systemRed), copy: MeetingPanelCopy.stopButton)
        closeButton.configure(symbol: Self.symbol("xmark", size: 11, color: .labelColor), copy: MeetingPanelCopy.closeButton)
        buttonSeparator.translatesAutoresizingMaskIntoConstraints = false
        let buttons = NSStackView(views: [pauseButton, stopButton, closeButton, buttonSeparator, transcriptButton])
        buttons.orientation = .horizontal
        buttons.spacing = Layout.buttonSpacing
        buttons.detachesHiddenViews = true
        buttons.translatesAutoresizingMaskIntoConstraints = false

        noteLabel.translatesAutoresizingMaskIntoConstraints = false
        noteLabel.preferredMaxLayoutWidth = Layout.noticeWidth - Layout.noteLeading - Layout.noteTrailing
        noteLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for view in [status, buttons, noteLabel] { pill.addSubview(view) }
        NSLayoutConstraint.activate([
            status.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: Layout.pillLeading),
            status.centerYAnchor.constraint(equalTo: pill.topAnchor, constant: Layout.pillHeight / 2),
            status.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -Layout.buttonSpacing),
            buttons.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -Layout.pillTrailing),
            buttons.centerYAnchor.constraint(equalTo: pill.topAnchor, constant: Layout.pillHeight / 2),
            buttonSeparator.widthAnchor.constraint(equalToConstant: 0.5),
            buttonSeparator.heightAnchor.constraint(equalToConstant: 18),
            noteLabel.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: Layout.noteLeading),
            noteLabel.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -Layout.noteTrailing),
            noteLabel.topAnchor.constraint(equalTo: pill.topAnchor, constant: Layout.noteTop),
        ])
    }
}

/// Puts the pill at its edge of the window and gives the drawer the rest, at every size while
/// the window's frame animates.
private final class RootView: NSView {
    var pillHeight = MeetingControlsPanel.Layout.pillHeight
    var drawerAbove = false
    weak var pill: NSView?
    weak var drawer: NSView?

    override func layout() {
        pill?.frame = NSRect(x: 0, y: drawerAbove ? 0 : bounds.height - pillHeight, width: bounds.width, height: pillHeight)
        drawer?.frame = NSRect(x: 0, y: drawerAbove ? pillHeight : 0, width: bounds.width,
                               height: max(0, bounds.height - pillHeight))
        super.layout()
    }
}
