import AppKit
import ApplicationServices

/// Shows the Teams web content to Accessibility before each scan, and hides it again after the last one.
struct TeamsWebContentSource: TeamsSnapshotReading {
    let source: any TeamsSnapshotReading
    let webContent: TeamsWebContentSwitch

    func snapshot() -> TeamsAXSnapshot {
        webContent.turnOn()
        return source.snapshot()
    }

    func finish() {
        webContent.restore()
        source.finish()
    }
}

protocol TeamsAppFlagPort {
    func isTrusted() -> Bool
    func teamsProcesses() -> [pid_t]
    /// Nil when Teams gives no readable value.
    func enhancedUserInterface(_ pid: pid_t) -> Bool?
    func setEnhancedUserInterface(_ pid: pid_t, _ on: Bool)
}

/// Teams draws its call in an embedded Edge WebView, which shows its web content to Accessibility only
/// after a client sets `AXEnhancedUserInterface` on the Teams app. Teams does not support Electron's
/// `AXManualAccessibility`. The content stays visible until Teams quits, even after the flag goes off.
/// docs/superpowers/research/2026-11-09-teams-ax-tree.md has the evidence.
final class TeamsWebContentSwitch {
    private let port: any TeamsAppFlagPort
    private let log: (LogMessage) -> Void
    /// Each Teams process that was checked, with true when Mysli turned its flag on.
    private var turnedOn: [pid_t: Bool] = [:]

    init(port: any TeamsAppFlagPort, log: @escaping (LogMessage) -> Void = { Log.teams.notice($0) }) {
        self.port = port
        self.log = log
    }

    convenience init() { self.init(port: NativeTeamsAppFlag()) }

    /// A flag that is already on belongs to another client, such as VoiceOver, so it stays untouched.
    func turnOn() {
        guard port.isTrusted() else { return }
        for pid in port.teamsProcesses() where turnedOn[pid] == nil {
            let alreadyOn = port.enhancedUserInterface(pid) == true
            turnedOn[pid] = !alreadyOn
            if alreadyOn {
                log("Teams web content: AXEnhancedUserInterface was already on. Left as is.")
            } else {
                port.setEnhancedUserInterface(pid, true)
                log("Teams web content: turned on AXEnhancedUserInterface.")
            }
        }
    }

    /// Turns the flag off for the Teams processes that `turnOn` changed, because Chromium moves and
    /// resizes its windows slowly while the flag is on.
    func restore() {
        let restored = port.teamsProcesses().filter { turnedOn[$0] == true }.sorted()
        for pid in restored { port.setEnhancedUserInterface(pid, false) }
        if !restored.isEmpty { log("Teams web content: turned AXEnhancedUserInterface off again.") }
        turnedOn = [:]
    }
}

private struct NativeTeamsAppFlag: TeamsAppFlagPort {
    private static let attribute = "AXEnhancedUserInterface" as CFString

    func isTrusted() -> Bool { AXIsProcessTrusted() }

    func teamsProcesses() -> [pid_t] {
        NSRunningApplication.runningApplications(withBundleIdentifier: TeamsAXRules.bundleIdentifier)
            .map(\.processIdentifier)
    }

    func enhancedUserInterface(_ pid: pid_t) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application(pid), Self.attribute, &value) == .success,
              let value, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return (value as! CFBoolean) == kCFBooleanTrue
    }

    /// Teams answers -25208 (not implemented) even when the write takes effect, so the status says nothing.
    func setEnhancedUserInterface(_ pid: pid_t, _ on: Bool) {
        _ = AXUIElementSetAttributeValue(application(pid), Self.attribute, on ? kCFBooleanTrue : kCFBooleanFalse)
    }

    private func application(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.25)
        return element
    }
}
