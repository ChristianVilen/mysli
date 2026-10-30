import Cocoa

/// An accessory app's window does not reliably come to the front or get the keyboard. So the app is
/// `.regular` while any ordinary window is open, and `.accessory` again after the last one closes.
@MainActor
final class OrdinaryWindowActivation {
    static let shared = OrdinaryWindowActivation()
    private var windows: Set<ObjectIdentifier> = []
    private let setPolicy: (NSApplication.ActivationPolicy) -> Void
    private let activateApp: () -> Void

    init(setPolicy: @escaping (NSApplication.ActivationPolicy) -> Void = { NSApp.setActivationPolicy($0) },
         activateApp: @escaping () -> Void = { NSApp.activate() }) {
        self.setPolicy = setPolicy
        self.activateApp = activateApp
    }

    /// Call on every show, also for a window that is already open: it brings Ku-Ka to the front.
    func open(_ window: NSWindow) {
        if windows.isEmpty { setPolicy(.regular) }
        windows.insert(ObjectIdentifier(window))
        activateApp()
    }

    func close(_ window: NSWindow) {
        guard windows.remove(ObjectIdentifier(window)) != nil else { return }
        if windows.isEmpty { setPolicy(.accessory) }
    }
}
