import Cocoa

/// Owns rows, follow state, and scroll position. The panel owns visibility and geometry.
final class MeetingTranscriptDrawer: NSView {
    private typealias Layout = MeetingControlsPanel.Layout
    private typealias Colors = MeetingControlsPanel.Colors

    private static let speechCell = NSUserInterfaceItemIdentifier("MeetingSpeechCell")
    private static let pauseCell = NSUserInterfaceItemIdentifier("MeetingPauseCell")

    private let reduceMotion: () -> Bool
    private var follow = TranscriptFollow()
    private var rows: [LiveRow] = []
    /// True while the panel or the drawer itself scrolls or resizes the transcript, so only a
    /// scroll by the user changes `follow`.
    private var isMovingTranscript = false

    private let background = MeetingPanelFill(color: Colors.drawer, radius: Layout.cornerRadius, rounded: .bottom)
    private let pillEdge = MeetingPanelFill(color: .separatorColor, rounded: .none)
    private let header = NSStackView()
    private let behindChip = MeetingPanelFill(color: Colors.button, radius: 6)
    private let behindLabel = NSTextField.makeLabel(size: 11, weight: .semibold, digits: true)
    private lazy var hideButton = NSButton(title: "", target: self, action: #selector(hideClicked))
    private let messageTitle = NSTextField.makeLabel(size: 13, weight: .semibold)
    private let messageBody = NSTextField.makeWrappingLabel(size: 12.5, color: .secondaryLabelColor)
    private let messageStack = NSStackView()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let transcriptFade = MeetingTranscriptFade()
    private lazy var returnToLiveButton = MeetingPanelButton(fill: Colors.solid, floats: true, target: self,
                                                             action: #selector(returnToLiveClicked))
    private let grip = MeetingDrawerGrip()
    private var belowPillConstraints: [NSLayoutConstraint] = []
    private var abovePillConstraints: [NSLayoutConstraint] = []
    private var scrollBelowMessage: NSLayoutConstraint!
    private var scrollAtBodyTop: NSLayoutConstraint!

    var onHide: (() -> Void)?
    var onResizeBegan: (() -> Void)? {
        get { grip.onBegan }
        set { grip.onBegan = newValue }
    }
    var onResizeMoved: ((CGSize) -> Void)? {
        get { grip.onMoved }
        set { grip.onMoved = newValue }
    }
    var onResizeEnded: (() -> Void)? {
        get { grip.onEnded }
        set { grip.onEnded = newValue }
    }

    init(mouseLocation: @escaping () -> CGPoint, reduceMotion: @escaping () -> Bool) {
        self.reduceMotion = reduceMotion
        super.init(frame: .zero)
        grip.mouseLocation = mouseLocation
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(transcriptScrolled),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The header always lies next to the pill and the grip at the far edge.
    func setAbovePill(_ above: Bool) {
        NSLayoutConstraint.deactivate(above ? belowPillConstraints : abovePillConstraints)
        NSLayoutConstraint.activate(above ? abovePillConstraints : belowPillConstraints)
        background.rounded = above ? .top : .bottom
    }

    /// Nil while the drawer is closed.
    func showMessage(for status: LiveTranscript.Status?) {
        let message = status.flatMap(MeetingPanelCopy.message(for:))
        messageStack.isHidden = message == nil
        messageTitle.stringValue = message?.title ?? ""
        messageBody.stringValue = message?.body ?? ""
        scrollAtBodyTop.isActive = false
        scrollBelowMessage.isActive = false
        (message == nil ? scrollAtBodyTop : scrollBelowMessage).isActive = true
    }

    func showBehind(_ behind: TimeInterval?) {
        let chip = MeetingPanelCopy.behindChip(behind)
        behindChip.isHidden = chip == nil
        if let chip, chip != behindLabel.stringValue { behindLabel.stringValue = chip }
    }

    /// Replaces only the rows after the unchanged start, so new text measures only new rows.
    func showRows(_ newRows: [LiveRow]) {
        guard newRows != rows else { return }
        let old = rows
        let kept = zip(old, newRows).prefix { $0 == $1 }.count
        rows = newRows
        ignoringScroll {
            tableView.beginUpdates()
            if old.count > kept { tableView.removeRows(at: IndexSet(kept..<old.count), withAnimation: []) }
            if newRows.count > kept { tableView.insertRows(at: IndexSet(kept..<newRows.count), withAnimation: []) }
            tableView.endUpdates()
            follow.rowsChanged(from: old.count, to: newRows.count)
            if follow.isFollowing { scrollToEnd(animated: false) }
        }
        renderReturnToLive()
    }

    func opened() {
        follow.returnToLive()
        scrollToEnd(animated: false)
        renderReturnToLive()
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.fadeDuration
            animator().alphaValue = 1
        }
    }

    func returnToLive() {
        follow.returnToLive()
        scrollToEnd(animated: !reduceMotion())
        renderReturnToLive()
    }

    /// Runs `work`, which moves or resizes the transcript, without a change to `follow`.
    func ignoringScroll(_ work: () -> Void) {
        let wasMoving = isMovingTranscript
        isMovingTranscript = true
        work()
        isMovingTranscript = wasMoving
    }

    private func scrollToEnd(animated: Bool) {
        guard !rows.isEmpty else { return }
        // The panel's root view sets this view's frame, so the layout starts there.
        superview?.layoutSubtreeIfNeeded()
        let clip = scrollView.contentView
        let end = clip.constrainBoundsRect(NSRect(origin: NSPoint(x: 0, y: tableView.bounds.maxY),
                                                  size: clip.bounds.size)).origin
        guard animated else {
            ignoringScroll {
                clip.scroll(to: end)
                scrollView.reflectScrolledClipView(clip)
            }
            return
        }
        isMovingTranscript = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Layout.resizeDuration
            clip.animator().setBoundsOrigin(end)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.isMovingTranscript = false
                self?.scrollView.reflectScrolledClipView(clip)
            }
        })
    }

    @objc private func transcriptScrolled() {
        guard !isMovingTranscript, !rows.isEmpty else { return }
        follow.scrolled(lastRowVisible: tableView.rect(ofRow: rows.count - 1).intersects(tableView.visibleRect))
        renderReturnToLive()
    }

    private func renderReturnToLive() {
        let title = follow.returnToLiveTitle
        returnToLiveButton.isHidden = title == nil
        guard let title else { return }
        returnToLiveButton.configure(symbol: MeetingControlsPanel.symbol("arrow.down", size: 11, color: .labelColor),
                                     copy: MeetingPanelCopy.Button(title: title, label: title, tooltip: title))
    }

    @objc private func hideClicked() { onHide?() }
    @objc private func returnToLiveClicked() { returnToLive() }

    private func build() {
        let title = NSTextField.makeLabel(size: 12, weight: .semibold)
        title.stringValue = MeetingPanelCopy.transcriptTitle
        let draft = NSTextField.makeLabel(size: 11.5, color: .secondaryLabelColor)
        draft.stringValue = MeetingPanelCopy.draftNote
        draft.toolTip = MeetingPanelCopy.draftTooltip
        draft.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        draft.setContentHuggingPriority(.defaultLow, for: .horizontal)

        behindLabel.translatesAutoresizingMaskIntoConstraints = false
        behindChip.addSubview(behindLabel)
        NSLayoutConstraint.activate([
            behindLabel.leadingAnchor.constraint(equalTo: behindChip.leadingAnchor, constant: 7),
            behindLabel.trailingAnchor.constraint(equalTo: behindChip.trailingAnchor, constant: -7),
            behindLabel.topAnchor.constraint(equalTo: behindChip.topAnchor, constant: 3),
            behindLabel.bottomAnchor.constraint(equalTo: behindChip.bottomAnchor, constant: -3),
        ])

        hideButton.isBordered = false
        hideButton.attributedTitle = NSAttributedString(string: MeetingPanelCopy.hideButton.title ?? "", attributes: [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        hideButton.setAccessibilityLabel(MeetingPanelCopy.hideButton.label)
        hideButton.toolTip = MeetingPanelCopy.hideButton.tooltip

        header.setViews([title, draft], in: .leading)
        header.setViews([behindChip, hideButton], in: .trailing)
        header.orientation = .horizontal
        header.spacing = 8
        header.detachesHiddenViews = true
        header.edgeInsets = NSEdgeInsets(top: 0, left: Layout.rowInset, bottom: 0, right: 10)

        messageStack.setViews([messageTitle, messageBody], in: .top)
        messageStack.orientation = .vertical
        messageStack.alignment = .leading
        messageStack.spacing = 6
        messageBody.preferredMaxLayoutWidth = Layout.openWidth - 2 * Layout.messageInset

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MeetingTranscriptColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.rowSizeStyle = .custom
        tableView.intercellSpacing = .zero
        tableView.gridStyleMask = []
        tableView.selectionHighlightStyle = .none
        tableView.backgroundColor = .clear
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        // A list the user reads, not a live region: rows are never announced.
        tableView.setAccessibilityLabel(MeetingPanelCopy.transcriptLabel)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 2, left: 0, bottom: 8, right: 0)

        grip.toolTip = MeetingPanelCopy.heightGripTooltip
        returnToLiveButton.isHidden = true

        background.frame = bounds
        background.autoresizingMask = [.width, .height]
        addSubview(background)
        let body = NSLayoutGuide()
        addLayoutGuide(body)
        for view in [pillEdge, header, messageStack, scrollView, transcriptFade, returnToLiveButton, grip] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        // While the window grows from the pill alone, the drawer is shorter than its parts.
        let gripAtFarEdgeBelow = grip.bottomAnchor.constraint(equalTo: bottomAnchor)
        let headerAtFarEdgeAbove = header.bottomAnchor.constraint(equalTo: bottomAnchor)
        for constraint in [gripAtFarEdgeBelow, headerAtFarEdgeAbove] { constraint.priority = .defaultHigh }

        NSLayoutConstraint.activate([
            pillEdge.leadingAnchor.constraint(equalTo: leadingAnchor),
            pillEdge.trailingAnchor.constraint(equalTo: trailingAnchor),
            pillEdge.heightAnchor.constraint(equalToConstant: 0.5),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: Layout.headerHeight),
            body.leadingAnchor.constraint(equalTo: leadingAnchor),
            body.trailingAnchor.constraint(equalTo: trailingAnchor),
            messageStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.messageInset),
            messageStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.messageInset),
            messageStack.topAnchor.constraint(equalTo: body.topAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            transcriptFade.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            transcriptFade.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            transcriptFade.topAnchor.constraint(equalTo: scrollView.topAnchor),
            transcriptFade.heightAnchor.constraint(equalToConstant: 14),
            returnToLiveButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            returnToLiveButton.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -Layout.returnToLiveBottom),
            grip.leadingAnchor.constraint(equalTo: leadingAnchor),
            grip.trailingAnchor.constraint(equalTo: trailingAnchor),
            grip.heightAnchor.constraint(equalToConstant: Layout.gripHeight),
        ])
        scrollAtBodyTop = scrollView.topAnchor.constraint(equalTo: body.topAnchor)
        scrollBelowMessage = scrollView.topAnchor.constraint(equalTo: messageStack.bottomAnchor, constant: 8)
        belowPillConstraints = [
            pillEdge.topAnchor.constraint(equalTo: topAnchor),
            header.topAnchor.constraint(equalTo: topAnchor),
            body.topAnchor.constraint(equalTo: header.bottomAnchor),
            body.bottomAnchor.constraint(equalTo: grip.topAnchor),
            gripAtFarEdgeBelow,
        ]
        abovePillConstraints = [
            pillEdge.bottomAnchor.constraint(equalTo: bottomAnchor),
            grip.topAnchor.constraint(equalTo: topAnchor),
            body.topAnchor.constraint(equalTo: grip.bottomAnchor),
            body.bottomAnchor.constraint(equalTo: header.topAnchor),
            headerAtFarEdgeAbove,
        ]
        NSLayoutConstraint.activate(belowPillConstraints + [scrollAtBodyTop])
        isHidden = true
    }
}

