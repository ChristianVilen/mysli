import Foundation

struct CalendarOccurrence: Equatable, Sendable {
    struct ID: Hashable, Codable, Sendable, Comparable {
        let calendar: String
        let item: String
        let originalOccurrence: Date?

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.calendar != rhs.calendar { return lhs.calendar < rhs.calendar }
            if lhs.item != rhs.item { return lhs.item < rhs.item }
            return (lhs.originalOccurrence ?? .distantPast) < (rhs.originalOccurrence ?? .distantPast)
        }
    }

    let id: ID
    var title: String
    var start: Date
    var end: Date
    var allDay = false
    var cancelled = false
    var declined = false
    var free = false

    var eligible: Bool { end > start && !allDay && !cancelled && !declined && !free }
    var displayTitle: String {
        MeetingTitle.normalized(title) ?? "Calendar meeting"
    }
}

enum CalendarAccess { case notDetermined, denied, full }

@MainActor
protocol CalendarEventSource: AnyObject {
    var authorization: CalendarAccess { get }
    func requestAccess() async -> Bool
    func occurrences(from: Date, to: Date) async throws -> [CalendarOccurrence]
    func occurrence(id: CalendarOccurrence.ID) async throws -> CalendarOccurrence?
}

struct CalendarReminder: Equatable {
    enum Kind { case start, end }
    let token: UUID
    let kind: Kind
    let title: String
}

enum CalendarReminderAction { case start, stop, continueRecording, showControls, dismiss }

@MainActor
protocol CalendarReminderNotifying: AnyObject {
    func authorizationGranted() async -> Bool
    func requestAccess() async -> Bool
    func add(_ reminder: CalendarReminder) async throws
    func cancel(tokens: [UUID])
}

@MainActor
protocol CalendarReminderRecording: AnyObject {
    var activeSessionID: UUID? { get }
    func startRecording(title: String?) async -> UUID?
    func stopRecording(ifSession: UUID)
    func showControls()
}

extension MeetingRecorder: CalendarReminderRecording {}

@MainActor
protocol CalendarReminderDriving: AnyObject {
    func start(onChange: @escaping @MainActor () -> Void)
    func schedule(at: Date?)
    func stop()
}
