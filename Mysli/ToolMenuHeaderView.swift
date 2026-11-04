import Cocoa

/// The first row of a tool's group in the menu: its coloured square and its name.
final class ToolMenuHeaderView: NSView {
    let tool: MysliTool
    let titleLabel: NSTextField

    init(tool: MysliTool, title: String) {
        self.tool = tool
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        titleLabel.font = .menuFont(ofSize: 13)
        titleLabel.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [ToolMenuHeaderView.iconView(tool), titleLabel])
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
        ])
        frame.size = fittingSize
        autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func iconView(_ tool: MysliTool) -> NSImageView {
        let view = NSImageView(image: tool.icon(size: 16))
        view.setAccessibilityElement(false)
        return view
    }
}

extension NSMenuItem {
    /// A disabled item whose view shows the tool. The item keeps the title, so code can find the group by name.
    static func toolHeader(_ tool: MysliTool, title: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title ?? tool.title, action: nil, keyEquivalent: "")
        item.view = ToolMenuHeaderView(tool: tool, title: item.title)
        item.isEnabled = false
        return item
    }
}
