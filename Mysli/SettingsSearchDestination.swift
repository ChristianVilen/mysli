import Cocoa

@MainActor
struct SettingsSearchDestination {
    let item: SettingsSearchItem
    let view: NSView
    var control: NSView?
    var reveal: (() -> Void)?
    var isAvailable: () -> Bool = { true }
}
