import Cocoa

enum SettingsPage: Int, CaseIterable {
    case settings, instructions

    var title: String { self == .settings ? "Settings" : "Instructions" }
    var symbol: String { self == .settings ? "gearshape" : "book.closed" }
}

struct SettingsDisplayOptions {
    var reduceTransparency: Bool
    var increaseContrast: Bool

    static var current: Self {
        Self(reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
             increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
    }
}

final class SettingsBackground: NSView {
    private let effect = NSVisualEffectView()
    private var options = SettingsDisplayOptions.current

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        SettingsLayout.fill(effect, in: self)
        apply(options)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(_ options: SettingsDisplayOptions) {
        self.options = options
        effect.isHidden = options.reduceTransparency
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = options.reduceTransparency ? NSColor.windowBackgroundColor.cgColor : nil
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        apply(options)
    }
}

final class SettingsGlass: NSView {
    let content = NSView()
    private let glass = NSGlassEffectView()
    private var options = SettingsDisplayOptions.current

    init(radius: CGFloat = 14) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = radius
        glass.style = .regular
        glass.cornerRadius = radius
        SettingsLayout.fill(glass, in: self)
        apply(options)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(_ options: SettingsDisplayOptions) {
        self.options = options
        glass.isHidden = options.reduceTransparency
        let parent: NSView = options.reduceTransparency ? self : glass
        if content.superview !== parent {
            glass.contentView = nil
            content.removeFromSuperview()
            if options.reduceTransparency { addSubview(content) } else { glass.contentView = content }
            content.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
                content.topAnchor.constraint(equalTo: parent.topAnchor),
                content.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
            ])
        }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = options.reduceTransparency ? NSColor.controlBackgroundColor.cgColor : nil
            layer?.borderWidth = options.increaseContrast ? 1.5 : 0.5
            layer?.borderColor = (options.increaseContrast ? NSColor.labelColor : NSColor.labelColor.withAlphaComponent(0.12)).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        apply(options)
    }
}

enum SettingsLayout {
    static func stack(_ views: [NSView] = [], spacing: CGFloat = 12) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    static func label(_ text: String, size: CGFloat = 13, secondary: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        return label
    }

    static func fill(_ child: NSView, in parent: NSView, inset: CGFloat = 0) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
        ])
    }

    static func add(_ child: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(child)
        child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    static func row(_ title: String, detail: String? = nil, control: NSView) -> NSView {
        let copy = stack(spacing: 4)
        add(label(title), to: copy)
        if let detail { add(label(detail, size: 11, secondary: true), to: copy) }
        copy.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        copy.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let row = NSStackView(views: [copy, control])
        row.distribution = .fill
        row.spacing = 12
        row.alignment = .centerY
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        (control as? NSStackView)?.setHuggingPriority(.required, for: .horizontal)
        return row
    }

    static func group(_ rows: [NSView]) -> SettingsGlass {
        let glass = SettingsGlass()
        let stack = stack(spacing: 6)
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = NSBox()
                separator.boxType = .separator
                add(separator, to: stack)
            }
            add(row, to: stack)
        }
        fill(stack, in: glass.content, inset: 10)
        return glass
    }

    static func heading(_ title: String, symbol: String, color: NSColor) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        icon.contentTintColor = .white
        icon.wantsLayer = true
        icon.layer?.backgroundColor = color.cgColor
        icon.layer?.cornerRadius = 7
        icon.imageScaling = .scaleProportionallyDown
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let title = label(title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let row = NSStackView(views: [icon, title])
        row.spacing = 9
        return row
    }

    static func page(title: String, subtitle: String) -> NSStackView {
        let stack = stack(spacing: 8)
        let heading = label(title, size: 28)
        heading.font = .systemFont(ofSize: 28, weight: .bold)
        add(heading, to: stack)
        add(label(subtitle, secondary: true), to: stack)
        return stack
    }

    static func scroll(_ page: NSView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let document = SettingsDocument()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        fill(page, in: document, inset: 20)
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        return scroll
    }
}

private final class SettingsDocument: NSView {
    override var isFlipped: Bool { true }
}
