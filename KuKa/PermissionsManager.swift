import Cocoa

/// The System Settings panes Ku-Ka deep-links into. The anchor tokens after
/// `?` are unchanged across the System Settings redesign.
enum SettingsPane {
    case accessibility
    case screenCapture

    private var anchor: String {
        switch self {
        case .accessibility: return "Privacy_Accessibility"
        case .screenCapture: return "Privacy_ScreenCapture"
        }
    }

    /// In the order to try them: the modern `.extension` pane identifier
    /// (Sequoia/Tahoe) first, then the pre-redesign form as fallback — Apple
    /// has broken some `.extension` panes on individual builds.
    var urls: [URL] {
        [
            URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?" + anchor)!,
            URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor)!,
        ]
    }
}

/// Single source of truth for the two permissions Ku-Ka needs: Accessibility
/// (the CGEvent tap for hotkeys plus AX window moves for tiling) and Screen
/// Recording (ScreenCaptureKit capture).
///
/// macOS offers no callback when the user grants a permission in System
/// Settings, so status is re-read either on demand (`refresh()`) or on a
/// short timer while the onboarding window is open (`startPolling()`).
@MainActor
final class PermissionsManager {
    private(set) var accessibility = false
    private(set) var screenRecording = false

    /// Fired after `refresh()` whenever either status changed.
    var onChange: (@MainActor () -> Void)?

    private let isAccessibilityTrusted: () -> Bool
    private let hasScreenCaptureAccess: () -> Bool
    private let openURL: (URL) -> Bool
    private var timer: Timer?

    var allGranted: Bool { accessibility && screenRecording }

    /// The probes and opener default to the real system calls; tests inject
    /// stand-ins.
    init(
        isAccessibilityTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        hasScreenCaptureAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.hasScreenCaptureAccess = hasScreenCaptureAccess
        self.openURL = openURL
    }

    /// Re-read both statuses without prompting the user.
    func refresh() {
        let ax = isAccessibilityTrusted()
        let screen = hasScreenCaptureAccess()
        guard ax != accessibility || screen != screenRecording else { return }
        accessibility = ax
        screenRecording = screen
        onChange?()
    }

    /// Show the system Accessibility prompt (which also lists the app in the
    /// Accessibility pane) and open that pane.
    func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )
        openSettings(.accessibility)
    }

    /// Show the system Screen Recording prompt and open that pane. The
    /// request call is also what registers the app in the Screen Recording
    /// list — without it the app may not appear there at all.
    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        openSettings(.screenCapture)
    }

    func openSettings(_ pane: SettingsPane) {
        for url in pane.urls where openURL(url) { return }
        NSLog("Ku-Ka: could not open the System Settings pane for \(pane)")
    }

    /// Keep status fresh outside the onboarding poll: re-read whenever the
    /// app becomes active — catches grants (or revocations) made in System
    /// Settings while we weren't polling. Runs for the app's lifetime.
    func startMonitoring() {
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The .main queue delivers on the main thread.
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Poll every 0.5s so a grant made in System Settings shows up live.
    /// Only meant to run while the onboarding window is open.
    func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            // Timers scheduled from the main thread fire on the main run loop.
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}
