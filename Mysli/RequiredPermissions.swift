enum MysliPermission: CaseIterable {
    case accessibility, screenRecording, microphone, calendar, notifications, inputMonitoring

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        case .microphone: "Microphone"
        case .calendar: "Calendar"
        case .notifications: "Notifications"
        case .inputMonitoring: "Input Monitoring"
        }
    }

    var explanation: String {
        switch self {
        case .accessibility: "Move windows, paste clipboard items and dictation, and read text near the cursor for dictation."
        case .screenRecording: "Take screenshots and record Mac audio for meeting notes. macOS may ask you to quit and reopen Mysli. Unfinished setup returns to its saved step."
        case .microphone: "Record your voice for meeting notes and dictation."
        case .calendar: "Read event titles and times for calendar reminders. Mysli never changes your calendar."
        case .notifications: "Show calendar reminders when an event starts or ends."
        case .inputMonitoring: "Listen for the Fn key for dictation. Control + Option + D does not need this permission."
        }
    }
}

struct RequiredPermissions {
    let permissions: [MysliPermission]

    init(tools: Set<MysliTool>, calendarReminders: Bool, dictationKeyMode: DictationKeyMode = .fn) {
        var needed: Set<MysliPermission> = []
        if tools.contains(.screenshots) { needed.insert(.screenRecording) }
        if !tools.isDisjoint(with: [.clipboard, .windows]) { needed.insert(.accessibility) }
        if tools.contains(.meetings) {
            needed.formUnion([.screenRecording, .microphone])
            if calendarReminders { needed.formUnion([.calendar, .notifications]) }
        }
        if tools.contains(.dictation) {
            needed.formUnion([.accessibility, .microphone])
            if dictationKeyMode == .fn { needed.insert(.inputMonitoring) }
        }
        permissions = MysliPermission.allCases.filter { needed.contains($0) }
    }

    func allGranted(in snapshot: PermissionSnapshot) -> Bool {
        permissions.allSatisfy { snapshot.status(for: $0) == .granted }
    }
}

struct PermissionSnapshot: Equatable {
    enum Status { case granted, missing, notAsked }

    let accessibility: Bool
    let screenRecording: Bool
    let microphone: MicrophoneAccess
    let calendar: CalendarAccess
    let notifications: NotificationAccess
    var inputMonitoring: Bool = false

    func status(for permission: MysliPermission) -> Status {
        switch permission {
        case .accessibility: return accessibility ? .granted : .missing
        case .screenRecording: return screenRecording ? .granted : .missing
        case .inputMonitoring: return inputMonitoring ? .granted : .missing
        case .microphone:
            switch microphone {
            case .granted: return .granted
            case .denied: return .missing
            case .notDetermined: return .notAsked
            }
        case .calendar:
            switch calendar {
            case .full: return .granted
            case .denied: return .missing
            case .notDetermined: return .notAsked
            }
        case .notifications:
            switch notifications {
            case .granted: return .granted
            case .denied: return .missing
            case .notDetermined: return .notAsked
            }
        }
    }
}
