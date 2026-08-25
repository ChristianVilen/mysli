import Cocoa

/// The clipboard-history overlay: a filter field above a list of recorded
/// items, floating on `NSGlassEffectView` glass roughly where Spotlight
/// appears.
///
/// Pure view. Every piece of state it draws — the visible items, the
/// selected row, list-versus-chooser mode — belongs to
/// `ClipboardHistoryController`; the panel reads that state to render and
/// pushes key events back into the controller's entry points. It reads no
/// history, no `NSPasteboard`, and no `Settings`. Sizes and insets live in
/// `Metrics`, next to the row views that draw against the same numbers.
///
/// Focus discipline matters here: the panel is borderless and
/// `.nonactivatingPanel`, so it takes key status without activating Ku-Ka.
/// The app the user was working in stays frontmost, which is what the
/// synthetic Cmd+V after a paste needs. Never call `NSApp.activate` from
/// this file.
final class ClipboardPanel: FloatingPanel {

    private static let emptyStateText = "Nothing copied yet"
    private static let cellIdentifier = NSUserInterfaceItemIdentifier("ClipboardRowCell")
    private static let rowIdentifier = NSUserInterfaceItemIdentifier("ClipboardRowView")

    /// The two chooser rows in the order `ClipboardHistoryController`
    /// indexes them: 0 is "without formatting" and is pre-selected, 1 is
    /// "with formatting".
    private static let chooserRows: [(symbol: String, title: String)] = [
        ("text.alignleft", "Paste without formatting"),
        ("textformat", "Paste with formatting"),
    ]

    // MARK: - Collaborators

    private let controller: ClipboardHistoryController
    private let screens: Screens

    // MARK: - Views

    private let searchGlyph = NSImageView()
    private let searchField = NSTextField()
    private let headerLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var scrollTopConstraint: NSLayoutConstraint!

    /// Thumbnails only — each one is at most 2× `Metrics.thumbnailBox`, so
    /// the panel never holds a full-size bitmap.
    private let thumbnails = ClipboardThumbnailCache()

    /// Guards against re-entry: `orderOut` makes the panel resign key, and
    /// `resignKey` dismisses.
    private var isDismissing = false

    // MARK: - Init

    init(controller: ClipboardHistoryController, screens: Screens = SystemScreens()) {
        self.controller = controller
        self.screens = screens
        super.init(contentRect: NSRect(origin: .zero, size: Metrics.size))

        // An NSPanel hides itself when its app deactivates. Ku-Ka is a menu
        // bar app that deliberately never activates, so that default would
        // hide the panel the moment it appears.
        hidesOnDeactivate = false
        // A clipboard panel is reached by a global hotkey, so it has to
        // follow the user across spaces and over full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        buildChrome()
    }

    /// Claims *both* of the controller's callback slots: a list change
    /// redraws the panel, and a close request dismisses it. The owner calls
    /// this once, straight after building the panel.
    ///
    /// Deliberately not part of `init`: the claim belongs at the owner's
    /// call site, where anything else that wants to hear about list changes
    /// can see that these two slots are already taken and route through the
    /// panel instead of quietly overwriting them.
    func bindController() {
        controller.onListChanged = { [weak self] in self?.reload() }
        controller.onPanelShouldClose = { [weak self] in self?.dismiss() }
    }

    // MARK: - Key status

    /// The panel has to be key to receive typing, but `.nonactivatingPanel`
    /// keeps Ku-Ka itself in the background while it is.
    override var canBecomeKey: Bool { true }

    /// Clicking away or switching apps closes the panel. Dismissal is
    /// view-side only: the controller's state resets on the next `show()`
    /// through `prepareForPresentation()`.
    override func resignKey() {
        super.resignKey()
        dismiss()
    }

    /// Backstop for Esc when the search field is not handling it (the field
    /// normally is — see `control(_:textView:doCommandBy:)`).
    override func cancelOperation(_ sender: Any?) {
        controller.escPressed()
    }

    // MARK: - Presentation

