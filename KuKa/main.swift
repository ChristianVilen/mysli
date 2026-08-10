import Cocoa

// Process entry always runs on the main thread; assumeIsolated makes that
// visible to the compiler so the @MainActor AppDelegate can be created here.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
