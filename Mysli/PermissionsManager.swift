import AVFoundation
import Cocoa
import UserNotifications

/// The System Settings panes Mysli opens for permissions and shortcut setup.
enum SettingsPane {
    case accessibility
    case screenCapture
    case microphone
    case calendars
    case notifications
    case keyboardShortcuts

    /// Privacy panes try the modern identifier first. Keyboard setup tries
    /// the shortcuts link, then falls back to the general Keyboard pane.
    var urls: [URL] {
        let anchor: String
        switch self {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .screenCapture: anchor = "Privacy_ScreenCapture"
        case .microphone: anchor = "Privacy_Microphone"
        case .calendars: anchor = "Privacy_Calendars"
        case .notifications:
            return [URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!]
        case .keyboardShortcuts:
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

enum NotificationAccess: Equatable {
    case granted, denied, notDetermined

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .authorized, .provisional: self = .granted
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        @unknown default: self = .denied
        }
    }
}

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
    private(set) var notifications = NotificationAccess.notDetermined

    /// Notification reads can call this after `refresh()` returns.
    var onChange: (@MainActor () -> Void)?

    private let isAccessibilityTrusted: () -> Bool
    private let hasScreenCaptureAccess: () -> Bool
    private let microphoneAccess: () -> MicrophoneAccess
    private let requestMicrophoneAccess: @MainActor () async -> Bool
    private let calendarAccess: () -> CalendarAccess
    private let requestCalendarAccess: @MainActor () async -> Bool
    private let notificationAccess: @MainActor () async -> NotificationAccess
    private let requestNotificationAccess: @MainActor () async -> Bool
    private let openURL: (URL) -> Bool
    private let showAccessibilityPrompt: () -> Void
    private let defaults: UserDefaults
    private let pollInterval: TimeInterval
    private var timer: Timer?
    private var notificationRevision = 0
    private var notificationRefresh: Task<Void, Never>?

    var snapshot: PermissionSnapshot {
        PermissionSnapshot(accessibility: accessibility, screenRecording: screenRecording,
                           microphone: microphone, calendar: calendar, notifications: notifications)
    }

    /// The probes, the opener and the prompt default to the real system
    /// calls; tests inject stand-ins. Calendar and notification probes are supplied by the app,
    /// so their defaults never reach EventKit or the notification center.
    init(
        isAccessibilityTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        hasScreenCaptureAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        microphoneAccess: @escaping () -> MicrophoneAccess = { MicrophoneAccess(AVCaptureDevice.authorizationStatus(for: .audio)) },
        requestMicrophoneAccess: @escaping @MainActor () async -> Bool = { await AVCaptureDevice.requestAccess(for: .audio) },
        calendarAccess: @escaping () -> CalendarAccess = { .notDetermined },
        requestCalendarAccess: @escaping @MainActor () async -> Bool = { false },
        notificationAccess: @escaping @MainActor () async -> NotificationAccess = { .notDetermined },
        requestNotificationAccess: @escaping @MainActor () async -> Bool = { false },
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
        self.notificationAccess = notificationAccess
        self.requestNotificationAccess = requestNotificationAccess
        self.openURL = openURL
        self.showAccessibilityPrompt = showAccessibilityPrompt
        self.defaults = defaults
        self.pollInterval = pollInterval
    }

    /// Re-read every status without prompting the user.
    func refresh() {
        let before = snapshot
        accessibility = isAccessibilityTrusted()
        screenRecording = hasScreenCaptureAccess()
        microphone = microphoneAccess()
        calendar = calendarAccess()
        notificationRevision += 1
        let revision = notificationRevision
        notificationRefresh = Task { [weak self, notificationAccess] in
            let access = await notificationAccess()
            guard let self, revision == notificationRevision else { return }
            notificationRefresh = nil
            guard access != notifications else { return }
            notifications = access
            onChange?()
        }
        if snapshot != before { onChange?() }
    }

    func refreshAndWait() async {
        refresh()
        while let pending = notificationRefresh { await pending.value }
    }

    func requestNotifications() async {
        await refreshAndWait()
        switch notifications {
        case .granted: return
        case .denied: openSettings(.notifications)
        case .notDetermined:
            _ = await requestNotificationAccess()
            await refreshAndWait()
        }
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
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    /// Poll every `pollInterval` (0.5s) so a grant made in System Settings
    /// shows up live. Only meant to run while the Permissions page is visible.
    func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            // Timers scheduled from the main thread fire on the main run loop.
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}
