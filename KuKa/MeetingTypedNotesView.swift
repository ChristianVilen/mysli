import AppKit
import Carbon.HIToolbox

@MainActor
final class MeetingTypedNotesView: NSView {
    let session: MeetingTypedNotesSession
    private let requestUpdate: () -> Void
    private let confirmReload: @MainActor (NSWindow) -> Bool
    private let stack = NSStackView()
    private let scroll = NSScrollView()
    private let saveLabel = NSTextField.makeWrappingLabel(size: 12, color: .secondaryLabelColor)
    private let summaryLabel = NSTextField.makeWrappingLabel(size: 12, color: .secondaryLabelColor)
    private lazy var retry = NSButton(title: "Retry save", target: self, action: #selector(retrySave))
    private lazy var reload = NSButton(title: "Reload saved notes", target: self, action: #selector(reloadSaved))
    private lazy var update = NSButton(title: "Update summary", target: self, action: #selector(updateSummary))
    /// Keeps a row that leaves the session: text undo actions point at its editor, so undo can
    /// bring it back. Only a reload, which clears undo, removes rows.
    private var rows: [UUID: MeetingNoteRowView] = [:]
    private let thumbnails: MeetingScreenshotThumbnails
    private var focusedEntry: UUID?

    init(session: MeetingTypedNotesSession, requestUpdate: @escaping () -> Void,
         confirmReload: @escaping @MainActor (NSWindow) -> Bool = MeetingTypedNotesView.confirmReload) {
        self.session = session
        self.requestUpdate = requestUpdate
        self.confirmReload = confirmReload
        thumbnails = MeetingScreenshotThumbnails(store: MeetingScreenshotStore(meeting: session.meeting))
        super.init(frame: NSRect(x: 0, y: 0, width: 460, height: 330))
        registerForDraggedTypes([.png, .tiff, .fileURL])
        wantsLayer = true
        layer?.masksToBounds = true
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        let document = NotesDocumentView()
        document.onDrop = { [weak self] in self?.dropImage(from: $0) ?? false }
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -12)
        ])
        scroll.documentView = document
        scroll.frame = NSRect(x: 0, y: 0, width: 444, height: 220)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let buttons = NSStackView(views: [retry, reload, update])
        buttons.spacing = 8
        buttons.detachesHiddenViews = true
        let title = NSTextField.makeLabel(size: 13, weight: .semibold)
        title.stringValue = session.meeting.title
        title.toolTip = session.meeting.title
        let outer = NSStackView(views: [title, scroll, saveLabel, summaryLabel, buttons])
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 6
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            outer.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            scroll.widthAnchor.constraint(equalTo: outer.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
            saveLabel.widthAnchor.constraint(equalTo: outer.widthAnchor),
            summaryLabel.widthAnchor.constraint(equalTo: outer.widthAnchor)
        ])
        // `onChange` has one subscriber, so a second view of a session would take it from this
        // one. `MeetingNotesHosting` keeps one view per meeting and moves it.
        session.onChange = { [weak self] in self?.render() }
        render()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        NoteRowTextView.acceptsImage(from: sender.draggingPasteboard) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropImage(from: sender.draggingPasteboard)
    }

    @discardableResult
    func dropImage(from board: NSPasteboard) -> Bool {
        let focused = window?.firstResponder as? NoteRowTextView
        let last = session.entries.last.flatMap { rows[$0.id]?.editor }
        return (focused ?? last)?.dropImage(from: board) ?? false
    }

    override func draw(_ dirtyRect: NSRect) {
        MeetingControlsPanel.Colors.drawer.setFill()
        dirtyRect.fill()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let editor = window?.firstResponder as? NoteRowTextView, rows[editor.entryID]?.editor === editor {
            focusedEntry = editor.entryID
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func focus() {
        let editor = focusedEntry.flatMap { rows[$0]?.editor } ?? session.entries.first.flatMap { rows[$0.id]?.editor }
        if let editor { window?.makeFirstResponder(editor) }
    }

    private func render() {
        let ids = Set(session.entries.map(\.id))
        for view in stack.arrangedSubviews {
            guard let row = view as? MeetingNoteRowView, !ids.contains(row.editor.entryID) else { continue }
            stack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        for (index, entry) in session.entries.enumerated() {
            let row: MeetingNoteRowView
            if let existing = rows[entry.id] { row = existing }
            else {
                row = MeetingNoteRowView(editor: makeEditor(entry), thumbnails: thumbnails)
                rows[entry.id] = row
            }
            if index >= stack.arrangedSubviews.count || stack.arrangedSubviews[index] !== row {
                stack.insertArrangedSubview(row, at: index)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            row.show(entry)
        }
        saveLabel.stringValue = session.saveError.map { "Not saved. " + $0 } ?? "Saved to notes.md"
        summaryLabel.stringValue = session.summaryMessage
        retry.isHidden = session.saveError == nil
        reload.isHidden = session.saveError == nil
        update.isEnabled = session.canUpdateSummary
    }

    private func makeEditor(_ entry: MeetingNoteEntry) -> NoteRowTextView {
        let editor = NoteRowTextView(entryID: entry.id)
        editor.editingUndo = session.undoManager
        editor.string = entry.text
        editor.onEdit = { [weak self, weak editor] in
            guard let self, let editor else { return }
            editor.invalidateIntrinsicContentSize()
            self.session.updateEntry(id: editor.entryID, text: editor.string)
        }
        editor.font = .systemFont(ofSize: 15)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.isVerticallyResizable = true
        editor.textContainer?.widthTracksTextView = true
        editor.onNewRow = { [weak self, weak editor] in
            guard let self, let editor else { return }
            editor.breakUndoCoalescing()
            guard let next = self.session.splitEntry(id: entry.id, selection: editor.selectedRange()) else { return }
            self.window?.makeFirstResponder(self.rows[next]?.editor)
        }
        editor.onImage = { [weak self] data in
            guard let self else { return }
            try self.session.addScreenshot(data, to: entry.id)
        }
        return editor
    }

    @objc private func retrySave() { session.save() }
    @objc private func reloadSaved() {
        guard let window, confirmReload(window) else { return }
        session.reloadSavedNotes()
        if session.saveError == nil {
            let ids = Set(session.entries.map(\.id))
            rows = rows.filter { ids.contains($0.key) }
        }
    }
    private static func confirmReload(_ window: NSWindow) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Replace your draft with the saved notes?"
        alert.informativeText = "Copy any text you want to keep first."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Reload saved notes")
        return alert.runModal() == .alertSecondButtonReturn
    }
    @objc private func updateSummary() { if session.canUpdateSummary { requestUpdate() } }
}

private final class MeetingNoteRowView: NSStackView {
    let editor: NoteRowTextView
    private let time = NSTextField.makeLabel(size: 11, color: .secondaryLabelColor)
    private let images = NSStackView()
    private let thumbnails: MeetingScreenshotThumbnails
    private var attachmentNames: [String] = []

    init(editor: NoteRowTextView, thumbnails: MeetingScreenshotThumbnails) {
        self.editor = editor
        self.thumbnails = thumbnails
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 8
        images.orientation = .vertical
        images.alignment = .leading
        images.spacing = 6
        images.isHidden = true
        for view in [time, editor, images] as [NSView] { addArrangedSubview(view) }
        NSLayoutConstraint.activate([
            editor.widthAnchor.constraint(equalTo: widthAnchor),
            editor.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            images.widthAnchor.constraint(equalTo: widthAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ entry: MeetingNoteEntry) {
        time.stringValue = entry.time.label
        if editor.string != entry.text { editor.replaceFromSession(entry.text) }
        guard attachmentNames != entry.attachments else { return }
        attachmentNames = entry.attachments
        for image in images.arrangedSubviews { images.removeArrangedSubview(image); image.removeFromSuperview() }
        for name in attachmentNames {
            guard let thumbnail = thumbnails.thumbnail(named: name) else { continue }
            let image = NSImageView(image: thumbnail)
            image.imageScaling = .scaleProportionallyDown
            image.setAccessibilityLabel("Screenshot")
            images.addArrangedSubview(image)
            image.widthAnchor.constraint(lessThanOrEqualTo: images.widthAnchor).isActive = true
            image.heightAnchor.constraint(equalToConstant: 140).isActive = true
        }
        images.isHidden = images.arrangedSubviews.isEmpty
    }
}

private final class NotesDocumentView: NSView {
    override var isFlipped: Bool { true }
    var onDrop: ((NSPasteboard) -> Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.png, .tiff, .fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        NoteRowTextView.acceptsImage(from: sender.draggingPasteboard) ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDrop?(sender.draggingPasteboard) ?? false
    }
}

final class NoteRowTextView: NSTextView, NSTextStorageDelegate {
    let entryID: UUID
    var onNewRow: (() -> Void)?
    var onImage: ((MeetingScreenshot) throws -> Void)?
    var onEdit: (() -> Void)?
    private var isReplacing = false
    var editingUndo: UndoManager?
    override var undoManager: UndoManager? { editingUndo }

    init(entryID: UUID) {
        self.entryID = entryID
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        textStorage?.delegate = self
        registerForDraggedTypes([.png, .tiff, .fileURL])
        setAccessibilityLabel("Meeting note")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        if !isReplacing && editedMask.contains(.editedCharacters) { onEdit?() }
    }

    func replaceFromSession(_ text: String) {
        isReplacing = true
        string = text
        isReplacing = false
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else { return NSSize(width: NSView.noIntrinsicMetric, height: 24) }
        layoutManager.ensureLayout(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(24, ceil(layoutManager.usedRect(for: textContainer).height + textContainerInset.height * 2)))
    }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Return && !event.modifierFlags.contains(.shift) { onNewRow?(); return }
        super.keyDown(with: event)
    }
    override func paste(_ sender: Any?) {
        if pasteImage(from: .general) { return }
        super.paste(sender)
    }
    @discardableResult
    func pasteImage(from pasteboard: NSPasteboard) -> Bool {
        guard let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) else { return false }
        do { try onImage?(MeetingScreenshot.decode(data)); return true } catch { NSSound.beep(); return true }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.acceptsImage(from: sender.draggingPasteboard) ? .copy : []
    }
    static func acceptsImage(from board: NSPasteboard) -> Bool {
        let types = board.types ?? []
        return types.contains(.png) || types.contains(.tiff) || types.contains(.fileURL)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropImage(from: sender.draggingPasteboard)
    }
    @discardableResult
    func dropImage(from board: NSPasteboard) -> Bool {
        if pasteImage(from: board) { return true }
        guard let url = NSURL(from: board) as URL?, url.isFileURL else { return false }
        do { try onImage?(MeetingScreenshot.read(from: url)); return true } catch { NSSound.beep(); return false }
    }
}
