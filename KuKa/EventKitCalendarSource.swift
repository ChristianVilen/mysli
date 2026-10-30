import EventKit

struct CalendarEventFields {
    var calendar: String
    var item: String
    var originalOccurrence: Date?
    var recurring = false
    var external: String?
    var source: String
    var title: String
    var start: Date
    var end: Date
    var allDay = false
    var cancelled = false
    var declined = false
    var free = false

    var occurrence: CalendarOccurrence {
        CalendarOccurrence(id: .init(calendar: calendar, item: item,
                                    originalOccurrence: recurring ? originalOccurrence : nil),
                           title: title, start: start, end: end, allDay: allDay,
                           cancelled: cancelled, declined: declined, free: free)
    }

    init(calendar: String, item: String, originalOccurrence: Date? = nil, recurring: Bool = false,
         external: String? = nil, source: String, title: String, start: Date, end: Date) {
        self.calendar = calendar
        self.item = item
        self.originalOccurrence = originalOccurrence
        self.recurring = recurring
        self.external = external
        self.source = source
        self.title = title
        self.start = start
        self.end = end
    }

    init?(_ event: EKEvent) {
        guard let calendar = event.calendar, let start = event.startDate, let end = event.endDate else { return nil }
        self.init(calendar: calendar.calendarIdentifier, item: event.calendarItemIdentifier,
                  originalOccurrence: event.occurrenceDate,
                  recurring: event.hasRecurrenceRules || event.isDetached,
                  external: event.calendarItemExternalIdentifier, source: calendar.source.sourceIdentifier,
                  title: event.title ?? "", start: start, end: end)
        allDay = event.isAllDay
        cancelled = event.status == .canceled
        declined = event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
        free = event.availability == .free
    }
}

@MainActor
final class EventKitCalendarSource: CalendarEventSource {
    struct Calls {
        var authorization: () -> EKAuthorizationStatus
        var requestAccess: () async throws -> Bool
        var events: (Date, Date) throws -> [CalendarEventFields]
        var item: (String) -> CalendarEventFields?
    }
    private let calls: Calls
    private struct Alias: Hashable {
        let source: String
        let external: String
        let original: Date?
    }
    private var aliases: [Alias: CalendarOccurrence.ID] = [:]
    private var ambiguous: Set<Alias> = []
    private var observed: [CalendarOccurrence.ID: CalendarEventFields] = [:]
    enum ReadFailure: Error { case accessRequired }
    init(calls: Calls) { self.calls = calls }

    convenience init() {
        let store = EKEventStore()
        self.init(calls: Calls(authorization: { EKEventStore.authorizationStatus(for: .event) },
            requestAccess: { try await store.requestFullAccessToEvents() }, events: { from, to in
                store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: nil))
                    .compactMap(CalendarEventFields.init)
            }, item: { (store.calendarItem(withIdentifier: $0) as? EKEvent).flatMap(CalendarEventFields.init) }))
    }

    var authorization: CalendarAccess {
        switch calls.authorization() {
        case .notDetermined: .notDetermined
        case .fullAccess: .full
        default: .denied
        }
    }
    func requestAccess() async -> Bool {
        if authorization == .full { return true }
        guard authorization == .notDetermined else { return false }
        return (try? await calls.requestAccess()) == true && authorization == .full
    }
    func occurrences(from: Date, to: Date) async throws -> [CalendarOccurrence] {
        guard authorization == .full else { throw ReadFailure.accessRequired }
        return normalize(try calls.events(from, to))
    }
    func occurrence(id: CalendarOccurrence.ID) async throws -> CalendarOccurrence? {
        guard authorization == .full else { throw ReadFailure.accessRequired }
        let previous = observed[id]
        if id.originalOccurrence == nil, let item = calls.item(previous?.item ?? id.item),
           item.occurrence.id == (previous?.occurrence.id ?? id) {
            return normalize([item], establishAliases: false).first { $0.id == id }
        }
        let dates = [previous?.start, id.originalOccurrence].compactMap { $0 }
        guard !dates.isEmpty else { return nil }
        var fields: [CalendarOccurrence.ID: CalendarEventFields] = [:]
        for date in Set(dates) {
            for event in try calls.events(date.addingTimeInterval(-86_400), date.addingTimeInterval(86_400)) {
                fields[event.occurrence.id] = event
            }
        }
        return normalize(Array(fields.values), establishAliases: false).first { $0.id == id }
    }

    private func normalize(_ events: [CalendarEventFields], establishAliases: Bool = true) -> [CalendarOccurrence] {
        if observed.count > 4096 { observed.removeAll(); aliases.removeAll() }
        let groups = Dictionary(grouping: events, by: alias)
        for (key, values) in groups where values.count > 1 {
            if let key { reject(key) }
        }
        return events.compactMap { event in
            guard !event.calendar.isEmpty, !event.item.isEmpty,
                  !event.recurring || event.originalOccurrence != nil else { return nil }
            let raw = event.occurrence
            var id = raw.id
            if let key = alias(event), !ambiguous.contains(key), groups[key]?.count == 1 {
                if let canonical = aliases[key], let old = observed[canonical] {
                    let previousItem = old.occurrence.id
                    if previousItem != raw.id,
                       let stillPresent = calls.item(old.item),
                       stillPresent.calendar == old.calendar && stillPresent.item == old.item {
                        reject(key)
                    } else {
                        id = canonical
                    }
                } else if establishAliases {
                    aliases[key] = raw.id
                }
            }
            observed[id] = event
            return CalendarOccurrence(id: id, title: raw.title, start: raw.start, end: raw.end,
                                      allDay: raw.allDay, cancelled: raw.cancelled, declined: raw.declined, free: raw.free)
        }
    }

    private func reject(_ key: Alias) {
        ambiguous.insert(key)
        aliases.removeValue(forKey: key)
    }

    private func alias(_ event: CalendarEventFields) -> Alias? {
        guard let external = event.external, !external.isEmpty else { return nil }
        return Alias(source: event.source, external: external, original: event.occurrence.id.originalOccurrence)
    }
}