    /// Opens the panel on the screen under the pointer, with an empty
    /// filter and the newest item selected.
    func show() {
        assert(controller.onListChanged != nil, "call bindController() before show()")
        controller.prepareForPresentation()
        searchField.stringValue = ""
        reload()

        if let origin = targetOrigin(mouseLocation: NSEvent.mouseLocation) {
            setFrameOrigin(origin)
        }

        // `show()` only ever runs on a hidden panel — the caller's toggle
        // dismisses on a second hotkey press instead of calling `show()`
        // again — so this always sets the pre-fade alpha; kept as a guard
        // rather than an assumption, since restarting the fade on an
        // already-visible panel would blink a panel being read.
        if !isVisible {
            setAlphaImmediately(shouldFade ? 0 : 1)
        }

        // Not `NSApp.activate`: the app the user was in must stay frontmost.
        makeKeyAndOrderFront(nil)
        makeFirstResponder(searchField)

        guard shouldFade, alphaValue < 1 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Metrics.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    /// Hides the panel at once. No fade out: a paste dismisses the panel
    /// and then sends Cmd+V a moment later, and a window still fading would
    /// be in the way of that keystroke.
    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        // Ends the field editor before the window goes away, so the next
        // `show()` starts from a clean one rather than inheriting a stale
        // editing session. `show()` re-establishes first responder.
        makeFirstResponder(nil)
        orderOut(nil)
        setAlphaImmediately(1)
        thumbnails.removeAll()
        isDismissing = false
    }

    private var shouldFade: Bool {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Writes alpha through a zero-duration animation, which also replaces
    /// any fade still in flight. A plain `alphaValue =` would be overwritten
    /// by the running animation on its next tick.
    private func setAlphaImmediately(_ value: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            animator().alphaValue = value
        }
    }

    /// Horizontally centered on the screen under the pointer, with the top
    /// edge a quarter of the way down that screen's visible height.
    private func targetOrigin(mouseLocation: CGPoint) -> NSPoint? {
        let layout = screens.all
        guard let screen = ScreenGeometry.under(mouseLocation, in: layout) ?? layout.first else { return nil }

        let visible = screen.visibleFrame
        let x = visible.midX - Metrics.size.width / 2
        let topEdge = visible.maxY - visible.height * Metrics.topFraction
        // Keep the whole panel on screen: not past the visible bottom, and
        // not past the visible top. The top clamp is applied last so it
        // wins on a display shorter than the panel, where the two disagree
        // — a panel running off the bottom is far better than one whose
        // search field is off the top.
        var y = max(topEdge - Metrics.size.height, visible.minY)
        y = min(y, visible.maxY - Metrics.size.height)
        return NSPoint(x: x.rounded(), y: y.rounded())
    }

    // MARK: - Rendering

    /// Redraws everything the controller currently says to show. Cheap
    /// enough to be the single entry point for every change — the list
    /// caps out at `ClipboardHistory.maxItems` rows.
    func reload() {
        if case .chooser(let item) = controller.mode {
            headerLabel.isHidden = false
            headerLabel.stringValue = Self.headerText(for: item)
            scrollTopConstraint.constant = Metrics.chooserTopGap
        } else {
            headerLabel.isHidden = true
            headerLabel.stringValue = ""
            scrollTopConstraint.constant = Metrics.listTopGap
        }

        tableView.reloadData()
        syncSelection()
    }

    /// Names the item the chooser is deciding on, cut to a readable
    /// prefix. The label truncates on its own once the width pin bites,
    /// but capping the string as well keeps the header short on every
    /// display width instead of only on narrow ones.
    private static func headerText(for item: ClipboardItem) -> String {
        let preview = item.previewLabel
        guard preview.count > Metrics.headerPreviewMaxLength else {
            return "Paste “\(preview)”"
        }
        let shortened = preview.prefix(Metrics.headerPreviewMaxLength)
            .trimmingCharacters(in: .whitespaces)
        return "Paste “\(shortened)…”"
    }

