import UserNotifications

@MainActor
final class CalendarReminderNotifications: CalendarReminderNotifying {
    struct Calls {
        var authorized: () async -> Bool
        var requestAccess: () async throws -> Bool
        var categories: () async -> Set<UNNotificationCategory>
        var setCategories: (Set<UNNotificationCategory>) -> Void
        var pending: () async -> [String]
        var delivered: () async -> [String]
        var add: (UNNotificationRequest) async throws -> Void
        var removePending: ([String]) -> Void
        var removeDelivered: ([String]) -> Void
    }
    static let prefix = "calendar-recording."
    static let startCategory = "calendar-recording.start"
    static let endCategory = "calendar-recording.end"
    static let startAction = "calendar-recording.start-recording"
    static let stopAction = "calendar-recording.stop-recording"
    static let continueAction = "calendar-recording.continue-recording"
    private let calls: Calls
    private var preparation: Task<Void, Never>?
    private var adding: Set<UUID> = []
    private var invalidated: Set<UUID> = []
    init(calls: Calls) { self.calls = calls }

    convenience init() {
        let center = UNUserNotificationCenter.current()
        self.init(calls: Calls(authorized: {
            let status = await center.notificationSettings().authorizationStatus
            return status == .authorized || status == .provisional
        }, requestAccess: { try await center.requestAuthorization(options: [.alert]) },
        categories: { await center.notificationCategories() }, setCategories: center.setNotificationCategories,
        pending: { await center.pendingNotificationRequests().map(\.identifier) },
        delivered: { await center.deliveredNotifications().map { $0.request.identifier } },
        add: { try await center.add($0) }, removePending: center.removePendingNotificationRequests,
        removeDelivered: center.removeDeliveredNotifications))
    }

    func prepare() async {
        if let preparation { await preparation.value; return }
        let task = Task {
            var categories = await calls.categories().filter {
                $0.identifier != Self.startCategory && $0.identifier != Self.endCategory
            }
            categories.insert(UNNotificationCategory(identifier: Self.startCategory,
                actions: [UNNotificationAction(identifier: Self.startAction, title: "Start Recording", options: [.foreground])],
                intentIdentifiers: [], options: [.customDismissAction]))
            categories.insert(UNNotificationCategory(identifier: Self.endCategory,
                actions: [UNNotificationAction(identifier: Self.stopAction, title: "Stop Recording"),
                          UNNotificationAction(identifier: Self.continueAction, title: "Continue Recording")],
                intentIdentifiers: [], options: [.customDismissAction]))
            calls.setCategories(categories)
            let pending = await calls.pending().filter { $0.hasPrefix(Self.prefix) }
            let delivered = await calls.delivered().filter { $0.hasPrefix(Self.prefix) }
            calls.removePending(pending)
            calls.removeDelivered(delivered)
        }
        preparation = task
        await task.value
    }
    func authorizationGranted() async -> Bool { await calls.authorized() }
    func requestAccess() async -> Bool { (try? await calls.requestAccess()) == true }
    func add(_ reminder: CalendarReminder) async throws {
        adding.insert(reminder.token)
        defer { adding.remove(reminder.token); invalidated.remove(reminder.token) }
        await prepare()
        guard !invalidated.contains(reminder.token) else { return }
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.kind == .start ? "Record this calendar meeting?" : "The calendar meeting has ended."
        content.categoryIdentifier = reminder.kind == .start ? Self.startCategory : Self.endCategory
        content.userInfo = ["calendarToken": reminder.token.uuidString]
        do {
            try await calls.add(UNNotificationRequest(identifier: Self.prefix + reminder.token.uuidString,
                                                      content: content, trigger: nil))
        } catch {
            cancel(tokens: [reminder.token])
            throw error
        }
        if invalidated.contains(reminder.token) { cancel(tokens: [reminder.token]) }
    }
    func cancel(tokens: [UUID]) {
        invalidated.formUnion(tokens.filter { adding.contains($0) })
        let identifiers = tokens.map { Self.prefix + $0.uuidString }
        calls.removePending(identifiers)
        calls.removeDelivered(identifiers)
    }
    static func decode(category: String, action: String, userInfo: [AnyHashable: Any])
        -> (action: CalendarReminderAction, token: UUID)? {
        guard category == startCategory || category == endCategory,
              let string = userInfo["calendarToken"] as? String, let token = UUID(uuidString: string) else { return nil }
        let decoded: CalendarReminderAction
        switch (category, action) {
        case (startCategory, startAction): decoded = .start
        case (endCategory, stopAction): decoded = .stop
        case (endCategory, continueAction): decoded = .continueRecording
        case (endCategory, UNNotificationDefaultActionIdentifier): decoded = .showControls
        case (_, UNNotificationDefaultActionIdentifier), (_, UNNotificationDismissActionIdentifier): decoded = .dismiss
        default: return nil
        }
        return (decoded, token)
    }
}
