import Cocoa

/// An accessory app's window does not reliably come to the front or get the keyboard. So the app is
/// `.regular` while any ordinary window is open, and `.accessory` again after the last one closes.
@MainActor
final class OrdinaryWindowActivation {
    static let shared = OrdinaryWindowActivation()
    private var windows: Set<ObjectIdentifier> = []
    private let setPolicy: (NSApplication.ActivationPolicy) -> Void
    private let activateApp: () -> Void
    private let nextTurn: (@escaping @MainActor () -> Void) -> Void

    init(setPolicy: @escaping (NSApplication.ActivationPolicy) -> Void = { NSApp.setActivationPolicy($0) },
         activateApp: @escaping () -> Void = { NSApp.activate() },
         nextTurn: @escaping (@escaping @MainActor () -> Void) -> Void = { work in Task { @MainActor in work() } }) {
        self.setPolicy = setPolicy
        self.activateApp = activateApp
        self.nextTurn = nextTurn
    }

    /// Call on every show, also for a window that is already open: it brings Mysli to the front.
    func open(_ window: NSWindow) {
        let becomesRegular = windows.isEmpty
        windows.insert(ObjectIdentifier(window))
        guard becomesRegular else { return activateApp() }
        setPolicy(.regular)
        // macOS can refuse an activation that comes in the same turn as the policy change. The
        // window then opens behind the active app, and Stage Manager puts it in the side strip.
        nextTurn { [weak self] in self?.activateApp() }
    }

    func close(_ window: NSWindow) {
        guard windows.remove(ObjectIdentifier(window)) != nil else { return }
        if windows.isEmpty { setPolicy(.accessory) }
    }
}
