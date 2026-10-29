import Cocoa

/// Renders controller state and forwards input to `ClipboardHistoryController`.
///
/// Takes key status without activating Ku-Ka. The previous app must stay frontmost for
/// the synthetic Cmd+V after a paste. Never call `NSApp.activate` here.
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

    private let controller: ClipboardHistoryController
    private let screens: Screens

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

    init(controller: ClipboardHistoryController, screens: Screens = SystemScreens()) {
        self.controller = controller
        self.screens = screens
        super.init(contentRect: NSRect(origin: .zero, size: Metrics.size))

        // Ku-Ka never activates; the NSPanel default would hide it as soon as it appears.
        hidesOnDeactivate = false
        // A clipboard panel is reached by a global hotkey, so it has to
        // follow the user across spaces and over full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        buildChrome()
    }

    /// Claims both controller callbacks. The owner calls this once after construction,
    /// so other listeners can see the slots are taken and avoid overwriting them.
    func bindController() {
        controller.onListChanged = { [weak self] in self?.reload() }
        controller.onPanelShouldClose = { [weak self] in self?.dismiss() }
    }

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

        // Restarting the fade on a visible panel would make it blink while being read.
        if !isVisible {
            setAlphaImmediately(shouldFade ? 0 : 1)
        }

        // Not `NSApp.activate`: the app the user was in must stay frontmost.
        makeKeyAndOrderFront(nil)
        makeFirstResponder(searchField)

        guard shouldFade, alphaValue < 1 else { return }
        fadeIn(duration: Metrics.fadeDuration, timingFunction: CAMediaTimingFunction(name: .easeOut))
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

    /// Horizontally centered on the screen under the pointer, with the top
    /// edge a quarter of the way down that screen's visible height.
    private func targetOrigin(mouseLocation: CGPoint) -> NSPoint? {
        let layout = screens.all
        guard let screen = ScreenGeometry.under(mouseLocation, in: layout) ?? layout.first else { return nil }

        let visible = screen.visibleFrame
        let x = visible.midX - Metrics.size.width / 2
        let topEdge = visible.maxY - visible.height * Metrics.topFraction
        // On a display shorter than the panel, the top clamp wins to keep search in view.
        var y = max(topEdge - Metrics.size.height, visible.minY)
        y = min(y, visible.maxY - Metrics.size.height)
        return NSPoint(x: x.rounded(), y: y.rounded())
    }

    func reload() {
        if case .chooser(let item) = controller.mode {
            headerLabel.show(Self.headerText(for: item))
            scrollTopConstraint.constant = Metrics.chooserTopGap
        } else {
            headerLabel.show(nil)
            scrollTopConstraint.constant = Metrics.listTopGap
        }

        tableView.reloadData()
        syncSelection()
    }

    /// Caps the chooser header even on displays wide enough to show the whole preview.
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

    private func buildChrome() {
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
        // Regular glass keeps text legible over the wallpaper.
        glass.style = .regular
        glass.cornerRadius = Metrics.cornerRadius
        glass.contentView = container
        contentView = glass

        // A borderless window takes its minimum size from the content's fitting size.
        // Explicit width/height prevent long labels from stretching it beyond the screen.
        // Leave trailing/bottom unpinned so the glass cannot determine that size again.
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
        // Compression resistance below the width constraint lets long labels truncate.
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

}

extension ClipboardPanel: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        controller.setSearchQuery(searchField.stringValue)
        // Read back the accepted query because the controller refuses typing in chooser mode.
        if searchField.stringValue != controller.searchQuery {
            searchField.stringValue = controller.searchQuery
        }
    }

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

extension ClipboardPanel: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        switch controller.mode {
        case .chooser:
            return Self.chooserRows.count
        case .list:
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
