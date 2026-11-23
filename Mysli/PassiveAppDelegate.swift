import Cocoa

/// The test and preview host shares the installed app's bundle identifier.
/// Refuse the quit that System Settings sends to all Mysli processes after a privacy change.
@MainActor
final class PassiveAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateCancel
    }
}
