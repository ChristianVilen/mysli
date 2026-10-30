import XCTest
@testable import KuKa

@MainActor
final class CalendarReminderTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var settings: Settings!
    private var source: CalendarSourceFake!
    private var notices: CalendarNoticesFake!
    private var recorder: CalendarRecorderFake!
    private var driver: CalendarDriverFake!
    private var sut: CalendarReminderController!
    private var time = Date(timeIntervalSince1970: 10_000)

    override func setUp() async throws {
        suite = "CalendarReminderTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        settings = Settings(defaults: defaults)
        source = CalendarSourceFake()
        notices = CalendarNoticesFake()
        recorder = CalendarRecorderFake()
        driver = CalendarDriverFake()
        sut = makeController()
    }

    override func tearDown() async throws {
        sut.shutDown()
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeController() -> CalendarReminderController {
        CalendarReminderController(source: source, notifications: notices, recorder: recorder,
                                   driver: driver, settings: settings,
                                   store: CalendarReminderStore(defaults: defaults), now: { self.time })
    }

    private func event(_ item: String = "one", start: TimeInterval = 0, end: TimeInterval = 600,
                       original: Date? = nil) -> CalendarOccurrence {
        CalendarOccurrence(id: .init(calendar: "calendar", item: item, originalOccurrence: original),
                           title: "Planning", start: Date(timeIntervalSince1970: 10_000 + start),
                           end: Date(timeIntervalSince1970: 10_000 + end))
    }

    func testStartArrivesAtBoundaryOnlyOnceAcrossRefreshAndRestart() async {
        source.events = [event(start: 30)]
        await sut.setEnabled(true)
        XCTAssertTrue(notices.visible.isEmpty)
        XCTAssertEqual(driver.next, time.addingTimeInterval(30))
        time += 30
        await sut.refresh()
        XCTAssertEqual(notices.visible.map(\.kind), [.start])
        await sut.refresh()
        XCTAssertEqual(notices.added.count, 1)
        sut.shutDown()
        sut = makeController()
        await sut.resume()
        XCTAssertTrue(notices.visible.isEmpty)
        XCTAssertEqual(notices.added.count, 1)
    }

    func testWakeGraceAndEligibility() async {
        var allDay = event("allDay"); allDay.allDay = true
        var cancelled = event("cancelled"); cancelled.cancelled = true
        var declined = event("declined"); declined.declined = true
        var free = event("free"); free.free = true
        source.events = [allDay, cancelled, declined, free, event("zero", end: 0),
                         event("old", start: -121), event("ended", start: -20, end: -1),
                         event("grace", start: -120)]
        await sut.setEnabled(true)
        XCTAssertEqual(notices.visible.map(\.kind), [.start])
        let token = notices.visible.first?.token ?? UUID()
        time += 300
        await sut.handle(.start, token: token)
        XCTAssertEqual(recorder.titles, ["Planning"])
    }

    func testEditedStartCannotBeReplayedButDistinctRecurringOccurrenceCan() async {
        source.events = [event(original: Date(timeIntervalSince1970: 1))]
        await sut.setEnabled(true)
        let old = notices.visible.first?.token ?? UUID()
        source.events[0].title = "Changed"
        await sut.refresh()
        XCTAssertTrue(notices.visible.isEmpty)
        await sut.handle(.start, token: old)
        XCTAssertTrue(recorder.titles.isEmpty)
        source.events.append(event(original: Date(timeIntervalSince1970: 2)))
        await sut.refresh()
        XCTAssertEqual(notices.visible.map(\.title), ["Planning"])
    }

    func testSimultaneousAndStaggeredOverlapsAreConsumed() async {
        source.events = [event("b"), event("a"), event("later", start: 60)]
        await sut.setEnabled(true)
        XCTAssertEqual(notices.visible.count, 1)
        time += 60
        await sut.refresh()
        XCTAssertEqual(notices.added.count, 1)
        let token = notices.visible.first?.token ?? UUID()
        await sut.handle(.dismiss, token: token)
        await sut.refresh()
        XCTAssertTrue(notices.visible.isEmpty)
    }

    func testBusyRecorderConsumesStartsWithoutReplay() async {
        recorder.activeSessionID = UUID()
        source.events = [event()]
        await sut.setEnabled(true)
        XCTAssertTrue(notices.visible.isEmpty)
        recorder.activeSessionID = nil
        sut.recorderDidChange()
        await sut.refresh()
        XCTAssertTrue(notices.visible.isEmpty)
    }

    func testPausedEndContinueDoesNotResumeOrAskAgainAfterEdit() async {
        source.events = [event()]
        await sut.setEnabled(true)
        await sut.handle(.start, token: notices.visible.first?.token ?? UUID())
        recorder.paused = true
        time += 600
        await sut.refresh()
        XCTAssertEqual(notices.visible.map(\.kind), [.end])
        await sut.handle(.continueRecording, token: notices.visible.first?.token ?? UUID())
        XCTAssertTrue(recorder.paused)
        XCTAssertNotNil(recorder.activeSessionID)
        source.events[0].end += 100
        time += 100
        await sut.refresh()
        XCTAssertTrue(notices.visible.isEmpty)
    }

    func testStopChecksExactCurrentEndAndSession() async {
        source.events = [event()]
        await sut.setEnabled(true)
        await sut.handle(.start, token: notices.visible.first?.token ?? UUID())
        time += 600
        await sut.refresh()
        let old = notices.visible.first?.token ?? UUID()
        source.events[0].end += 100
        await sut.handle(.stop, token: old)
        XCTAssertNotNil(recorder.activeSessionID)
        time += 100
        await sut.refresh()
        XCTAssertEqual(notices.visible.map(\.kind), [.end])
        let moved = notices.visible.first?.token ?? UUID()
        recorder.activeSessionID = UUID()
        await sut.handle(.stop, token: moved)
        XCTAssertEqual(recorder.stops, 0)
    }

    func testDefaultOffAndSavedEnabledLaunchNeverPrompt() async {
        source.events = [event()]
        await sut.resume()
        XCTAssertEqual(sut.status, .off)
        XCTAssertTrue(notices.visible.isEmpty)
        settings.calendarRecordingRemindersEnabled = true
        await sut.resume()
        XCTAssertEqual(sut.status, .ready)
        XCTAssertEqual(source.prompts, 0)
        XCTAssertEqual(notices.prompts, 0)
        XCTAssertEqual(notices.visible.count, 1)
    }

    func testDefaultEndClickShowsControlsOnceWithoutRepeatedEndBanners() async {
        source.events = [event()]
        await sut.setEnabled(true)
        await sut.handle(.start, token: notices.visible.first?.token ?? UUID())
        time += 600
        await sut.refresh()
        await sut.handle(.showControls, token: notices.visible.first?.token ?? UUID())
        await sut.refresh()
        XCTAssertEqual(recorder.controlsShown, 1)
        XCTAssertEqual(recorder.stops, 0)
        XCTAssertTrue(notices.visible.isEmpty)
    }

    func testDeletionCancellationDeclineAndReadFailureSuppressEndWithoutStopping() async {
        for mode in 0..<4 {
            sut.shutDown()
            defaults.removeObject(forKey: "calendarRecordingReminderReceipts")
            recorder.activeSessionID = nil
            source.read = nil
            source.events = [event("event\(mode)")]
            sut = makeController()
            await sut.setEnabled(true)
            await sut.handle(.start, token: notices.visible.first?.token ?? UUID())
            time = Date(timeIntervalSince1970: 10_600)
            switch mode {
            case 0: source.events = []
            case 1: source.events[0].cancelled = true
            case 2: source.events[0].declined = true
            default: source.read = { throw NSError(domain: "read", code: 1) }
            }
            await sut.refresh()
            XCTAssertNotNil(recorder.activeSessionID, "mode \(mode)")
            XCTAssertTrue(notices.visible.isEmpty, "mode \(mode)")
            XCTAssertEqual(recorder.stops, 0)
            time = Date(timeIntervalSince1970: 10_000)
        }
    }

    func testFreshExactReadRejectsChangedStartWithoutStoreChangeSignal() async {
        source.events = [event()]
        await sut.setEnabled(true)
        let token = notices.visible.first?.token ?? UUID()
        source.events[0].title = "Changed"
        await sut.handle(.start, token: token)
        XCTAssertTrue(recorder.titles.isEmpty)
        XCTAssertTrue(notices.visible.isEmpty)
    }

    func testRecorderCallbackDuringAcceptedStartKeepsAssociationAndConsumesDoubleClick() async {
        source.events = [event()]
        await sut.setEnabled(true)
        let token = notices.visible.first?.token ?? UUID()
        recorder.duringStart = {
            self.sut.recorderDidChange()
            await self.sut.handle(.start, token: token)
            await self.sut.refresh()
        }
        await sut.handle(.start, token: token)
        XCTAssertEqual(driver.next, Date(timeIntervalSince1970: 10_600))
        time += 600
        await sut.refresh()
        XCTAssertEqual(recorder.titles, ["Planning"])
        XCTAssertEqual(notices.visible.map(\.kind), [.end])
        await sut.handle(.stop, token: notices.visible.first?.token ?? UUID())
        XCTAssertEqual(recorder.stops, 1)
        XCTAssertNil(recorder.activeSessionID)
    }

    func testEditDuringStartAwaitDoesNotAttachAnObsoleteAssociation() async {
        source.events = [event()]
        await sut.setEnabled(true)
        recorder.duringStart = { self.source.events = [] }
        await sut.handle(.start, token: notices.visible.first?.token ?? UUID())
        source.events = [event()]
        time += 600
        await sut.refresh()
        XCTAssertNotNil(recorder.activeSessionID)
        XCTAssertTrue(notices.visible.isEmpty)
    }

    func testDeniedAndRevokedPermissionsInvalidateActions() async {
        source.authorization = .denied
        await sut.setEnabled(true)
        XCTAssertEqual(sut.status, .calendarAccessRequired)
        XCTAssertEqual(notices.prompts, 0)
        source.authorization = .full
        notices.authorized = false
        await sut.refresh()
        XCTAssertEqual(sut.status, .notificationsRequired)
        notices.authorized = true
        source.events = [event()]
        await sut.refresh()
        let token = notices.visible.first?.token ?? UUID()
        source.authorization = .denied
        await sut.refresh()
        await sut.handle(.start, token: token)
        XCTAssertEqual(sut.status, .calendarAccessRequired)
        XCTAssertTrue(notices.visible.isEmpty)
        XCTAssertTrue(recorder.titles.isEmpty)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Continuation was not reached")
    }

    func testDisableDuringCalendarPermissionRequestDoesNotRequestNotifications() async {
        source.authorization = .notDetermined
        var answer: CheckedContinuation<Bool, Never>?
        source.request = { await withCheckedContinuation { answer = $0 } }
        let enabling = Task { await self.sut.setEnabled(true) }
        await waitUntil { answer != nil }
        await sut.setEnabled(false)
        source.authorization = .full
        answer?.resume(returning: true)
        await enabling.value
        XCTAssertFalse(settings.calendarRecordingRemindersEnabled)
        XCTAssertEqual(sut.status, .off)
        XCTAssertEqual(notices.prompts, 0)
        XCTAssertTrue(notices.visible.isEmpty)
    }

    func testLateNotificationAddAfterDisableIsRemoved() async {
        source.events = [event()]
        let center = CalendarCenterFake()
        let adapter = CalendarReminderNotifications(calls: center.calls)
        sut = CalendarReminderController(source: source, notifications: adapter, recorder: recorder,
            driver: driver, settings: settings, store: CalendarReminderStore(defaults: defaults), now: { self.time })
        var release: CheckedContinuation<Void, Never>?
        center.addWait = { await withCheckedContinuation { release = $0 } }
        let enabling = Task { await self.sut.setEnabled(true) }
        await waitUntil { release != nil }
        await sut.setEnabled(false)
        release?.resume()
        await enabling.value
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertTrue(center.pendingIDs.isEmpty)
        XCTAssertTrue(center.deliveredIDs.isEmpty)
        XCTAssertEqual(sut.status, .off)
    }

    func testNewRefreshDiscardsSuspendedSnapshot() async {
        var release: CheckedContinuation<[CalendarOccurrence], Error>?
        source.read = { try await withCheckedThrowingContinuation { release = $0 } }
        let enabling = Task { await self.sut.setEnabled(true) }
        await waitUntil { release != nil }
        source.read = nil
        source.events = []
        let refreshing = Task { await self.sut.refresh() }
        await Task.yield()
        release?.resume(returning: [event()])
        await enabling.value
        await refreshing.value
        XCTAssertTrue(notices.added.isEmpty)
        XCTAssertEqual(sut.status, .ready)
    }

    func testActionSuspendedAcrossDisableCannotStart() async {
        source.events = [event()]
        await sut.setEnabled(true)
        var release: CheckedContinuation<CalendarOccurrence?, Error>?
        source.exact = { try await withCheckedThrowingContinuation { release = $0 } }
        let token = notices.visible.first?.token ?? UUID()
        let action = Task { await self.sut.handle(.start, token: token) }
        await waitUntil { release != nil }
        await sut.setEnabled(false)
        release?.resume(returning: event())
        await action.value
        XCTAssertTrue(recorder.titles.isEmpty)
    }

    func testDeniedLaunchKeepsWatchingForPermissionGrantedInSettings() async {
        settings.calendarRecordingRemindersEnabled = true
        source.authorization = .denied
        await sut.resume()
        XCTAssertEqual(sut.status, .calendarAccessRequired)
        XCTAssertNotNil(driver.change)
        source.authorization = .full
        source.events = [event()]
        driver.change?()
        await sut.refresh()
        XCTAssertEqual(notices.visible.map(\.kind), [.start])
        XCTAssertEqual(source.prompts, 0)
    }

    func testEditedReceiptRetainsTheLastKnownEndAcrossRestart() async {
        source.events = [event()]
        await sut.setEnabled(true)
        source.events[0].end += 10 * 86_400
        await sut.refresh()
        sut.shutDown()
        time += 8 * 86_400
        source.events[0].start = time
        sut = makeController()
        await sut.resume()
        XCTAssertTrue(notices.visible.isEmpty)
    }

    func testEndActionSuspendedAcrossSessionReplacementCannotStopNewSession() async {
        source.events = [event()]
        await sut.setEnabled(true)
        await sut.handle(.start, token: notices.visible.first?.token ?? UUID())
        time += 600
        await sut.refresh()
        let token = notices.visible.first?.token ?? UUID()
        var release: CheckedContinuation<CalendarOccurrence?, Error>?
        source.exact = { try await withCheckedThrowingContinuation { release = $0 } }
        let action = Task { await self.sut.handle(.stop, token: token) }
        await waitUntil { release != nil }
        let replacement = UUID()
        recorder.activeSessionID = replacement
        release?.resume(returning: event())
        await action.value
        XCTAssertEqual(recorder.activeSessionID, replacement)
        XCTAssertEqual(recorder.stops, 0)
    }

    func testDisableDuringAsyncNotificationAuthorizationCannotOffer() async {
        source.events = [event()]
        var release: CheckedContinuation<Bool, Never>?
        notices.authorizationWait = { await withCheckedContinuation { release = $0 } }
        let enabling = Task { await self.sut.setEnabled(true) }
        await waitUntil { release != nil }
        await sut.setEnabled(false)
        release?.resume(returning: true)
        await enabling.value
        XCTAssertTrue(notices.visible.isEmpty)
        XCTAssertEqual(sut.status, .off)
    }

    func testContinueRechecksMovedEndBeforeSuppressingFutureReminder() async {
        source.events = [event()]
        await sut.setEnabled(true)
        await sut.handle(.start, token: notices.visible.first?.token ?? UUID())
        time += 600
        await sut.refresh()
        let old = notices.visible.first?.token ?? UUID()
        source.events[0].end += 100
        await sut.handle(.continueRecording, token: old)
        time += 100
        await sut.refresh()
        XCTAssertEqual(notices.visible.map(\.kind), [.end])
        XCTAssertEqual(recorder.titles, ["Planning"])
    }

    func testReceiptStorageIsBoundedExpiresAndContainsNoTitles() {
        let store = CalendarReminderStore(defaults: defaults)
        let events = (0..<2_049).map { event("item\($0)", end: TimeInterval($0 + 1)) }
        store.consume(events, at: time)
        XCTAssertEqual(store.consumed(at: time).count, 2_048)
        XCTAssertFalse(store.consumed(at: time).contains(event("item0").id))
        let data = defaults.data(forKey: "calendarRecordingReminderReceipts")!
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Planning"))
        XCTAssertTrue(store.consumed(at: time.addingTimeInterval(7 * 86_400 + 2_049)).isEmpty)
    }

    func testTitleOnlyEditInvalidatesEndActionWithoutAnotherEndBanner() async {
        source.events = [event()]
        await sut.setEnabled(true)
        await sut.handle(.start, token: notices.visible.first?.token ?? UUID())
        time += 600
        await sut.refresh()
        let token = notices.visible.first?.token ?? UUID()
        source.events[0].title = "Renamed"
        await sut.refresh()
        await sut.handle(.stop, token: token)
        XCTAssertEqual(notices.added.map(\.kind), [.start, .end])
        XCTAssertTrue(notices.visible.isEmpty)
        XCTAssertNotNil(recorder.activeSessionID)
    }

    func testRevocationDuringStartInvalidatesAssociationEvenIfAccessReturns() async {
        source.events = [event()]
        await sut.setEnabled(true)
        recorder.duringStart = {
            self.source.authorization = .denied
            await self.sut.refresh()
            self.source.authorization = .full
        }
        await sut.handle(.start, token: notices.visible.first?.token ?? UUID())
        time += 600
        await sut.refresh()
        XCTAssertEqual(recorder.titles, ["Planning"])
        XCTAssertNotNil(recorder.activeSessionID)
        XCTAssertTrue(notices.visible.isEmpty)
    }

    func testUnchangedRefreshDuringPostStartReadKeepsEndReminder() async {
        source.events = [event()]
        await sut.setEnabled(true)
        var reads = 0
        var release: CheckedContinuation<CalendarOccurrence?, Error>?
        source.exact = {
            reads += 1
            if reads == 2 {
                return try await withCheckedThrowingContinuation { release = $0 }
            }
            return self.event()
        }
        let token = notices.visible.first?.token ?? UUID()
        let action = Task { await self.sut.handle(.start, token: token) }
        await waitUntil { release != nil }
        await sut.refresh()
        release?.resume(returning: event())
        await action.value
        XCTAssertEqual(driver.next, Date(timeIntervalSince1970: 10_600))
        time += 600
        await sut.refresh()
        XCTAssertEqual(notices.added.map(\.kind), [.start, .end])
        await sut.handle(.stop, token: notices.visible.first?.token ?? UUID())
        XCTAssertNil(recorder.activeSessionID)
        XCTAssertEqual(recorder.stops, 1)
    }

    func testStalePostStartExactReadCannotRestoreDeletedAssociation() async {
        source.events = [event()]
        await sut.setEnabled(true)
        var reads = 0
        var release: CheckedContinuation<CalendarOccurrence?, Error>?
        source.exact = {
            reads += 1
            if reads == 1 { return self.event() }
            if reads == 2 {
                return try await withCheckedThrowingContinuation { release = $0 }
            }
            return self.source.events.first
        }
        let token = notices.visible.first?.token ?? UUID()
        let action = Task { await self.sut.handle(.start, token: token) }
        await waitUntil { release != nil }
        source.events = []
        await sut.refresh()
        source.exact = nil
        source.events = [event()]
        release?.resume(returning: event())
        await action.value
        source.events = [event()]
        time += 600
        await sut.refresh()
        XCTAssertEqual(recorder.titles, ["Planning"])
        XCTAssertTrue(notices.visible.isEmpty)
    }
}

