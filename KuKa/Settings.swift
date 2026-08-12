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

    var launchAtLogin: Bool { loginItem.isEnabled }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
        } catch {
            NSLog("Launch at login toggle failed: \(error)")
        }
    }
}
