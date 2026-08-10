import Foundation

protocol StageManagerDetecting {
    var isStageManagerEnabled: Bool { get }
}

/// Reads the system Stage Manager setting fresh on every access — no
/// caching, since the user can toggle Stage Manager at any time. Ku-Ka is
/// not sandboxed, so reading another app's UserDefaults domain works.
struct StageManagerDetector: StageManagerDetecting {
    var isStageManagerEnabled: Bool {
        UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
    }
}
