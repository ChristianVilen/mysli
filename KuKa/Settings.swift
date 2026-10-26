import Cocoa
import ServiceManagement

/// Test seam for the login-item registration KuKa can't exercise in tests.
protocol LoginItemManaging {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

struct SystemLoginItem: LoginItemManaging {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Typed access to user preferences: every key and default defined once.
final class Settings {
    private let defaults: UserDefaults
    private let loginItem: LoginItemManaging

    init(defaults: UserDefaults = .standard,
         loginItem: LoginItemManaging = SystemLoginItem()) {
        self.defaults = defaults
        self.loginItem = loginItem
    }

    var thumbnailDuration: Double {
        get { defaults.object(forKey: "thumbnailDuration") as? Double ?? 5.0 }
        set { defaults.set(newValue, forKey: "thumbnailDuration") }
    }

    var windowTilingEnabled: Bool {
        get { defaults.object(forKey: "windowTilingEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "windowTilingEnabled") }
    }

    var clipboardHistoryEnabled: Bool {
        get { defaults.object(forKey: "clipboardHistoryEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "clipboardHistoryEnabled") }
    }

    /// Defaults to ~/Meetings, not ~/Documents or ~/Desktop: with iCloud
    /// "Desktop & Documents" on, those sync to iCloud, and meeting audio must
    /// stay on this Mac.
    var meetingsFolder: URL {
        guard let path = defaults.string(forKey: "meetingsFolder"), !path.isEmpty else {
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Meetings", isDirectory: true)
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// A BCP 47 tag such as "de-DE", set with `defaults write`.
    var meetingLocale: Locale {
        guard let tag = defaults.string(forKey: "meetingLocale"), !tag.isEmpty else {
            return Locale(identifier: "en-US")
        }
        return Locale(identifier: tag)
    }

    var didShowScreenshotShortcutSetup: Bool {
        get { defaults.bool(forKey: "didShowScreenshotShortcutSetup") }
        set { defaults.set(newValue, forKey: "didShowScreenshotShortcutSetup") }
    }

    var launchAtLogin: Bool { loginItem.isEnabled }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
        } catch {
            NSLog("Launch at login toggle failed: \(error)")
        }
    }
}
