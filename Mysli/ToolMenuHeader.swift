import Cocoa

extension NSMenuItem {
    static func toolHeader(_ tool: MysliTool, title: String? = nil) -> NSMenuItem {
        let item = NSMenuItem.sectionHeader(title: title ?? tool.title)
        item.image = tool.icon(size: 16)
        return item
    }
}