    private func syncSelection() {
        let row = controller.selectionIndex
        guard row >= 0, row < tableView.numberOfRows, rowsAreSelectable else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    /// False only while the list mode shows its empty-state row, which is a
    /// message rather than something to paste. Every other row, in either
    /// mode, can be selected.
    private var rowsAreSelectable: Bool {
        if case .chooser = controller.mode { return true }
        return !controller.visibleItems.isEmpty
    }

    // MARK: - Mouse

    /// The clicked row when it is a real, selectable one — nil for a click
    /// on the empty-state message or on blank space below the last row.
    private var clickedSelectableRow: Int? {
        let row = tableView.clickedRow
        guard row >= 0, rowsAreSelectable else { return nil }
        return row
    }

    @objc private func rowClicked() {
        guard let row = clickedSelectableRow else { return }
        controller.selectRow(row)
    }

    @objc private func rowDoubleClicked() {
        guard let row = clickedSelectableRow else { return }
        controller.selectRow(row)
        controller.enterPressed()
    }

    // MARK: - Chrome

    private func buildChrome() {
        // Frameless: the constraints below own its geometry.
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.cornerRadius = Metrics.cornerRadius
        // The list scrolls right up to the glass edge, so the rounding has
        // to clip it rather than only being painted behind it.
        container.layer?.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false

        configureSearchRow()
        configureHeader()
        configureTable()

        let separator = NSBox()
        separator.boxType = .separator
        // A separator has no content to be wide about, but it is pinned to
        // both container edges like the header is, so it gets the same
        // treatment rather than being left as the one unchecked view.
        separator.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        separator.translatesAutoresizingMaskIntoConstraints = false

        for view in [searchGlyph, searchField, separator, headerLabel, scrollView] {
            container.addSubview(view)
        }

        scrollTopConstraint = scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: Metrics.listTopGap)

        NSLayoutConstraint.activate([
            searchGlyph.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.contentInset),
            searchGlyph.widthAnchor.constraint(equalToConstant: Metrics.iconSlot),
            searchGlyph.heightAnchor.constraint(equalToConstant: Metrics.iconSlot),
            searchGlyph.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),

            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: Metrics.searchTopInset),
            searchField.leadingAnchor.constraint(equalTo: searchGlyph.trailingAnchor, constant: Metrics.iconGap),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Metrics.contentInset),

            separator.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: Metrics.separatorGap),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: Metrics.separatorHeight),

            headerLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: Metrics.listTopGap),
            headerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.contentInset),
            headerLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Metrics.contentInset),
            headerLabel.heightAnchor.constraint(equalToConstant: Metrics.headerHeight),

            scrollTopConstraint,
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.tableInset),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Metrics.tableInset),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Metrics.bottomInset),
        ])

        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: Metrics.size))
        // `.regular` rather than `.clear`: this panel is mostly text, and
        // regular glass is the one tuned to keep text legible over any
        // wallpaper. `tintColor` is left unset so the glass stays neutral;
        // it is the knob to reach for if the panel turns out short of
        // contrast on a busy light desktop at first run.
        glass.style = .regular
        glass.cornerRadius = Metrics.cornerRadius
        glass.contentView = container
        contentView = glass

        // Size the content explicitly rather than letting it be inferred.
        // The window is borderless, so AppKit takes its minimum content
        // size from the content view's fitting size; with no width pin, the
        // widest label's intrinsic width becomes that minimum. That is what
        // once stretched the panel past the screen edge when a chooser
        // header carried a 500-character preview.
        //
        // Position comes from leading/top, size from width/height. Pinning
        // trailing and bottom as well would tie the container's width back
        // to the glass's own and re-open the same argument from the other
        // side, so those two are deliberately left out.
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            container.topAnchor.constraint(equalTo: glass.topAnchor),
            container.widthAnchor.constraint(equalToConstant: Metrics.size.width),
            container.heightAnchor.constraint(equalToConstant: Metrics.size.height),
        ])
    }

    private func configureSearchRow() {
        let font = NSFont.systemFont(ofSize: Metrics.searchFontSize)

        searchGlyph.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchGlyph.contentTintColor = .secondaryLabelColor
        searchGlyph.imageScaling = .scaleProportionallyUpOrDown
        searchGlyph.translatesAutoresizingMaskIntoConstraints = false

        // A plain borderless field rather than an NSSearchField: a search
        // field brings its own bezel, and a second rounded surface inside
        // the glass reads as clutter.
        searchField.isBezeled = false
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = font
        searchField.textColor = .labelColor
        searchField.maximumNumberOfLines = 1
        searchField.cell?.usesSingleLineMode = true
        // Same rule as the header: a long filter string must scroll inside
        // the field editor, not push the panel wider. No `lineBreakMode`
        // here — the field is editable, and truncating tail would fight the
        // caret once typing runs past the visible width.
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        searchField.placeholderAttributedString = NSAttributedString(
            string: "Type to filter…",
            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        )
        searchField.delegate = self
        searchField.setAccessibilityLabel("Filter clipboard history")
        searchField.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureHeader() {
        headerLabel.font = .systemFont(ofSize: Metrics.headerFontSize, weight: .medium)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.maximumNumberOfLines = 1
        headerLabel.cell?.lineBreakMode = .byTruncatingTail
        // Truncation is a drawing rule; it does nothing about the width the
        // label *asks* for. Dropping compression resistance below the width
        // pin above is what makes the label give way and actually truncate,
        // rather than widening everything around it.
        headerLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        headerLabel.isHidden = true
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureTable() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ClipboardColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.rowHeight = Metrics.rowHeight
        tableView.rowSizeStyle = .custom
        tableView.intercellSpacing = .zero
        tableView.gridStyleMask = []
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        // Transparent so the glass carries the background.
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.doubleAction = #selector(rowDoubleClicked)
        // Arrow keys and Return are read by the search field, which keeps
        // first responder for the whole life of the panel.
        tableView.refusesFirstResponder = true

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        // The clip view paints its own background too, and that one would
        // sit between the rows and the glass.
        scrollView.contentView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Row content

    private func symbolName(for item: ClipboardItem) -> String {
        switch item.kind {
        case .image:
            return "photo"
        case .text:
            // Rich text earns a different glyph because it behaves
            // differently: Return on it opens the formatting chooser.
            return item.hasRichFlavors ? "textformat" : "text.alignleft"
        }
    }

    /// Decodes at thumbnail size on demand and caches the small result. The
}

// MARK: - Search field

extension ClipboardPanel: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        controller.setSearchQuery(searchField.stringValue)
        // The controller decides whether typing counts — it refuses in
        // chooser mode, which has nothing to filter. Reading the query
        // back keeps the field showing what the filter actually holds,
        // instead of stray keystrokes sitting there until the chooser
        // closes.
        if searchField.stringValue != controller.searchQuery {
            searchField.stringValue = controller.searchQuery
        }
    }

    /// The four keys the panel steers with. Everything else falls through
    /// to the field editor and edits the filter.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            controller.moveSelectionUp()
        case #selector(NSResponder.moveDown(_:)):
            controller.moveSelectionDown()
        case #selector(NSResponder.insertNewline(_:)):
            controller.enterPressed()
        case #selector(NSResponder.cancelOperation(_:)):
            controller.escPressed()
        default:
            return false
        }
        return true
    }
}

