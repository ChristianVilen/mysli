enum MysliPermission: CaseIterable {
    case accessibility, screenRecording, microphone, calendar, notifications

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        case .microphone: "Microphone"
        case .calendar: "Calendar"
        case .notifications: "Notifications"
        }
    }

    var explanation: String {
        switch self {
        case .accessibility: "Move windows and paste items from clipboard history."
        case .screenRecording: "Take screenshots and record Mac audio for meeting notes. macOS may ask you to quit and reopen Mysli. Unfinished setup returns to its saved step."
        case .microphone: "Record your voice for meeting notes."
        case .calendar: "Read event titles and times for calendar reminders. Mysli never changes your calendar."
        case .notifications: "Show calendar reminders when an event starts or ends."
        }
    }
}

struct RequiredPermissions {
    let permissions: [MysliPermission]

    init(tools: Set<MysliTool>, calendarReminders: Bool) {
        var needed: Set<MysliPermission> = []
        if tools.contains(.screenshots) { needed.insert(.screenRecording) }
        if !tools.isDisjoint(with: [.clipboard, .windows]) { needed.insert(.accessibility) }
        if tools.contains(.meetings) {
            needed.formUnion([.screenRecording, .microphone])
            if calendarReminders { needed.formUnion([.calendar, .notifications]) }
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

    func status(for permission: MysliPermission) -> Status {
        switch permission {
        case .accessibility: return accessibility ? .granted : .missing
        case .screenRecording: return screenRecording ? .granted : .missing
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
