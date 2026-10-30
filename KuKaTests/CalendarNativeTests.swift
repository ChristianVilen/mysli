import XCTest
import EventKit
import UserNotifications
@testable import KuKa

@MainActor
final class CalendarNativeTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 10_000)

    private func fields(original: Date? = nil, recurring: Bool = false) -> CalendarEventFields {
        CalendarEventFields(calendar: "work", item: "series", originalOccurrence: original,
                            recurring: recurring, source: "synthetic", title: "Planning", start: date, end: date.addingTimeInterval(600))
    }

    func testNormalizationPreservesOriginalRecurrenceAndEligibility() {
        var event = fields(original: date.addingTimeInterval(-86_400), recurring: true)
        event.allDay = true
        event.cancelled = true
        event.declined = true
        event.free = true
        let value = event.occurrence
        XCTAssertEqual(value.id.originalOccurrence, Date(timeIntervalSince1970: -76_400))
        XCTAssertEqual(value.title, "Planning")
        XCTAssertTrue(value.allDay && value.cancelled && value.declined && value.free)
        XCTAssertFalse(value.eligible)
        event.recurring = false
        XCTAssertNil(event.occurrence.id.originalOccurrence)
    }

    func testSyntheticBeforeAfterEvidenceUsesRealRequestsAndGeneratedDocuments() async throws {
        let center = CalendarCenterFake()
        let adapter = CalendarReminderNotifications(calls: center.calls)
        let token = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        try await adapter.add(.init(token: token, kind: .start, title: "Planning"))
        try await adapter.add(.init(token: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                                    kind: .end, title: "Planning"))
        let folder = try MeetingFolder.create(in: makeTemporaryDirectory(), startingAt: localDate(2026, 10, 23, 14, 2))
        let before = SummaryDocument.markdown(title: folder.title, body: "Ship on Friday.")
        try folder.saveDisplayTitle("Planning")
        let after = SummaryDocument.markdown(title: folder.title, body: "Ship on Friday.")
        let transcript = Transcript.markdown([], title: folder.title, duration: 60, by: "Synthetic", after: [], rooms: .notDiarized,
                                             teams: .empty)
        try folder.write(after, to: .summary)
        try folder.write(transcript, to: .transcript)
        XCTAssertEqual(before, "# Meeting on 2026-10-23 at 14:02\n\nShip on Friday.\n")
        XCTAssertEqual(try String(contentsOf: folder.url(for: .summary), encoding: .utf8), "# Planning\n\nShip on Friday.\n")
        XCTAssertTrue(try String(contentsOf: folder.url(for: .transcript), encoding: .utf8).hasPrefix("# Planning\n"))
        let payload = center.requests.map { request in
            "\(request.identifier)\n\(request.content.categoryIdentifier)\n\(request.content.title)\n\(request.content.body)\n\(request.content.userInfo)"
        }.joined(separator: "\n\n")
        let evidence = XCTAttachment(string: "Synthetic native requests\n\(payload)\n\nBefore notes\n\(before)\nAfter notes\n\(after)\nTranscript\n\(transcript)")
        evidence.name = "calendar-reminder-synthetic-evidence"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    func testReadAuthorizationNeverRequestsAccessAndFullAccessIsRequired() async throws {
        var status: EKAuthorizationStatus = .notDetermined
        var requests = 0
        let source = EventKitCalendarSource(calls: .init(authorization: { status }, requestAccess: {
            requests += 1
            status = .fullAccess
            return true
        }, events: { _, _ in [self.fields()] }, item: { _ in self.fields() }))
        XCTAssertEqual(source.authorization, .notDetermined)
        status = .writeOnly
        XCTAssertEqual(source.authorization, .denied)
        do {
            _ = try await source.occurrences(from: date, to: date.addingTimeInterval(86_400))
            XCTFail("Write-only access must not read events")
        } catch {}
        XCTAssertEqual(requests, 0)
        status = .notDetermined
        let granted = await source.requestAccess()
        XCTAssertTrue(granted)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(source.authorization, .full)
        let events = try await source.occurrences(from: date, to: date.addingTimeInterval(86_400))
        XCTAssertEqual(events.map(\.title), ["Planning"])
    }

    func testExactReadFindsLaterAndDetachedOccurrenceWithoutReturningFirst() async throws {
        let first = fields(original: date, recurring: true)
        var later = fields(original: date.addingTimeInterval(86_400), recurring: true)
        later.start = date.addingTimeInterval(172_800)
        later.end = later.start.addingTimeInterval(600)
        let source = EventKitCalendarSource(calls: .init(authorization: { .fullAccess }, requestAccess: { true },
            events: { _, _ in [first, later] }, item: { _ in first }))
        let events = try await source.occurrences(from: date, to: date.addingTimeInterval(259_200))
        XCTAssertEqual(events.count, 2)
        let resolved = try await source.occurrence(id: later.occurrence.id)
        XCTAssertEqual(resolved?.start, Date(timeIntervalSince1970: 182_800))
        XCTAssertEqual(resolved?.id.originalOccurrence, Date(timeIntervalSince1970: 96_400))
    }

    func testNonrecurringTimeEditKeepsIdentityAndReturnsFreshSnapshot() async throws {
        var event = fields(original: date)
        let source = EventKitCalendarSource(calls: .init(authorization: { .fullAccess }, requestAccess: { true },
            events: { _, _ in [event] }, item: { _ in event }))
        let old = try await source.occurrences(from: date, to: date.addingTimeInterval(86_400))
        event.start = date.addingTimeInterval(900)
        let fresh = try await source.occurrence(id: fields().occurrence.id)
        XCTAssertEqual(old.first?.id, fresh?.id)
        XCTAssertEqual(fresh?.start, Date(timeIntervalSince1970: 10_900))
    }

    func testUnambiguousCalendarMoveKeepsCanonicalIdentityButDuplicateCopiesStaySeparate() async throws {
        var event = fields()
        event.external = "provider-event"
        var events = [event]
        let source = EventKitCalendarSource(calls: .init(authorization: { .fullAccess }, requestAccess: { true },
            events: { _, _ in events }, item: { id in events.first { $0.item == id } }))
        let initial = try await source.occurrences(from: date, to: date.addingTimeInterval(86_400))
        event.calendar = "personal"
        event.item = "new-local-id"
        events = [event]
        let moved = try await source.occurrences(from: date, to: date.addingTimeInterval(86_400))
        XCTAssertEqual(moved.first?.id, initial.first?.id)
        XCTAssertEqual(moved.first?.title, "Planning")
        var duplicate = event
        duplicate.calendar = "copy"
        duplicate.item = "copy-id"
        events.append(duplicate)
        let copies = try await source.occurrences(from: date, to: date.addingTimeInterval(86_400))
        XCTAssertEqual(Set(copies.map(\.id)).count, 2)
        let unsafe = try await source.occurrence(id: fields().occurrence.id)
        XCTAssertNil(unsafe)
        events = [event]
        let partial = try await source.occurrences(from: date, to: date.addingTimeInterval(60))
        XCTAssertEqual(partial.first?.id.calendar, "personal")
        let stillUnsafe = try await source.occurrence(id: fields().occurrence.id)
        XCTAssertNil(stillUnsafe)
    }

    func testPartialSnapshotCannotMergeALiveCopyOrAnEventFromAnotherSource() async throws {
        var first = fields()
        first.external = "provider-event"
        var second = first
        second.calendar = "copy"
        second.item = "copy-item"
        var query = [first]
        var items = [first, second]
        let source = EventKitCalendarSource(calls: .init(authorization: { .fullAccess }, requestAccess: { true },
            events: { _, _ in query }, item: { id in items.first { $0.item == id } }))
        let original = try await source.occurrences(from: date, to: date.addingTimeInterval(60))
        query = [second]
        let copy = try await source.occurrences(from: date, to: date.addingTimeInterval(60))
        XCTAssertEqual(original.first?.id.calendar, "work")
        XCTAssertEqual(copy.first?.id.calendar, "copy")
        let exactOriginal = try await source.occurrence(id: first.occurrence.id)
        let exactCopy = try await source.occurrence(id: second.occurrence.id)
        XCTAssertEqual(exactOriginal?.id.calendar, "work")
        XCTAssertEqual(exactCopy?.id.calendar, "copy")
        second.source = "another-account"
        second.item = "account-item"
        items = [second]
        query = [second]
        let otherAccount = try await source.occurrences(from: date, to: date.addingTimeInterval(60))
        XCTAssertEqual(otherAccount.first?.id.item, "account-item")
    }

    func testExternalAliasNeverCrossesCalendarAccounts() async throws {
        var event = fields()
        event.external = "same-provider-id"
        var query = [event]
        let source = EventKitCalendarSource(calls: .init(authorization: { .fullAccess }, requestAccess: { true },
            events: { _, _ in query }, item: { _ in nil }))
        _ = try await source.occurrences(from: date, to: date.addingTimeInterval(60))
        event.source = "another-account"
        event.item = "other-account-item"
        query = [event]
        let other = try await source.occurrences(from: date, to: date.addingTimeInterval(60))
        XCTAssertEqual(other.first?.id.item, "other-account-item")
    }

    func testLateNativeAddIsRemovedAfterTokenInvalidation() async throws {
        let center = CalendarCenterFake()
        var continuation: CheckedContinuation<Void, Never>?
        center.addWait = { await withCheckedContinuation { continuation = $0 } }
        let adapter = CalendarReminderNotifications(calls: center.calls)
        let token = UUID()
        let operation = Task { try await adapter.add(.init(token: token, kind: .start, title: "Planning")) }
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        XCTAssertNotNil(continuation)
        adapter.cancel(tokens: [token])
        continuation?.resume()
        try await operation.value
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertTrue(center.pendingIDs.isEmpty)
        XCTAssertTrue(center.deliveredIDs.isEmpty)
        XCTAssertEqual(center.removedPending.filter { $0 == "calendar-recording.\(token.uuidString)" }.count, 2)
        XCTAssertEqual(center.removedDelivered.filter { $0 == "calendar-recording.\(token.uuidString)" }.count, 2)
    }

    func testFailedNativeAddRemovesPartiallyAddedRequest() async {
        let center = CalendarCenterFake()
        center.addFailure = NSError(domain: "test", code: 1)
        let adapter = CalendarReminderNotifications(calls: center.calls)
        let token = UUID()
        do {
            try await adapter.add(.init(token: token, kind: .start, title: "Planning"))
            XCTFail("The native add must fail")
        } catch {}
        XCTAssertTrue(center.pendingIDs.isEmpty)
        XCTAssertTrue(center.deliveredIDs.isEmpty)
    }

    func testCancellationDuringPreparationNeverAddsRequest() async throws {
        let center = CalendarCenterFake()
        var release: CheckedContinuation<Void, Never>?
        center.prepareWait = { await withCheckedContinuation { release = $0 } }
        let adapter = CalendarReminderNotifications(calls: center.calls)
        let token = UUID()
        let operation = Task { try await adapter.add(.init(token: token, kind: .start, title: "Planning")) }
        for _ in 0..<100 where release == nil { await Task.yield() }
        XCTAssertNotNil(release)
        adapter.cancel(tokens: [token])
        release?.resume()
        try await operation.value
        XCTAssertTrue(center.requests.isEmpty)
    }

    func testNativeRequestsAndCategoriesContainOnlyTokenAndSafeActions() async throws {
        let center = CalendarCenterFake()
        let adapter = CalendarReminderNotifications(calls: center.calls)
        let token = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        try await adapter.add(.init(token: token, kind: .start, title: "Planning"))
        let request = try XCTUnwrap(center.requests.first)
        XCTAssertEqual(request.identifier, "calendar-recording.11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(request.content.title, "Planning")
        XCTAssertEqual(request.content.userInfo as? [String: String], ["calendarToken": token.uuidString])
        XCTAssertNil(request.trigger)
        XCTAssertEqual(center.registered.first { $0.identifier == "calendar-recording.start" }?.actions.map(\.title),
                       ["Start Recording"])
        XCTAssertEqual(center.registered.first { $0.identifier == "calendar-recording.end" }?.actions.map(\.title),
                       ["Stop Recording", "Continue Recording"])
        XCTAssertTrue(center.registered.contains { $0.identifier == "other" })
        let end = UUID()
        try await adapter.add(.init(token: end, kind: .end, title: "Planning"))
        XCTAssertEqual(center.requests.last?.content.categoryIdentifier, "calendar-recording.end")
    }

    func testDecodeSeparatesStartEndDefaultDismissAndUnknownActions() {
        let token = UUID()
        let info: [String: String] = ["calendarToken": token.uuidString]
        let cases: [(String, String, CalendarReminderAction?)] = [
            ("calendar-recording.start", "calendar-recording.start-recording", .start),
            ("calendar-recording.end", "calendar-recording.stop-recording", .stop),
            ("calendar-recording.end", "calendar-recording.continue-recording", .continueRecording),
            ("calendar-recording.start", UNNotificationDefaultActionIdentifier, .dismiss),
            ("calendar-recording.end", UNNotificationDefaultActionIdentifier, .showControls),
            ("calendar-recording.end", UNNotificationDismissActionIdentifier, .dismiss),
            ("calendar-recording.start", "calendar-recording.stop-recording", nil),
            ("other", UNNotificationDefaultActionIdentifier, nil),
            ("calendar-recording.end", "unknown", nil)
        ]
        for (category, action, expected) in cases {
            let decoded = CalendarReminderNotifications.decode(category: category, action: action, userInfo: info)
            XCTAssertEqual(decoded?.action, expected)
            if expected != nil { XCTAssertEqual(decoded?.token, token) }
        }
        XCTAssertNil(CalendarReminderNotifications.decode(category: "calendar-recording.start",
            action: "calendar-recording.start-recording", userInfo: ["calendarToken": "bad"]))
    }

    func testSingleDelegateRoutesCalendarWithoutTakingOverExistingClicks() async {
        var received: [(CalendarReminderAction, UUID)] = []
        var opened: [URL] = []
        let notifier = SystemNotifier(open: { opened.append($0) })
        notifier.onCalendarReminder = { received.append(($0, $1)) }
        let token = UUID()
        let handled = await notifier.routeCalendarReminder(category: "calendar-recording.end",
            action: "calendar-recording.stop-recording", userInfo: ["calendarToken": token.uuidString])
        XCTAssertTrue(handled)
        XCTAssertEqual(received.first?.0, .stop)
        XCTAssertEqual(received.first?.1, token)
        notifier.perform(.open(URL(fileURLWithPath: "/synthetic/summary.md")))
        XCTAssertEqual(opened, [URL(fileURLWithPath: "/synthetic/summary.md")])
    }

    func testNotificationResponseCompletesOnlyAfterAsyncActionFinishes() async {
        let notifier = SystemNotifier(open: { _ in })
        var continuation: CheckedContinuation<Void, Never>?
        var completed = false
        notifier.onCalendarReminder = { _, _ in await withCheckedContinuation { continuation = $0 } }
        let operation = Task {
            await notifier.handleResponse(category: "calendar-recording.end", action: "calendar-recording.stop-recording",
                userInfo: ["calendarToken": UUID().uuidString], completion: { completed = true })
        }
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        XCTAssertNotNil(continuation)
        XCTAssertFalse(completed)
        continuation?.resume()
        await operation.value
        XCTAssertTrue(completed)
    }

    func testStartupAndTokenRemovalLeaveUnrelatedNotificationsAlone() async throws {
        let center = CalendarCenterFake()
        center.pendingIDs = ["other", "calendar-recording.old-pending"]
        center.deliveredIDs = ["notes", "calendar-recording.old-delivered"]
        let adapter = CalendarReminderNotifications(calls: center.calls)
        await adapter.prepare()
        XCTAssertEqual(center.removedPending, ["calendar-recording.old-pending"])
        XCTAssertEqual(center.removedDelivered, ["calendar-recording.old-delivered"])
        let token = UUID()
        try await adapter.add(.init(token: token, kind: .start, title: "Planning"))
        adapter.cancel(tokens: [token])
        XCTAssertEqual(center.removedPending.last, "calendar-recording.\(token.uuidString)")
        XCTAssertEqual(center.removedDelivered.last, "calendar-recording.\(token.uuidString)")
    }

    func testDriverReplacesBoundaryAndCancelsSignalsOnStop() {
        var timers: [(Date, TimeInterval, @MainActor () -> Void)] = []
        var cancellations = 0
        var signal: (@MainActor () -> Void)?
        var changes = 0
        let driver = CalendarReminderDriver(calls: .init(observe: {
            signal = $0
            return { signal = nil; cancellations += 1 }
        }, timer: { date, interval, action in
            timers.append((date, interval, action))
            return { cancellations += 1 }
        }, now: { self.date }))
        driver.start { changes += 1 }
        XCTAssertEqual(timers.first?.0, Date(timeIntervalSince1970: 10_060))
        XCTAssertEqual(timers.first?.1, 60)
        signal?()
        timers.first?.2()
        XCTAssertEqual(changes, 2)
        driver.schedule(at: date.addingTimeInterval(10))
        XCTAssertEqual(timers.last?.0, Date(timeIntervalSince1970: 10_010))
        XCTAssertEqual(timers.last?.1, 0)
        driver.schedule(at: date.addingTimeInterval(20))
        XCTAssertEqual(cancellations, 1)
        driver.schedule(at: nil)
        XCTAssertEqual(cancellations, 2)
        driver.stop()
        XCTAssertNil(signal)
        XCTAssertEqual(cancellations, 4)
    }
}

@MainActor
final class CalendarCenterFake {
    var requests: [UNNotificationRequest] = []
    var registered: Set<UNNotificationCategory> = []
    var pendingIDs: [String] = []
    var deliveredIDs: [String] = []
    var removedPending: [String] = []
    var removedDelivered: [String] = []
    var addWait: (() async -> Void)?
    var prepareWait: (() async -> Void)?
    var addFailure: Error?
    var calls: CalendarReminderNotifications.Calls {
        .init(authorized: { true }, requestAccess: { true }, categories: {
            await self.prepareWait?()
            return [UNNotificationCategory(identifier: "other", actions: [], intentIdentifiers: [])]
        }, setCategories: { self.registered = $0 }, pending: { self.pendingIDs }, delivered: { self.deliveredIDs },
        add: { request in
            await self.addWait?()
            self.requests.append(request)
            self.pendingIDs.append(request.identifier)
            self.deliveredIDs.append(request.identifier)
            if let error = self.addFailure { throw error }
        }, removePending: { ids in
            self.removedPending += ids
            self.pendingIDs.removeAll { ids.contains($0) }
        }, removeDelivered: { ids in
            self.removedDelivered += ids
            self.deliveredIDs.removeAll { ids.contains($0) }
        })
    }
}
