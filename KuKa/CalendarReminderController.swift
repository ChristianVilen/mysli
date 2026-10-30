import Foundation

@MainActor
final class CalendarReminderController {
    enum Status: Equatable {
        case off, requestingAccess, ready, calendarAccessRequired, notificationsRequired, readFailed
    }

    private(set) var status: Status = .off
    var onStatusChange: (() -> Void)?

    private let source: CalendarEventSource
    private let notifications: CalendarReminderNotifying
    private let recorder: CalendarReminderRecording
    private let driver: CalendarReminderDriving
    private let settings: Settings
    private let store: CalendarReminderStore
    private let now: () -> Date
    private struct Offer {
        enum Kind {
            case start(CalendarOccurrence)
            case end(CalendarOccurrence, session: UUID)
        }
        let token: UUID
        let kind: Kind
        var claimed = false
        var event: CalendarOccurrence {
            switch kind { case .start(let event), .end(let event, _): event }
        }
        var session: UUID? {
            switch kind { case .start: nil; case .end(_, let session): session }
        }
    }
    private enum EndReminder: Equatable { case waiting, offered(Date), continued }
    private struct Association {
        var event: CalendarOccurrence
        let session: UUID
        var endReminder: EndReminder = .waiting
    }
    private enum RecordingLink {
        case validating(CalendarOccurrence, session: UUID), associated(Association)
        var event: CalendarOccurrence {
            switch self { case .validating(let event, _): event; case .associated(let link): link.event }
        }
        var session: UUID {
            switch self { case .validating(_, let session): session; case .associated(let link): link.session }
        }
    }
    private var offer: Offer?
    private var recordingLink: RecordingLink?
    private var enabled = false
    private var generation = UUID()
    private var worker: Task<Void, Never>?
    private var refreshRevision = 0
    private var dirty = false

    init(source: CalendarEventSource, notifications: CalendarReminderNotifying,
         recorder: CalendarReminderRecording, driver: CalendarReminderDriving,
         settings: Settings, store: CalendarReminderStore, now: @escaping () -> Date = Date.init) {
        self.source = source
        self.notifications = notifications
        self.recorder = recorder
        self.driver = driver
        self.settings = settings
        self.store = store
        self.now = now
    }

    func setEnabled(_ enabled: Bool) async {
        settings.calendarRecordingRemindersEnabled = enabled
        reset()
        self.enabled = enabled
        guard enabled else { setStatus(.off); return }
        let stamp = generation
        setStatus(.requestingAccess)
        _ = await source.requestAccess()
        guard valid(stamp) else { return }
        guard source.authorization == .full else {
            watch()
            setStatus(.calendarAccessRequired)
            return
        }
        _ = await notifications.requestAccess()
        guard valid(stamp) else { return }
        await activate()
    }

    func resume() async {
        reset()
        enabled = settings.calendarRecordingRemindersEnabled
        guard enabled else { setStatus(.off); return }
        await activate()
    }

    private func activate() async {
        watch()
        guard await accessIsReady(generation) else { return }
        await refresh()
    }

    private func watch() {
        driver.start { [weak self] in
            guard let self else { return }
            Task { await self.refresh() }
        }
    }

    func refresh() async {
        guard enabled else { return }
        refreshRevision += 1
        dirty = true
        if let worker { await worker.value; return }
        let task = Task { [weak self] in
            guard let self else { return }
            while self.dirty && self.enabled {
                self.dirty = false
                await self.reconcile()
            }
            self.worker = nil
        }
        worker = task
        await task.value
    }

    private func reconcile() async {
        let stamp = generation
        guard await accessIsReady(stamp) else { return }
        let revision = refreshRevision
        do {
            let date = now()
            let events = try await source.occurrences(from: date.addingTimeInterval(-120),
                                                      to: date.addingTimeInterval(86_400))
            guard valid(stamp), revision == refreshRevision, await accessIsReady(stamp),
                  revision == refreshRevision else { return }
            var associatedEvent: CalendarOccurrence?
            if let event = recordingLink?.event {
                associatedEvent = try await source.occurrence(id: event.id)
                guard valid(stamp), revision == refreshRevision, await accessIsReady(stamp),
                      revision == refreshRevision else { return }
            }
            reconcileRecorder()
            if case .validating(let event, _) = recordingLink, associatedEvent != event {
                recordingLink = nil
            }
            if case .associated(var link) = recordingLink {
                if let event = associatedEvent, event.eligible {
                    link.event = event
                    recordingLink = .associated(link)
                } else {
                    recordingLink = nil
                }
            }
            let current = now()
            invalidate { item in
                switch item.kind {
                case .end(let event, let session):
                    guard case .associated(let link) = recordingLink else { return true }
                    return link.session != session || link.event != event
                        || link.endReminder == .continued || event.end > current
                case .start(let event):
                    return recorder.activeSessionID != nil || event.end <= current
                        || !events.contains(event) || !event.eligible
                }
            }
            let consumed = store.consumed(at: current)
            let due = events.filter {
                $0.eligible && $0.start <= current && $0.start >= current.addingTimeInterval(-120)
                    && $0.end > current && !consumed.contains($0.id)
            }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
            let canOffer = recorder.activeSessionID == nil && offer == nil
            store.consume(due + events.filter { consumed.contains($0.id) }, at: current)
            if canOffer, let event = due.first {
                await post(.start(event))
            }
            guard valid(stamp), revision == refreshRevision, await accessIsReady(stamp),
                  revision == refreshRevision else { return }
            if case .associated(var link) = recordingLink, link.endReminder != .continued,
               link.endReminder != .offered(link.event.end), link.event.end <= now(), offer == nil {
                link.endReminder = .offered(link.event.end)
                recordingLink = .associated(link)
                await post(.end(link.event, session: link.session))
            }
            guard valid(stamp), revision == refreshRevision else { return }
            let future = events.filter { $0.eligible && $0.start > now() }.map(\.start)
            var end: Date?
            if case .associated(let link) = recordingLink, link.endReminder != .continued, link.event.end > now() {
                end = link.event.end
            }
            let offerEnd = offer.flatMap { $0.session == nil ? $0.event.end : nil }
            driver.schedule(at: (future + [offerEnd, end].compactMap { $0 }).min())
            setStatus(.ready)
        } catch {
            guard valid(stamp), revision == refreshRevision else { return }
            if case .validating = recordingLink { recordingLink = nil }
            invalidate { _ in true }
            driver.schedule(at: nil)
            setStatus(.readFailed)
        }
    }

