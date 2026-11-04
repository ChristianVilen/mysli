import AVFoundation
import Cocoa

/// The System Settings panes Mysli opens for permissions and shortcut setup.
enum SettingsPane {
    case accessibility
    case screenCapture
    case microphone
    case calendars
    case keyboardShortcuts

    private var anchor: String {
        switch self {
        case .accessibility: return "Privacy_Accessibility"
        case .screenCapture: return "Privacy_ScreenCapture"
        case .microphone: return "Privacy_Microphone"
        case .calendars: return "Privacy_Calendars"
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

/// Single source of truth for the permissions Mysli needs: Accessibility
/// (window moves for tiling and synthetic clipboard paste), Screen
/// Recording (ScreenCaptureKit capture), Microphone (Meeting Notes only) and
/// Calendar (calendar reminders).
///
/// macOS offers no callback when the user grants a permission in System
/// Settings, so status is re-read either on demand (`refresh()`) or on a
/// short timer while the Permissions page is visible (`startPolling()`).
@MainActor
final class PermissionsManager {
    /// Marks that the system Accessibility prompt has been shown once. See
    /// `requestAccessibility()`.
    private static let didPromptForAccessibilityKey = "didPromptForAccessibility"

    private(set) var accessibility = false
    private(set) var screenRecording = false
    private(set) var microphone = MicrophoneAccess.notDetermined
    private(set) var calendar = CalendarAccess.notDetermined

    /// Fired after `refresh()` whenever any status changed.
    var onChange: (@MainActor () -> Void)?

    private let isAccessibilityTrusted: () -> Bool
    private let hasScreenCaptureAccess: () -> Bool
    private let microphoneAccess: () -> MicrophoneAccess
    private let requestMicrophoneAccess: @MainActor () async -> Bool
    private let calendarAccess: () -> CalendarAccess
    private let requestCalendarAccess: @MainActor () async -> Bool
    private let openURL: (URL) -> Bool
    private let showAccessibilityPrompt: () -> Void
    private let defaults: UserDefaults
    private let pollInterval: TimeInterval
    private var timer: Timer?

    /// Launch opens the Permissions page when this is false. It leaves out Microphone on purpose:
    /// people who never record a meeting must not get that page for Microphone. Calendar counts
    /// (decided by the user, 2026-11-04), although calendar reminders stay off until turned on.
    var allGranted: Bool { accessibility && screenRecording && calendar == .full }

    /// The probes, the opener and the prompt default to the real system
    /// calls; tests inject stand-ins. The calendar probes are the exception: the app
    /// passes its one `EventKitCalendarSource`, and the defaults never touch EventKit.
    init(
        isAccessibilityTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        hasScreenCaptureAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        microphoneAccess: @escaping () -> MicrophoneAccess = { MicrophoneAccess(AVCaptureDevice.authorizationStatus(for: .audio)) },
        requestMicrophoneAccess: @escaping @MainActor () async -> Bool = { await AVCaptureDevice.requestAccess(for: .audio) },
        calendarAccess: @escaping () -> CalendarAccess = { .notDetermined },
        requestCalendarAccess: @escaping @MainActor () async -> Bool = { false },
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        showAccessibilityPrompt: @escaping () -> Void = {
            _ = AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            )
        },
        defaults: UserDefaults = .standard,
        pollInterval: TimeInterval = 0.5
    ) {
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.hasScreenCaptureAccess = hasScreenCaptureAccess
        self.microphoneAccess = microphoneAccess
        self.requestMicrophoneAccess = requestMicrophoneAccess
        self.calendarAccess = calendarAccess
        self.requestCalendarAccess = requestCalendarAccess
        self.openURL = openURL
        self.showAccessibilityPrompt = showAccessibilityPrompt
        self.defaults = defaults
        self.pollInterval = pollInterval
    }

    /// Re-read every status without prompting the user.
    func refresh() {
        let ax = isAccessibilityTrusted()
        let screen = hasScreenCaptureAccess()
        let mic = microphoneAccess()
        let cal = calendarAccess()
        guard ax != accessibility || screen != screenRecording || mic != microphone || cal != calendar else { return }
        accessibility = ax
        screenRecording = screen
        microphone = mic
        calendar = cal
        onChange?()
    }

    /// Asks macOS for calendar access when it never asked; macOS asks only once, so after a
    /// refusal this opens the Calendars pane instead. Calendar reminders stay as they are.
    func requestCalendar() async {
        switch calendar {
        case .full:
            return
        case .denied:
            openSettings(.calendars)
        case .notDetermined:
            _ = await requestCalendarAccess()
            refresh()
        }
    }

    /// Open the Accessibility pane, and show the system prompt on the first
    /// request only.
    ///
    /// That prompt is what puts Mysli in the Accessibility list — opening the
    /// pane alone does not — so it must run at least once, or the user finds
    /// no row to switch on.
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
    /// Unlike Accessibility, it prompts on every request: it is not a modal over the
    /// Permissions page, and macOS asks for this grant again about once a month anyway.
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
        Log.permissions.error("Could not open the System Settings pane for \(String(describing: pane), privacy: .public)")
    }

    /// Keep status fresh outside the Permissions page: re-read whenever the
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

    /// Poll every `pollInterval` (0.5s) so a grant made in System Settings
    /// shows up live. Only meant to run while the Permissions page is visible.
    func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            // Timers scheduled from the main thread fire on the main run loop.
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}
