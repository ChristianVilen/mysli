import AppKit

enum WordReviewCopy {
    static let windowTitle = "Check Words"
    static let rightWordLabel = "Right word:"
    static let skip = "Skip"
    static let correctAsHeard = "It Is Correct as Heard"
    static let save = "Save"
    static let openSummary = "Open Summary"
    static let updateNotes = "Update Notes"
    static let nextMeeting = "Next Meeting"
    static let close = "Close"
    static let updateExplanation =
        "Update Notes makes the transcript and the summary again with your answers. It replaces changes that you made to the transcript by hand."
    static let updating = "Ku-Ka is updating the notes. You get a notification when they are ready."

    static func position(_ number: Int, of count: Int) -> String {
        "Word \(number) of \(count)"
    }

    static func reason(_ reason: String) -> String {
        "Why Ku-Ka asks: \(reason)"
    }

    /// The field's VoiceOver label. It names the word, because VoiceOver does not say which part
    /// of the quote is bold.
    static func rightWordField(_ heard: String) -> String {
        "Right word for “\(heard)”"
    }

    static func ordinaryNote(_ heard: String) -> String {
        "“\(heard)” is also ordinary words. Ku-Ka will not replace it in every transcript. The summary tool will check it by context."
    }

    static func finished(_ meetingTitle: String) -> String {
        "All words checked for \(meetingTitle)."
    }
}

