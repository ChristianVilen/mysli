import Cocoa
import UniformTypeIdentifiers

@MainActor
final class LogWindowController: NSWindowController, NSWindowDelegate {
    let range = NSPopUpButton()
    let category = NSPopUpButton()
    let level = NSPopUpButton()
    let copyAll = NSButton(title: "Copy All", target: nil, action: nil)
    let save = NSButton(title: "Save…", target: nil, action: nil)
    let deleteAll = NSButton(title: "Delete All Logs", target: nil, action: nil)
    let status = NSTextField(labelWithString: "")
    let scrollView = NSScrollView()
    let textView = NSTextView()
    private(set) var operationTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var stopRepeating: (() -> Void)?
    private var generation = UUID()
    private var isOpen = false
    private var isDeleting = false
    private var followNextRefresh = true
    private var displayed = LogText([])
    private var actionError: String?
    private let reader: any LogReading
    private let launchDate: Date
    private let processID: Int32
    private let now: () -> Date
    private let calendar: Calendar
    private let activation: OrdinaryWindowActivation
    private let present: (NSWindow) -> Void
    private let copyText: (String) -> Void
    private let saveText: (NSWindow, String) -> Void
    private let confirmDelete: (NSWindow) async -> Bool
    private let deleteLogs: () async throws -> Void
    private let repeatRefresh: (@escaping @MainActor () -> Void) -> () -> Void
    private let rowLimit: Int

    init(reader: any LogReading, launchDate: Date, processID: Int32 = ProcessInfo.processInfo.processIdentifier,
         now: @escaping () -> Date = Date.init, calendar: Calendar = .current,
         activation: OrdinaryWindowActivation = .shared,
         present: @escaping (NSWindow) -> Void = { $0.makeKeyAndOrderFront(nil) },
         copy: @escaping (String) -> Void = { NSPasteboard.general.clearContents(); NSPasteboard.general.setString($0, forType: .string) },
         save: @escaping (NSWindow, String) -> Void = { LogWindowController.save($1, in: $0) },
         confirmDelete: @escaping (NSWindow) async -> Bool = { await LogWindowController.confirmDeletion(in: $0) },
         deleteLogs: @escaping () async throws -> Void,
         repeatRefresh: @escaping (@escaping @MainActor () -> Void) -> () -> Void = LogWindowController.everyTwoSeconds,
         rowLimit: Int = LogFilter.defaultRowLimit) {
        self.reader = reader
        // File timestamps have millisecond precision, including the first line after launch.
        self.launchDate = Date(timeIntervalSince1970: floor(launchDate.timeIntervalSince1970 * 1000) / 1000)
        self.processID = processID
        self.now = now
        self.calendar = calendar
        self.activation = activation
        self.present = present
        self.copyText = copy
        self.saveText = save
        self.confirmDelete = confirmDelete
        self.deleteLogs = deleteLogs
        self.repeatRefresh = repeatRefresh
        self.rowLimit = rowLimit
        let window = LogWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Ku-Ka Log"
        window.minSize = NSSize(width: 780, height: 360)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.onFind = { [weak self] in self?.showFind() }
        buildContent(in: window)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        guard let window else { return }
        if !isOpen {
            isOpen = true
            actionError = nil
            stopRepeating = repeatRefresh { [weak self] in
                guard let self, self.refreshTask == nil else { return }
                self.refresh()
            }
        }
        activation.open(window)
        present(window)
        window.makeFirstResponder(textView)
        refresh()
    }

    override func close() { stopRefreshing(); super.close() }
    func windowWillClose(_ notification: Notification) { stopRefreshing() }
    func windowDidResize(_ notification: Notification) { layoutText() }

    private func stopRefreshing() {
        guard isOpen else { return }
        isOpen = false
        generation = UUID()
        stopRepeating?()
        stopRepeating = nil
        refreshTask?.cancel()
        refreshTask = nil
        if let window { activation.close(window) }
    }

    @discardableResult
    func refresh() -> Task<Void, Never>? {
        guard isOpen, !isDeleting else { return nil }
        refreshTask?.cancel()
        let token = UUID()
        generation = token
        let filter = LogFilter(range: LogRange.allCases[range.indexOfSelectedItem],
                               category: category.indexOfSelectedItem == 0 ? nil : category.titleOfSelectedItem,
                               errorsOnly: level.indexOfSelectedItem == 1, rowLimit: rowLimit)
        let date = now()
        let launch = launchDate
        let pid = processID
        let calendar = calendar
        if textView.string.isEmpty { status.stringValue = "Loading logs…" }
        let task = Task { [weak self, reader] in
            do {
                let visible = try await reader.filteredRows(using: filter, now: date, launchDate: launch,
                                                             processID: pid, calendar: calendar)
                guard let self, isOpen, generation == token, !Task.isCancelled else { return }
                display(visible)
                status.stringValue = actionError ?? (visible.isEmpty ? "No logs match these filters." : "\(visible.count) \(visible.count == 1 ? "line" : "lines")")
                refreshTask = nil
            } catch {
                guard let self, isOpen, generation == token, !Task.isCancelled else { return }
                status.stringValue = "Could not read logs. Retrying…"
                refreshTask = nil
            }
        }
        refreshTask = task
        return task
    }

    @objc private func filterChanged(_ sender: Any?) {
        actionError = nil
        followNextRefresh = true
        refresh()
    }

