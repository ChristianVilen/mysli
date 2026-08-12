import Cocoa

/// Preflight for the Screen Recording permission ScreenCaptureKit needs.
/// Without it, captures fail with nothing but a log line; this surfaces the
/// problem the same way HotkeyManager's Accessibility prompt does.
@MainActor
enum ScreenRecordingPermission {
    /// True when the app can capture the screen. When false, asks macOS to
    /// prompt (the system shows its own dialog only on the very first ask)
    /// and shows an alert pointing at the right Privacy pane, so a denied
    /// permission never fails silently.
    static func ensureGranted() -> Bool {
        guard !CGPreflightScreenCaptureAccess() else { return true }
        CGRequestScreenCaptureAccess()
        showAlert()
        return false
    }

    private static func showAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "Ku-Ka needs Screen Recording permission to take screenshots.\n\nPlease enable it in System Settings → Privacy & Security → Screen Recording, then try again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }
}
