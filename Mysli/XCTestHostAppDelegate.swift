import Cocoa

/// The delegate of the passive host that XCTest starts. The host has the bundle identifier of the
/// installed Mysli, so it also gets the quit requests that are meant for that app. After a privacy
/// change for Mysli, the "Quit & Reopen" button in System Settings sends a quit to every running
/// Mysli. Without a delegate, AppKit accepts the quit, the host exits in the middle of a test, and
/// xcodebuild reports that test as failed.
@MainActor
final class XCTestHostAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateCancel
    }
}
