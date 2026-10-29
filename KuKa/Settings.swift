import Cocoa
import ServiceManagement

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
        get {
            guard let path = defaults.string(forKey: "meetingsFolder"), !path.isEmpty else {
                return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Meetings", isDirectory: true)
            }
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        set { defaults.set(newValue.path, forKey: "meetingsFolder") }
    }

    /// The known-words list, set with `defaults write com.kuka.screenshot knownWordsFile <path>`
    /// to use a list the user already keeps. Defaults to known-words.md in the meetings folder.
    var knownWordsFile: URL {
        guard let path = defaults.string(forKey: "knownWordsFile"), !path.isEmpty else {
            return meetingsFolder.appendingPathComponent("known-words.md")
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// A BCP 47 tag such as "de-DE", set with `defaults write`.
    var meetingLocale: Locale {
        guard let tag = defaults.string(forKey: "meetingLocale"), !tag.isEmpty else {
            return Locale(identifier: "en-US")
        }
        return Locale(identifier: tag)
    }

    /// The meeting pill's top-right corner in global NS coordinates, stored as [x, y]. Nil
    /// means the default corner.
    var meetingControlsTopRight: CGPoint? {
        get {
            guard let xy = defaults.array(forKey: "meetingControlsTopRight") as? [Double], xy.count == 2 else { return nil }
            return CGPoint(x: xy[0], y: xy[1])
        }
        set {
            if let newValue {
                defaults.set([Double(newValue.x), Double(newValue.y)], forKey: "meetingControlsTopRight")
            } else {
                defaults.removeObject(forKey: "meetingControlsTopRight")
            }
        }
    }

    /// The live transcript drawer's height in points.
    var meetingTranscriptHeight: Double {
        get { defaults.object(forKey: "meetingTranscriptHeight") as? Double ?? Double(MeetingPanelPlacement.defaultDrawerHeight) }
        set { defaults.set(newValue, forKey: "meetingTranscriptHeight") }
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