// MARK: - Table

extension ClipboardPanel: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        switch controller.mode {
        case .chooser:
            return Self.chooserRows.count
        case .list:
            // An empty list still draws one row: the "nothing copied yet"
            // message.
            return max(controller.visibleItems.count, 1)
        }
    }
}

extension ClipboardPanel: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        if let reused = tableView.makeView(withIdentifier: Self.rowIdentifier, owner: self) as? ClipboardHistoryRowView {
            return reused
        }
        let rowView = ClipboardHistoryRowView()
        rowView.identifier = Self.rowIdentifier
        return rowView
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        rowsAreSelectable
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? ClipboardHistoryCellView)
            ?? ClipboardHistoryCellView(identifier: Self.cellIdentifier)

        if case .chooser = controller.mode {
            let option = Self.chooserRows[row]
            cell.configure(symbolName: option.symbol, text: option.title, thumbnail: nil, isMessage: false)
        } else if row < controller.visibleItems.count {
            let item = controller.visibleItems[row]
            cell.configure(
                symbolName: symbolName(for: item),
                text: item.previewLabel,
                thumbnail: thumbnails.thumbnail(for: item),
                isMessage: false
            )
        } else {
            // The icon slot is left empty rather than removed, so the
            // message starts on the same line as every real row's label.
            cell.configure(symbolName: nil, text: Self.emptyStateText, thumbnail: nil, isMessage: true)
        }
        return cell
    }
}