extension MeetingTranscriptDrawer: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rows[row].content {
        case .pause:
            return Layout.pauseRowHeight
        case .speech(_, let text, let isFinal):
            return TranscriptSpeechCell.height(text: text, isFinal: isFinal, isContinuation: isContinuation(row))
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = rows[row]
        switch item.content {
        case .pause(let duration):
            let cell = tableView.makeView(withIdentifier: Self.pauseCell, owner: self) as? TranscriptPauseCell
                ?? TranscriptPauseCell()
            cell.identifier = Self.pauseCell
            cell.configure(at: item.at, duration: duration)
            return cell
        case .speech(let speaker, let text, let isFinal):
            let cell = tableView.makeView(withIdentifier: Self.speechCell, owner: self) as? TranscriptSpeechCell
                ?? TranscriptSpeechCell()
            cell.identifier = Self.speechCell
            cell.configure(speaker: speaker, at: item.at, text: text, isFinal: isFinal, isContinuation: isContinuation(row))
            return cell
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    /// The same speaker as the row before: the label and time are not repeated.
    private func isContinuation(_ row: Int) -> Bool {
        guard row > 0, case .speech(let speaker, _, _) = rows[row].content,
              case .speech(let previous, _, _) = rows[row - 1].content else { return false }
        return speaker == previous
    }
}
