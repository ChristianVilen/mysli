import Foundation

final class CalendarReminderStore {
    private struct Receipt: Codable {
        let id: CalendarOccurrence.ID
        let end: Date
    }

    private let defaults: UserDefaults
    private let key = "calendarRecordingReminderReceipts"

    init(defaults: UserDefaults) { self.defaults = defaults }

    func consumed(at now: Date) -> Set<CalendarOccurrence.ID> {
        Set(receipts(at: now).map(\.id))
    }

    func consume(_ occurrences: [CalendarOccurrence], at now: Date) {
        guard !occurrences.isEmpty else { return }
        var ends: [CalendarOccurrence.ID: Date] = [:]
        for receipt in receipts(at: now) { ends[receipt.id] = receipt.end }
        for occurrence in occurrences {
            ends[occurrence.id] = occurrence.end
        }
        var values: [Receipt] = ends.map { Receipt(id: $0.key, end: $0.value) }
        values.sort { left, right in
            if left.end == right.end { return left.id < right.id }
            return left.end > right.end
        }
        if let data = try? JSONEncoder().encode(Array(values.prefix(2_048))) {
            defaults.set(data, forKey: key)
        }
    }

    private func receipts(at now: Date) -> [Receipt] {
        guard let data = defaults.data(forKey: key), data.count <= 2_000_000,
              let values = try? JSONDecoder().decode([Receipt].self, from: data) else { return [] }
        return values.filter { $0.end.addingTimeInterval(7 * 86_400) > now }
    }
}
