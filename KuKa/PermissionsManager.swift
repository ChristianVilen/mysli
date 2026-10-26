import AVFoundation
import Cocoa

/// The System Settings panes Ku-Ka opens for permissions and shortcut setup.
enum SettingsPane {
    case accessibility
    case screenCapture
    case microphone
    case keyboardShortcuts

    private var anchor: String {
        switch self {
        case .accessibility: return "Privacy_Accessibility"
        case .screenCapture: return "Privacy_ScreenCapture"
        case .microphone: return "Privacy_Microphone"
        case .keyboardShortcuts: return "Shortcuts"
        }
    }

    /// Privacy panes try the modern identifier first. Keyboard setup tries
    /// the shortcuts link, then falls back to the general Keyboard pane.
    var urls: [URL] {
        if self == .keyboardShortcuts {
            return [
                URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts")!,
                URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!,
            ]
        }
        return [
            URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?" + anchor)!,
            URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor)!,
        ]
    }
}

enum MicrophoneAccess: Equatable {
    case granted
    case denied
    case notDetermined

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self = .granted
        case .notDetermined: self = .notDetermined
        case .denied, .restricted: self = .denied
        @unknown default: self = .denied
        }
    }
}

/// Single source of truth for the permissions Ku-Ka needs: Accessibility
/// (window moves for tiling and synthetic clipboard paste), Screen
/// Recording (ScreenCaptureKit capture) and Microphone (Meeting Notes only).
///
/// macOS offers no callback when the user grants a permission in System
/// Settings, so status is re-read either on demand (`refresh()`) or on a
/// short timer while the onboarding window is open (`startPolling()`).
@MainActor
final class PermissionsManager {
    /// Marks that the system Accessibility prompt has been shown once. See
    /// `requestAccessibility()`.
    private static let didPromptForAccessibilityKey = "didPromptForAccessibility"

    private(set) var accessibility = false
    private(set) var screenRecording = false
    private(set) var microphone = MicrophoneAccess.notDetermined

    /// Fired after `refresh()` whenever any status changed.
    var onChange: (@MainActor () -> Void)?

    private let isAccessibilityTrusted: () -> Bool
    private let hasScreenCaptureAccess: () -> Bool
    private let microphoneAccess: () -> MicrophoneAccess
    private let requestMicrophoneAccess: @MainActor () async -> Bool
    private let openURL: (URL) -> Bool
    private let showAccessibilityPrompt: () -> Void
    private let defaults: UserDefaults
    private var timer: Timer?

    var allGranted: Bool { accessibility && screenRecording }

    /// The probes, the opener and the prompt default to the real system
    /// calls; tests inject stand-ins.
    init(
        isAccessibilityTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        hasScreenCaptureAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        microphoneAccess: @escaping () -> MicrophoneAccess = { MicrophoneAccess(AVCaptureDevice.authorizationStatus(for: .audio)) },
        requestMicrophoneAccess: @escaping @MainActor () async -> Bool = { await AVCaptureDevice.requestAccess(for: .audio) },
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        showAccessibilityPrompt: @escaping () -> Void = {
            _ = AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            )
        },
        defaults: UserDefaults = .standard
    ) {
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.hasScreenCaptureAccess = hasScreenCaptureAccess
        self.microphoneAccess = microphoneAccess
        self.requestMicrophoneAccess = requestMicrophoneAccess
        self.openURL = openURL
        self.showAccessibilityPrompt = showAccessibilityPrompt
        self.defaults = defaults
    }

    /// Re-read every status without prompting the user.
    func refresh() {
        let ax = isAccessibilityTrusted()
        let screen = hasScreenCaptureAccess()
        let mic = microphoneAccess()
        guard ax != accessibility || screen != screenRecording || mic != microphone else { return }
        accessibility = ax
        screenRecording = screen
        microphone = mic
        onChange?()
    }

    /// Open the Accessibility pane, and show the system prompt on the first
    /// request only.
    ///
    /// That prompt is what puts Ku-Ka in the Accessibility list — opening the
    /// pane alone does not — so it must run at least once, or the user finds
    /// no row to switch on. After that it only repeats what the onboarding
    /// window already says, as a modal on top of it, so we stay quiet.
    func requestAccessibility() {
        if !defaults.bool(forKey: Self.didPromptForAccessibilityKey) {
            defaults.set(true, forKey: Self.didPromptForAccessibilityKey)
            showAccessibilityPrompt()
        }
        openSettings(.accessibility)
    }

    /// Show the system Screen Recording prompt and open that pane. The
    /// request call is also what registers the app in the Screen Recording
    /// list — without it the app may not appear there at all.
    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        openSettings(.screenCapture)
    }

    /// Shows the system prompt when the user was never asked; macOS shows it
    /// only once, so after a refusal this opens the Microphone pane instead.
    func requestMicrophone() async -> Bool {
        switch microphone {
        case .granted:
            return true
        case .denied:
            openSettings(.microphone)
            return false
        case .notDetermined:
            _ = await requestMicrophoneAccess()
            refresh()
            return microphone == .granted
        }
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
