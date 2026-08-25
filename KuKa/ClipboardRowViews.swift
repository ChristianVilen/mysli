import Cocoa

/// Every size and inset the clipboard panel draws with, in one place, so
/// the alignments between the search row and the list rows stay in step
/// when they are tuned by eye at first run. Lives here with the row views
/// rather than in `ClipboardPanel`, because these are the numbers a row
/// draws itself against — the panel reads the same table for its chrome.
enum Metrics {
    static let size = NSSize(width: 560, height: 400)
    /// Matches the macOS 26 rounding of a panel this wide.
    static let cornerRadius: CGFloat = 20
    /// Panel edge to the search glyph, and to a row's type icon.
    static let contentInset: CGFloat = 20
    static let iconSlot: CGFloat = 18
    static let iconGap: CGFloat = 10
    static let rowHeight: CGFloat = 34
    /// The table sits nearer the panel edge than the text does, so the
    /// selection highlight can reach past the label without touching the
    /// glass edge.
    static let tableInset: CGFloat = 12
    /// Inset of a row's content inside its cell. `tableInset` plus this
    /// equals `contentInset`, which is what puts a row's icon on the same
    /// vertical line as the search glyph.
    static let cellInset = contentInset - tableInset
    static let thumbnailBox = NSSize(width: 44, height: 24)
    static let searchFontSize: CGFloat = 18
    static let rowFontSize: CGFloat = 13
    static let headerFontSize: CGFloat = 11
    static let headerHeight: CGFloat = 16
    /// Panel top edge down to the search field.
    static let searchTopInset: CGFloat = 16
    /// Search field down to the separator.
    static let separatorGap: CGFloat = 14
    static let separatorHeight: CGFloat = 1
    /// Last row down to the panel's bottom edge.
    static let bottomInset: CGFloat = 10
    /// Gap under the separator in list mode.
    static let listTopGap: CGFloat = 10
    /// Chooser header line down to the first row.
    static let headerGap: CGFloat = 8
    /// Gap under the separator in chooser mode: the list gap, plus the
    /// header line and the space below it.
    static let chooserTopGap = listTopGap + headerHeight + headerGap
    /// Longest run of the copied text the chooser header shows. The header
    /// only has to say *which* item is about to be pasted, and a copied
    /// line can run to hundreds of characters — sometimes carrying things
    /// the user would rather not have spread across the screen, such as a
    /// password sitting in a copied note. A short prefix answers the
    /// question and stops there.
    static let headerPreviewMaxLength = 60
    static let selectionInset: CGFloat = 4
    static let selectionVerticalInset: CGFloat = 2
    static let selectionRadius: CGFloat = 8
    /// The panel's top edge sits this far down the screen's visible
    /// height — high enough to read at a glance, low enough not to crowd
    /// the menu bar.
    static let topFraction: CGFloat = 0.25
    static let fadeDuration: TimeInterval = 0.12
}

/// Draws the selection as an inset rounded bar rather than the full-width
/// system band: on glass a bar that runs edge to edge fights the panel's
/// own rounding.
final class ClipboardHistoryRowView: NSTableRowView {
    /// The glass is the background. Anything AppKit would paint here would
    /// only sit in front of it and mute it.
    override func drawBackground(in dirtyRect: NSRect) {}

    /// The search field holds first responder, so the table is never
    /// "focused" in AppKit's sense. Reporting `.emphasized` anyway keeps
    /// the selected row vivid, which is the whole point of it.
    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isSelected ? .emphasized : .normal
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let rect = bounds.insetBy(dx: Metrics.selectionInset, dy: Metrics.selectionVerticalInset)
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: Metrics.selectionRadius, yRadius: Metrics.selectionRadius).fill()
    }
}

/// One row: type icon, one-line label, and — for images — a small
/// thumbnail on the trailing edge. The thumbnail sits last so that every
/// row's label starts on the same vertical line.
final class ClipboardHistoryCellView: NSTableCellView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let thumbnailView = NSImageView()
    /// True for the "nothing copied yet" row, which stays secondary
    /// coloured because it is never selected.
    private var isMessage = false

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = .secondaryLabelColor

        label.font = .systemFont(ofSize: Metrics.rowFontSize)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 1
        label.cell?.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // A preview label can be 500 characters. Low compression resistance
        // is what lets it truncate to the row's width; the scroll view
        // already stops the table from pushing the window, but the row
        // would otherwise scroll sideways within it.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        thumbnailView.imageScaling = .scaleProportionallyDown
        thumbnailView.imageAlignment = .alignCenter
        thumbnailView.setContentHuggingPriority(.required, for: .horizontal)

        // NSTableCellView's own outlets: VoiceOver reads a row through
        // them, so a row without them announces as an unlabelled group.
        textField = label
        imageView = icon

        let stack = NSStackView(views: [icon, label, thumbnailView])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = Metrics.iconGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.cellInset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.cellInset),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: Metrics.iconSlot),
            icon.heightAnchor.constraint(equalToConstant: Metrics.iconSlot),
            thumbnailView.widthAnchor.constraint(lessThanOrEqualToConstant: Metrics.thumbnailBox.width),
            thumbnailView.heightAnchor.constraint(lessThanOrEqualToConstant: Metrics.thumbnailBox.height),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Colours follow the row's background: on the accent highlight the
    /// icon and label switch to the matching foreground colour.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyColors() }
    }

    func configure(symbolName: String?, text: String, thumbnail: NSImage?, isMessage: Bool) {
        self.isMessage = isMessage
        icon.image = symbolName.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        label.stringValue = text
        label.toolTip = text
        thumbnailView.image = thumbnail
        thumbnailView.isHidden = thumbnail == nil
        applyColors()
    }

    private func applyColors() {
        let isHighlighted = backgroundStyle == .emphasized
        let foreground: NSColor = isHighlighted ? .alternateSelectedControlTextColor : .labelColor
        label.textColor = isMessage ? .secondaryLabelColor : foreground
        icon.contentTintColor = isHighlighted ? .alternateSelectedControlTextColor : .secondaryLabelColor
    }
}
