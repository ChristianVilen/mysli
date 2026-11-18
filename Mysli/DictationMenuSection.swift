import Cocoa

@MainActor
final class DictationMenuSection: NSObject, MenuSection, NSMenuItemValidation {
    private let controller: DictationController
    let replay = NSMenuItem(title: "Paste last dictation again", action: nil, keyEquivalent: "")
    private let claudeMissing = [NSMenuItem(title: "⚠️ Claude Code is not installed", action: nil, keyEquivalent: ""),
                                 NSMenuItem(title: "Text is pasted without polish", action: nil, keyEquivalent: "")]

    init(controller: DictationController) { self.controller = controller }

    func buildMenuSection(into menu: NSMenu) {
        menu.addItem(.sectionHeader(title: "Dictation"))
        for item in claudeMissing {
            item.isEnabled = false
            menu.addItem(item)
        }
        claudeMissing[1].indentationLevel = 1
        replay.target = self
        replay.action = #selector(pasteAgain)
        menu.addItem(replay)
        menu.addItem(.separator())
        menuWillOpen()
    }

    func menuWillOpen() {
        let installed = SummaryCLI.claude.installedPath() != nil
        for item in claudeMissing { item.isHidden = installed }
        menuTick()
    }

    func menuTick() { replay.isEnabled = controller.canPasteLast }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { controller.canPasteLast }
    @objc private func pasteAgain() { controller.pasteLastAgain() }
}