    private func post(_ kind: Offer.Kind) async {
        let token = UUID()
        let item = Offer(token: token, kind: kind)
        offer = item
        let reminderKind: CalendarReminder.Kind
        switch kind { case .start: reminderKind = .start; case .end: reminderKind = .end }
        do {
            try await notifications.add(CalendarReminder(token: token, kind: reminderKind,
                                                         title: item.event.displayTitle))
        } catch {
            if offer?.token == token { offer = nil }
        }
    }

    func recorderDidChange() {
        reconcileRecorder()
        guard enabled else { return }
        Task { await self.refresh() }
    }

    private func reconcileRecorder() {
        if recordingLink?.session != recorder.activeSessionID { recordingLink = nil }
        invalidate { item in
            item.session.map { $0 != recorder.activeSessionID } ?? (recorder.activeSessionID != nil)
        }
    }

    func shutDown() {
        enabled = false
        reset()
        setStatus(.off)
    }

    private func reset() {
        generation = UUID()
        refreshRevision += 1
        dirty = false
        recordingLink = nil
        invalidate { _ in true }
        driver.stop()
    }

    private func valid(_ stamp: UUID) -> Bool { enabled && generation == stamp }

    private func accessIsReady(_ stamp: UUID) async -> Bool {
        guard valid(stamp) else { return false }
        if source.authorization != .full {
            accessRequired(.calendarAccessRequired)
            return false
        }
        let granted = await notifications.authorizationGranted()
        guard valid(stamp) else { return false }
        if source.authorization != .full {
            accessRequired(.calendarAccessRequired)
            return false
        }
        if !granted {
            accessRequired(.notificationsRequired)
            return false
        }
        return true
    }

    private func accessRequired(_ status: Status) {
        generation = UUID()
        recordingLink = nil
        invalidate { _ in true }
        driver.schedule(at: nil)
        setStatus(status)
    }

    private func setStatus(_ value: Status) {
        guard status != value else { return }
        status = value
        onStatusChange?()
    }

    private func invalidate(where predicate: (Offer) -> Bool) {
        guard let offer, predicate(offer) else { return }
        self.offer = nil
        notifications.cancel(tokens: [offer.token])
    }

    func handle(_ action: CalendarReminderAction, token: UUID) async {
        let stamp = generation
        guard enabled, var item = offer, item.token == token, !item.claimed else { return }
        item.claimed = true
        offer = item
        notifications.cancel(tokens: [token])
        guard await accessIsReady(stamp), offer?.token == token else { return }
        do {
            let event = try await source.occurrence(id: item.event.id)
            guard valid(stamp), await accessIsReady(stamp), offer?.token == token else { return }
            offer = nil
            guard event == item.event, item.event.eligible else { return }
            switch item.kind {
            case .end(_, let session):
                guard case .associated(var link) = recordingLink, link.session == session,
                      recorder.activeSessionID == session, item.event.end <= now(),
                      link.endReminder != .continued else { return }
                switch action {
                case .stop: recorder.stopRecording(ifSession: session); reconcileRecorder()
                case .continueRecording:
                    link.endReminder = .continued
                    recordingLink = .associated(link)
                case .showControls: recorder.showControls()
                default: break
                }
            case .start:
                guard action == .start, item.event.start <= now(), item.event.end > now(),
                      recorder.activeSessionID == nil else { return }
                let session = await recorder.startRecording(title: item.event.displayTitle)
                guard valid(stamp), await accessIsReady(stamp), let session,
                      recorder.activeSessionID == session else { return }
                recordingLink = .validating(item.event, session: session)
                defer {
                    if case .validating(_, let pending) = recordingLink, pending == session { recordingLink = nil }
                }
                let current = try await source.occurrence(id: item.event.id)
                guard valid(stamp), await accessIsReady(stamp), recorder.activeSessionID == session,
                      case .validating(_, let pending) = recordingLink, pending == session,
                      current == item.event else { return }
                recordingLink = .associated(Association(event: item.event, session: session))
                await refresh()
            }
        } catch {
            guard valid(stamp) else { return }
            invalidate { _ in true }
            setStatus(.readFailed)
        }
    }
}
