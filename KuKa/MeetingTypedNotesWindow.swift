import AppKit

@MainActor
final class MeetingTypedNotesWindowController: NSWindowController, NSWindowDelegate, NSTextStorageDelegate {
    private let session: MeetingTypedNotesSession
    private let requestUpdate: () -> Void
    private let activation: OrdinaryWindowActivation
    private let present: @MainActor (NSWindow) -> Void
    private let confirmReload: @MainActor (NSWindow) -> Bool
    private let textView = NSTextView()
    private let editingUndo = UndoManager()
    private let saveLabel = NSTextField.makeWrappingLabel(size: 12, color: .secondaryLabelColor)
    private let summaryLabel = NSTextField.makeWrappingLabel(size: 12, color: .secondaryLabelColor)
    private lazy var retryButton = NSButton(title: "Retry save", target: self, action: #selector(retrySave))
    private lazy var reloadButton = NSButton(title: "Reload saved notes", target: self, action: #selector(reloadSaved))
    private lazy var updateButton = NSButton(title: "Update summary", target: self, action: #selector(updateSummary))
    var onClose: (() -> Void)?

    init(session: MeetingTypedNotesSession, requestUpdate: @escaping () -> Void,
         activation: OrdinaryWindowActivation = .shared,
         present: @escaping @MainActor (NSWindow) -> Void = { $0.makeKeyAndOrderFront(nil) },
         confirmReload: @escaping @MainActor (NSWindow) -> Bool = MeetingTypedNotesWindowController.confirmReload) {
        self.session = session
        self.requestUpdate = requestUpdate
        self.activation = activation
        self.present = present
        self.confirmReload = confirmReload
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        window.title = session.meeting.title
        window.contentMinSize = NSSize(width: 460, height: 330)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
        buildContent(in: window)
        session.onChange = { [weak self] in self?.render() }
        render()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        guard let window else { return }
        render()
        activation.open(window)
        present(window)
        window.makeFirstResponder(textView)
    }

    func windowWillClose(_ notification: Notification) {
        if let window { activation.close(window) }
        onClose?()
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        if editedMask.contains(.editedCharacters) { session.edit(textStorage.string) }
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { editingUndo }

    @objc private func retrySave() { session.save() }

    @objc private func reloadSaved() {
        guard let window, confirmReload(window) else { return }
        session.reloadSavedNotes()
    }

    @objc private func updateSummary() {
        guard session.canUpdateSummary else { return }
        requestUpdate()
    }

    private func render() {
        if textView.string != session.text {
            textView.textStorage?.delegate = nil
            textView.string = session.text
            textView.textStorage?.delegate = self
            textView.undoManager?.removeAllActions()
        }
        let saveText = session.saveError.map { "Not saved. " + $0 } ?? "Saved to notes.md"
        if saveLabel.stringValue != saveText {
            saveLabel.stringValue = saveText
            NSAccessibility.post(element: saveLabel, notification: .valueChanged)
        }
        saveLabel.textColor = session.saveError == nil ? .secondaryLabelColor : .systemRed
        if summaryLabel.stringValue != session.summaryMessage {
            summaryLabel.stringValue = session.summaryMessage
            NSAccessibility.post(element: summaryLabel, notification: .valueChanged)
        }
        retryButton.isHidden = session.saveError == nil
        reloadButton.isHidden = session.saveError == nil
        updateButton.isEnabled = session.canUpdateSummary
        window?.isDocumentEdited = session.hasUnsavedChanges
    }

    private func buildContent(in window: NSWindow) {
        let heading = NSTextField.makeLabel(size: 22, weight: .bold)
        heading.stringValue = "Meeting notes"
        let explanation = NSTextField.makeWrappingLabel(size: 13, color: .secondaryLabelColor)
        explanation.stringValue = "Write decisions, action items, or details you want in the summary."
        for label in [explanation, saveLabel, summaryLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude)
        textView.textStorage?.delegate = self
        textView.setAccessibilityLabel("Meeting notes")
        textView.setAccessibilityHelp("Plain text or Markdown. Changes save automatically to this meeting.")

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = textView
        scroll.drawsBackground = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [retryButton, reloadButton, spacer, updateButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.detachesHiddenViews = true
        for button in [retryButton, reloadButton, updateButton] { button.bezelStyle = .rounded }
        updateButton.toolTip = "Make summary.md again from the saved transcript and your saved notes."
        let stack = NSStackView(views: [heading, explanation, scroll, saveLabel, summaryLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        window.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
            saveLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            summaryLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        window.initialFirstResponder = textView
        textView.nextKeyView = retryButton
        retryButton.nextKeyView = reloadButton
        reloadButton.nextKeyView = updateButton
        updateButton.nextKeyView = textView
    }

    private static func confirmReload(_ window: NSWindow) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Replace your draft with the saved notes?"
        alert.informativeText = "Copy any text you want to keep first. This discards the unsaved draft in this window."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Reload saved notes")
        return alert.runModal() == .alertSecondButtonReturn
    }
}