@MainActor
private final class CalendarSourceFake: CalendarEventSource {
    var authorization: CalendarAccess = .full
    var events: [CalendarOccurrence] = []
    var prompts = 0
    var request: (() async -> Bool)?
    var read: (() async throws -> [CalendarOccurrence])?
    var exact: (() async throws -> CalendarOccurrence?)?
    func requestAccess() async -> Bool {
        prompts += 1
        return await request?() ?? (authorization == .full)
    }
    func occurrences(from: Date, to: Date) async throws -> [CalendarOccurrence] {
        if let read { return try await read() }
        return events
    }
    func occurrence(id: CalendarOccurrence.ID) async throws -> CalendarOccurrence? {
        if let exact { return try await exact() }
        return events.first { $0.id == id }
    }
}

@MainActor
private final class CalendarNoticesFake: CalendarReminderNotifying {
    var authorized = true
    var prompts = 0
    var added: [CalendarReminder] = []
    var visible: [CalendarReminder] = []
    var authorizationWait: (() async -> Bool)?
    func authorizationGranted() async -> Bool { await authorizationWait?() ?? authorized }
    func requestAccess() async -> Bool { prompts += 1; return authorized }
    func add(_ reminder: CalendarReminder) async throws {
        added.append(reminder)
        visible.append(reminder)
    }
    func cancel(tokens: [UUID]) { visible.removeAll { tokens.contains($0.token) } }
}

@MainActor
private final class CalendarRecorderFake: CalendarReminderRecording {
    var activeSessionID: UUID?
    var titles: [String] = []
    var stops = 0
    var paused = false
    var controlsShown = 0
    func showControls() { controlsShown += 1 }
    var duringStart: (() async -> Void)?
    func startRecording(title: String?) async -> UUID? {
        guard activeSessionID == nil else { return nil }
        let id = UUID()
        activeSessionID = id
        titles.append(title ?? "")
        await duringStart?()
        return activeSessionID == id ? id : nil
    }
    func stopRecording(ifSession id: UUID) {
        guard activeSessionID == id else { return }
        stops += 1
        activeSessionID = nil
    }
}

@MainActor
private final class CalendarDriverFake: CalendarReminderDriving {
    var next: Date?
    var change: (@MainActor () -> Void)?
    func start(onChange: @escaping @MainActor () -> Void) { change = onChange }
    func schedule(at: Date?) { next = at }
    func stop() { next = nil; change = nil }
}
