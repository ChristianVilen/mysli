import Cocoa

class CombineButton: NSPanel {
    var onCombine: (() -> Void)?

    static let buttonHeight: CGFloat = 28
    static let buttonWidth: CGFloat = 100

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = frame.height / 2
        effect.layer?.masksToBounds = true

        let button = NSButton(frame: NSRect(origin: .zero, size: frame.size))
        button.title = "Combine"
        button.bezelStyle = .inline
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        button.target = self
        button.action = #selector(combineTapped)
        effect.addSubview(button)

        contentView = effect
    }

    @objc private func combineTapped() {
        onCombine?()
    }
}