@MainActor
final class WordReviewWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private static let contentWidth: CGFloat = 480
    private static let contentPadding: CGFloat = 20

    private let controller: WordReviewController
    private let activation: OrdinaryWindowActivation

    private let meetingLabel = NSTextField(labelWithString: "")
    private let positionLabel = NSTextField(labelWithString: "")
    private let placeLabel = NSTextField.makeWrappingLabel(size: 13, color: .secondaryLabelColor)
    private let quoteLabel = NSTextField.makeWrappingLabel(size: 13)
    private let reasonLabel = NSTextField.makeWrappingLabel(size: 13, color: .secondaryLabelColor)
    private let field = NSTextField()
    private let ordinaryNoteLabel = NSTextField.makeWrappingLabel(size: 13, color: .secondaryLabelColor)
    private let questionErrorLabel = NSTextField.makeWrappingLabel(size: 13, color: .systemRed)
    private lazy var skipButton = makeButton(WordReviewCopy.skip, #selector(skipClicked))
    private lazy var correctAsHeardButton = makeButton(WordReviewCopy.correctAsHeard, #selector(correctAsHeardClicked))
    private lazy var saveButton = makeButton(WordReviewCopy.save, #selector(saveClicked))
    private lazy var questionPage = makeQuestionPage()

    private let finishedLabel = NSTextField.makeWrappingLabel(size: 13, weight: .bold)
    private let explanationLabel = NSTextField.makeWrappingLabel(size: 13, color: .secondaryLabelColor)
    private let finishedErrorLabel = NSTextField.makeWrappingLabel(size: 13, color: .systemRed)
    private lazy var openSummaryButton = makeButton(WordReviewCopy.openSummary, #selector(openSummaryClicked))
    private lazy var updateNotesButton = makeButton(WordReviewCopy.updateNotes, #selector(updateNotesClicked))
    private lazy var nextMeetingButton = makeButton(WordReviewCopy.nextMeeting, #selector(nextMeetingClicked))
    private lazy var closeButton = makeButton(WordReviewCopy.close, #selector(closeClicked))
    private lazy var finishedPage = makeFinishedPage()

    /// The question that last filled the field, so that a new error keeps what the user typed.
    private var questionInField: WordReviewScreen.QuestionPage?
    /// While the window closes, the nil screen that `controller.close()` reports must not close it again.
    private var isClosing = false

    init(controller: WordReviewController, activation: OrdinaryWindowActivation = .shared) {
        self.controller = controller
        self.activation = activation

        let window = ReviewWindow(contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 300),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.title = WordReviewCopy.windowTitle

        super.init(window: window)
        window.delegate = self
        field.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Claims `controller.onChange`. The owner calls this once, at launch.
    func bindController() {
        controller.onChange = { [weak self] in self?.render() }
    }

    /// Opens the review of `meeting`, or of the oldest meeting with open questions for nil. An open
    /// window also comes to the front when its page stays the same, which `onChange` does not report.
    func show(_ meeting: MeetingFolder?) {
        controller.show(meeting)
        if controller.screen != nil { present() }
    }

    func render() {
        guard let screen = controller.screen else {
            if !isClosing, window?.isVisible == true { close() }
            return
        }
        switch screen.page {
        case .question(let page): fill(page, error: screen.error)
        case .finished(let page): fill(page, error: screen.error)
        }
        if window?.isVisible != true { present() }
    }

    func windowWillClose(_ notification: Notification) {
        isClosing = true
        controller.close()
        isClosing = false
        questionInField = nil
        if let window { activation.close(window) }
    }

    private func fill(_ page: WordReviewScreen.QuestionPage, error: String?) {
        install(questionPage)
        meetingLabel.stringValue = page.meetingTitle
        positionLabel.stringValue = WordReviewCopy.position(page.number, of: page.count)
        placeLabel.show(page.place)
        quoteLabel.attributedStringValue = Self.attributedQuote(page.quote)
        reasonLabel.show(page.reason.map(WordReviewCopy.reason))
        ordinaryNoteLabel.show(page.isOrdinary ? WordReviewCopy.ordinaryNote(page.heard) : nil)
        questionErrorLabel.show(error)
        field.setAccessibilityLabel(WordReviewCopy.rightWordField(page.heard))
        if page != questionInField {
            questionInField = page
            field.abortEditing()
            field.stringValue = page.suggestion
            window?.makeFirstResponder(field)
        }
        updateSaveButton()
        fitWindow()
    }

    private func fill(_ page: WordReviewScreen.FinishedPage, error: String?) {
        install(finishedPage)
        questionInField = nil
        finishedLabel.stringValue = WordReviewCopy.finished(page.meetingTitle)
        let explanation = page.isUpdating ? WordReviewCopy.updating
            : page.canUpdateNotes ? WordReviewCopy.updateExplanation : nil
        explanationLabel.show(explanation)
        finishedErrorLabel.show(error)
        updateNotesButton.isHidden = !page.canUpdateNotes
        nextMeetingButton.isHidden = page.otherMeetings == 0
        fitWindow()
    }

    private func makeQuestionPage() -> NSView {
        meetingLabel.font = .boldSystemFont(ofSize: 13)
        meetingLabel.lineBreakMode = .byTruncatingTail
        meetingLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        meetingLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        positionLabel.font = .systemFont(ofSize: 12)
        positionLabel.textColor = .secondaryLabelColor
        positionLabel.setContentHuggingPriority(.required, for: .horizontal)
        positionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let rightWordLabel = NSTextField(labelWithString: WordReviewCopy.rightWordLabel)
        rightWordLabel.setContentHuggingPriority(.required, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        saveButton.keyEquivalent = "\r"

        return makePage([
            Self.row([meetingLabel, positionLabel]), placeLabel, quoteLabel, reasonLabel,
            Self.row([rightWordLabel, field]), ordinaryNoteLabel,
            Self.row([skipButton, correctAsHeardButton, Self.spacer(), saveButton]), questionErrorLabel,
        ])
    }

    private func makeFinishedPage() -> NSView {
        makePage([
            finishedLabel, explanationLabel,
            Self.row([openSummaryButton, updateNotesButton, nextMeetingButton, Self.spacer(), closeButton]),
            finishedErrorLabel,
        ])
    }

    /// A fixed-width page whose rows span the width, so wrapped labels give the page its height.
    private func makePage(_ rows: [NSView]) -> NSView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: Self.contentPadding, left: Self.contentPadding,
                                        bottom: Self.contentPadding, right: Self.contentPadding)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let page = NSView()
        page.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: page.topAnchor),
            stack.bottomAnchor.constraint(equalTo: page.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            page.widthAnchor.constraint(equalToConstant: Self.contentWidth),
        ] + rows.map { $0.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * Self.contentPadding) })
        return page
    }

    private func install(_ page: NSView) {
        guard let window, window.contentView !== page else { return }
        window.contentView = page
    }

    /// Sizes the window to its page and keeps its top edge where it was.
    private func fitWindow() {
        guard let window, let page = window.contentView else { return }
        page.layoutSubtreeIfNeeded()
        let size = window.frameRect(forContentRect: NSRect(origin: .zero, size: page.fittingSize)).size
        window.setFrame(NSRect(x: window.frame.minX, y: window.frame.maxY - size.height,
                               width: size.width, height: size.height), display: true)
    }

    private func present() {
        guard let window else { return }
        if !window.isVisible { window.center() }
        activation.open(window)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func saveClicked() {
        controller.save(rightWord: field.stringValue)
    }

    @objc private func skipClicked() {
        controller.skip()
    }

    @objc private func correctAsHeardClicked() {
        controller.keepAsHeard()
    }

    @objc private func openSummaryClicked() {
        controller.openSummary()
    }

    @objc private func updateNotesClicked() {
        controller.updateNotes()
    }

    @objc private func nextMeetingClicked() {
        controller.showNextMeeting()
    }

    @objc private func closeClicked() {
        close()
    }

    func controlTextDidChange(_ notification: Notification) {
        updateSaveButton()
    }

    /// Return saves and Esc closes while the field has the keyboard. Without this, the field
    /// editor would show word completions on Esc.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            if saveButton.isEnabled { saveClicked() }
        case #selector(NSResponder.cancelOperation(_:)):
            close()
        default:
            return false
        }
        return true
    }

    private func updateSaveButton() {
        saveButton.isEnabled = !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func makeButton(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.setAccessibilityLabel(title)
        return button
    }

    private static func row(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.distribution = .fill
        row.spacing = 8
        return row
    }

    private static func spacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        return spacer
    }

    /// The quote in quotation marks with the heard form in bold. The plain text is the same, so
    /// VoiceOver reads the whole sentence.
    private static func attributedQuote(_ quote: WordReviewScreen.HighlightedQuote) -> NSAttributedString {
        let regular: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
        var bold = regular
        bold[.font] = NSFont.boldSystemFont(ofSize: 13)
        let text = NSMutableAttributedString(string: "“" + quote.before, attributes: regular)
        text.append(NSAttributedString(string: quote.match, attributes: bold))
        text.append(NSAttributedString(string: quote.after + "”", attributes: regular))
        return text
    }
}

/// Esc closes the window also on the finished page, where no field handles it.
private final class ReviewWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
