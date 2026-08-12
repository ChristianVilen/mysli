import Foundation

// This seam costs more lines than the one read behind it — accepted as the
// price of testing WindowTilingController. If a second macOS-environment
// probe ever appears, widen this into one DesktopEnvironment interface
// rather than adding another single-property seam.
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
