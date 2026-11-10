import Cocoa

@MainActor
final class DictationMenuSection: NSObject, MenuSection, NSMenuItemValidation {
    private let controller: DictationController
    let replay = NSMenuItem(title: "Paste last dictation again", action: nil, keyEquivalent: "")

    init(controller: DictationController) { self.controller = controller }

    func buildMenuSection(into menu: NSMenu) {
        menu.addItem(.sectionHeader(title: "Dictation"))
        replay.target = self
        replay.action = #selector(pasteAgain)
        menu.addItem(replay)
        menu.addItem(.separator())
        menuWillOpen()
    }

    func menuWillOpen() { replay.isEnabled = controller.canPasteLast }
    func menuTick() { menuWillOpen() }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { controller.canPasteLast }
    @objc private func pasteAgain() { controller.pasteLastAgain() }
}
