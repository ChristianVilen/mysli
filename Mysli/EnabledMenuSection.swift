import Cocoa

@MainActor
final class EnabledMenuSection: MenuSection {
    private let section: MenuSection
    private let isEnabled: () -> Bool
    private weak var menu: NSMenu?
    private let anchor = NSMenuItem.separator()
    private var items: [NSMenuItem] = []
    private var visible = true

    init(_ section: MenuSection, isEnabled: @escaping () -> Bool) {
        self.section = section
        self.isEnabled = isEnabled
    }

    func buildMenuSection(into menu: NSMenu) {
        self.menu = menu
        let start = menu.items.count
        section.buildMenuSection(into: menu)
        items = Array(menu.items.dropFirst(start))
        anchor.isHidden = true
        menu.addItem(anchor)
        updateVisibility()
    }

    func menuWillOpen() {
        updateVisibility()
        if visible { section.menuWillOpen() }
    }

    func menuTick() {
        if visible { section.menuTick() }
    }

    func menuDidClose() { section.menuDidClose() }

    private func updateVisibility() {
        let enabled = isEnabled()
        guard enabled != visible, let menu else { return }
        visible = enabled
        if enabled {
            for item in items { menu.insertItem(item, at: menu.index(of: anchor)) }
        } else {
            for item in items { menu.removeItem(item) }
        }
    }
}
