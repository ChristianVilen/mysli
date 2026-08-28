import Cocoa
import Carbon.HIToolbox

/// The raw macOS secure-keyboard-input probes. Secure input silently starves
/// every CGEvent tap (all Ku-Ka hotkeys) while any app holds it. Normal holds
/// are short — a focused password field — but a crashed or misbehaving app can
/// leak the grab indefinitely. Nobody but the holder can release it; all
/// Ku-Ka can do is tell the user who to blame.
///
/// The dwell rule that decides when a hold counts as stuck lives in
/// `HotkeyHealthMonitor`, next to the identical rule for a dead tap.
enum SecureInput {
    static func isEnabled() -> Bool {
        IsSecureEventInputEnabled()
    }

    /// Name of the app holding secure input, from the session dictionary's
    /// holder pid. Nil when the pid is missing or no longer maps to a running
    /// app (a quit app can leak the grab, and the pid outlives it).
    static func holderName() -> String? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = (session["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value else {
            return nil
        }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }
}
