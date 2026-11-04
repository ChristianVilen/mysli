import AppKit

extension NSTextField {
    /// `digits` gives each digit the same width so a timer does not shift as it counts.
    static func makeLabel(size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor,
                          digits: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = digits ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    static func makeWrappingLabel(size: CGFloat, weight: NSFont.Weight = .regular,
                                  color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.cell?.wraps = true
        return label
    }

    func show(_ text: String?) {
        stringValue = text ?? ""
        isHidden = text == nil
    }
}