    private func display(_ rows: [LogRow]) {
        let next = LogText(rows)
        let text = next.text
        copyAll.isEnabled = !text.isEmpty
        save.isEnabled = !text.isEmpty
        guard text != displayed.text || next.ids != displayed.ids else { followNextRefresh = false; return }
        let follow = followNextRefresh || scrollView.documentVisibleRect.maxY >= textView.bounds.maxY - 2
        let origin = scrollView.contentView.bounds.origin
        let selection = textView.selectedRange()
        let layout = textView.layoutManager!
        let point = NSPoint(x: 0, y: max(0, origin.y - textView.textContainerInset.height))
        let glyph = layout.glyphIndex(for: point, in: textView.textContainer!)
        let character = layout.characterIndexForGlyph(at: glyph)
        let oldY = lineY(at: character)
        let anchor = next.position(character, from: displayed)
        let start = next.position(selection.location, from: displayed) ?? 0
        let end = next.position(NSMaxRange(selection), from: displayed) ?? start
        textView.string = text
        layoutText()
        textView.setSelectedRange(NSRange(location: start, length: max(0, end - start)))
        let anchoredY = anchor.map { origin.y + lineY(at: $0) - oldY } ?? 0
        let target = NSPoint(x: origin.x, y: follow ? max(0, textView.bounds.height - scrollView.contentView.bounds.height) : max(0, anchoredY))
        scrollView.contentView.scroll(to: target)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        followNextRefresh = false
        displayed = next
    }

    private func lineY(at character: Int) -> CGFloat {
        guard character < (textView.string as NSString).length, let layout = textView.layoutManager else { return 0 }
        return layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: character), effectiveRange: nil).minY
    }

    private func layoutText() {
        window?.contentView?.layoutSubtreeIfNeeded()
        guard let container = textView.textContainer, let layout = textView.layoutManager else { return }
        layout.ensureLayout(for: container)
        let size = layout.usedRect(for: container).size
        textView.setFrameSize(NSSize(width: max(scrollView.contentSize.width, size.width + 20),
                                    height: max(scrollView.contentSize.height, size.height + 20)))
    }

    @objc private func copyDisplayed(_ sender: Any?) { copyText(textView.string) }
    @objc private func saveDisplayed(_ sender: Any?) { if let window { saveText(window, textView.string) } }

    @objc private func deleteDisplayed(_ sender: Any?) {
        guard operationTask == nil, let window else { return }
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { operationTask = nil }
            guard await confirmDelete(window), isOpen else { return }
            isDeleting = true
            deleteAll.isEnabled = false
            actionError = nil
            generation = UUID()
            refreshTask?.cancel()
            refreshTask = nil
            do { try await deleteLogs() }
            catch { actionError = "Could not delete logs. Try again." }
            isDeleting = false
            deleteAll.isEnabled = true
            if isOpen { await refresh()?.value }
        }
    }

    private func showFind() {
        window?.makeFirstResponder(textView)
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        textView.performFindPanelAction(item)
    }

    nonisolated private static func everyTwoSeconds(_ tick: @escaping @MainActor () -> Void) -> () -> Void {
        let timer = Timer(timeInterval: 2, repeats: true) { _ in MainActor.assumeIsolated { tick() } }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }

    static func deletionAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Delete all Ku-Ka logs?"
        alert.informativeText = "This can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        return alert
    }

    private static func confirmDeletion(in window: NSWindow) async -> Bool {
        await withCheckedContinuation { continuation in
            deletionAlert().beginSheetModal(for: window) { continuation.resume(returning: $0 == .alertFirstButtonReturn) }
        }
    }

    private static func save(_ text: String, in window: NSWindow) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Ku-Ka.log.txt"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do { try text.write(to: url, atomically: true, encoding: .utf8) }
            catch { NSAlert(error: error).beginSheetModal(for: window) }
        }
    }

    private func buildContent(in window: NSWindow) {
        range.addItems(withTitles: ["This launch", "Today", "Last 7 days", "Everything kept"])
        category.addItems(withTitles: ["All"] + Log.categories)
        level.addItems(withTitles: ["All", "Errors only"])
        let filters = NSStackView()
        filters.spacing = 10
        for (title, control) in [("Range", range), ("Category", category), ("Level", level)] {
            control.target = self
            control.action = #selector(filterChanged(_:))
            control.setAccessibilityLabel(title)
            filters.addArrangedSubview(NSTextField(labelWithString: title))
            filters.addArrangedSubview(control)
        }
        range.widthAnchor.constraint(equalToConstant: 160).isActive = true
        category.widthAnchor.constraint(equalToConstant: 140).isActive = true
        level.widthAnchor.constraint(equalToConstant: 120).isActive = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.setAccessibilityLabel("Log messages")
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.findBarPosition = .aboveContent
        let footer = NSStackView()
        footer.spacing = 10
        status.textColor = .secondaryLabelColor
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(status)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(spacer)
        for (button, action) in [(copyAll, #selector(copyDisplayed(_:))), (save, #selector(saveDisplayed(_:))), (deleteAll, #selector(deleteDisplayed(_:)))] {
            button.bezelStyle = .rounded
            button.target = self
            button.action = action
            footer.addArrangedSubview(button)
        }
        copyAll.isEnabled = false
        save.isEnabled = false
        guard let content = window.contentView else { return }
        for view in [filters, scrollView, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            filters.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            filters.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            filters.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: filters.bottomAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14)
        ])
    }
}

@MainActor
private final class LogWindow: NSWindow {
    var onFind: (() -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            onFind?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
