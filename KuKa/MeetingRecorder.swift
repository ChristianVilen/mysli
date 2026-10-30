import Cocoa

enum RecorderPhase: Equatable {
    case idle
    case starting
    case recording
    case paused

    /// The stream runs and the folder lock is held.
    var isCapturing: Bool { self == .recording || self == .paused }

    /// For the status item's accessibility label and tooltip. Nil when there is nothing to say.
    var statusDescription: String? {
        switch self {
        case .recording: return "recording meeting"
        case .paused: return "recording paused"
        case .idle, .starting: return nil
        }
    }

    var recordingMark: RecordingMark? {
        switch self {
        case .recording: return .recording
        case .paused: return .paused
        case .idle, .starting: return nil
        }
    }
}

/// Built on demand from recorder state; the panel keeps no copy.
struct MeetingControls: Equatable {
    enum Status: Equatable {
        case starting
        case recording
        case paused
        case saved
        case interrupted(reason: String)
    }

    let status: Status
    /// Recorded seconds. Nil outside a meeting.
    let recordedTime: TimeInterval?
    /// Nil while starting, after the meeting, and while the transcript is closed.
    let preview: LivePreview?

    var isTranscriptOpen: Bool { preview != nil }
}

/// One-shot requests from the recorder to the panel, for things that are not state.
enum MeetingControlsRequest: Equatable {
    /// Show Meeting Controls: make the panel key, so Tab reaches its buttons.
    case focus
    case restoreDefaultPosition
}

@MainActor
final class MeetingRecorder {
    private enum State {
        /// `notice` is what the panel says about the meeting that just ended, until it closes.
        case idle(notice: EndNotice?)
        case starting(Session)
        case active(ActiveMeeting)

        var phase: RecorderPhase {
            switch self {
            case .idle: return .idle
            case .starting: return .starting
            case .active(let meeting): return meeting.state.clock.isPaused ? .paused : .recording
            }
        }
    }

    private enum EndNotice {
        case saved(MeetingFolder)
        /// Stays until the user closes it, so the end of a recording is never missed.
        case interrupted(reason: String)
    }

    private struct Session {
        let id: UUID
        let title: String?
    }

    /// Dropped at Stop, interruption, or quit to release the folder lock and all live state.
    private struct ActiveMeeting {
        struct State: Equatable {
            /// The only clock that changes. `handle` gets a copy after each change.
            var clock: RecordingClock
            var live = LiveTranscript()
            var isHidden = false
            var isTranscriptOpen = false
        }

        let session: Session
        let folder: MeetingFolder
        let lock: FileLock
        let handle: ActiveRecording
        let liveTask: Task<Void, Never>
        let speakers: TeamsSpeakerRecording?
        var state: State
    }

    private let permissions: PermissionsManager
    private let root: () -> URL
    private let locale: () -> Locale
    private let capture: MeetingAudioCapturing
    private let liveTranscriber: LiveTranscribing
    private let teamsSpeakerNamesEnabled: () -> Bool
    private let teamsSpeakerObserver: any TeamsSpeakerObserving
    private let notifier: Notifying
    /// Returns true when the user chose Open Permissions.
    private let alertStartFailure: @MainActor (_ reason: String, _ offersPermissions: Bool) -> Bool
    private let now: () -> Date
    private let hostNow: () -> HostTime
    private let closeSavedNoticeLater: @MainActor (@escaping @MainActor () -> Void) -> Void

    private var state: State = .idle(notice: nil) {
        didSet {
            reconcileDisplayTimer()
            if oldValue.phase != state.phase { onChange?() }
            onControlsChange?()
        }
    }
    /// Runs only while recording; the displayed time stops while paused.
    private var displayTimer: Timer?

    /// Fires on every change of `phase`, Starting and quit included: what the menu and the
    /// status icon show. The menu reads the recorded time at each tick.
    var onChange: (() -> Void)?
    var onShowPermissions: (() -> Void)?
    /// A meeting stopped or was interrupted, so its notes can be made. A quit leaves the meeting
    /// for the next launch and calls nothing.
    var onEnded: ((RecordedMeeting) -> Void)?
    /// The meeting controls panel: anything it draws changed.
    var onControlsChange: (@MainActor () -> Void)?
    var onControlsRequest: (@MainActor (MeetingControlsRequest) -> Void)?

    var phase: RecorderPhase { state.phase }
    var activeSessionID: UUID? {
        switch state {
        case .idle: return nil
        case .starting(let session): return session.id
        case .active(let meeting): return meeting.session.id
        }
    }

    var displayTitle: String? {
        switch state {
        case .idle: return nil
        case .starting(let session): return session.title
        case .active(let meeting): return meeting.session.title
        }
    }

    func stopRecording(ifSession session: UUID) {
        guard activeSessionID == session else { return }
        stopRecording()
    }

    /// Nil outside a meeting. It stands still while paused.
    var recordedTime: TimeInterval? {
        guard case .active(let meeting) = state else { return nil }
        return meeting.state.clock.recordedTime(at: hostNow())
    }

    /// Nil when the panel is off screen.
    var controls: MeetingControls? {
        let status: MeetingControls.Status
        switch state {
        case .idle(nil):
            return nil
        case .idle(.saved?):
            status = .saved
        case .idle(.interrupted(let reason)?):
            status = .interrupted(reason: reason)
        case .starting:
            status = .starting
        case .active(let meeting):
            let current = meeting.state
            guard !current.isHidden else { return nil }
            return MeetingControls(status: current.clock.isPaused ? .paused : .recording,
                                   recordedTime: current.clock.recordedTime(at: hostNow()),
                                   preview: current.isTranscriptOpen ? current.live.preview(on: current.clock) : nil)
        }
        return MeetingControls(status: status, recordedTime: nil, preview: nil)
    }

    init(permissions: PermissionsManager,
         root: @escaping () -> URL,
         locale: @escaping () -> Locale = { Locale(identifier: "en-US") },
         capture: MeetingAudioCapturing = ScreenCaptureMeetingAudio(),
         liveTranscriber: LiveTranscribing = AppleLiveTranscriber(),
         teamsSpeakerNamesEnabled: @escaping () -> Bool = { false },
         teamsSpeakerObserver: any TeamsSpeakerObserving = TeamsSpeakerObserver(),
         notifier: Notifying = SystemNotifier.shared,
         alertStartFailure: @escaping @MainActor (String, Bool) -> Bool = MeetingRecorder.showStartFailureAlert,
         now: @escaping () -> Date = { Date() },
         hostNow: @escaping () -> HostTime = HostTime.now,
         closeSavedNoticeLater: @escaping @MainActor (@escaping @MainActor () -> Void) -> Void = MeetingRecorder.afterSixSeconds) {
        self.permissions = permissions
        self.root = root
        self.locale = locale
        self.capture = capture
        self.liveTranscriber = liveTranscriber
        self.teamsSpeakerNamesEnabled = teamsSpeakerNamesEnabled
        self.teamsSpeakerObserver = teamsSpeakerObserver
        self.notifier = notifier
        self.alertStartFailure = alertStartFailure
        self.now = now
        self.hostNow = hostNow
        self.closeSavedNoticeLater = closeSavedNoticeLater
    }

    isolated deinit {
        displayTimer?.invalidate()
        if case .active(let meeting) = state { meeting.speakers?.pause() }
    }

    /// The recording's audio levels, for the menu's meters. Nil outside a meeting.
    func audioLevels() -> RecordingAudioLevels? {
        guard case .active(let meeting) = state else { return nil }
        return meeting.handle.audioLevels()
    }

    func toggleRecording() async {
        switch state {
        case .idle: _ = await startRecording()
        case .active: stopRecording()
        case .starting: break
        }
    }

    func startRecording(title: String? = nil) async -> UUID? {
        guard case .idle = state else { return nil }
        let session = Session(id: UUID(), title: title.flatMap(MeetingTitle.normalized))
        let namesEnabled = teamsSpeakerNamesEnabled()
        state = .starting(session)
        notifier.requestPermission()
        let reason = await missingGrant()
        guard activeSessionID == session.id else { return nil }
        guard !Task.isCancelled else {
            state = .idle(notice: nil)
            return nil
        }
        if let reason {
            state = .idle(notice: nil)
            if alertStartFailure(reason, true) { onShowPermissions?() }
            return nil
        }
        do {
            let meeting = try MeetingFolder.create(in: root(), startingAt: now())
            do {
                let lock = try meeting.lock()
                if let title = session.title { try meeting.saveDisplayTitle(title) }
                // Read the origin just before starting capture to align both tracks and click times.
                let clock = RecordingClock(origin: hostNow())
                let handle = try await capture.start(into: meeting, clock: clock) { [weak self] reason in
                    self?.handleInterruption(of: meeting, reason: reason)
                }
                guard activeSessionID == session.id, !Task.isCancelled else {
                    handle.stop()
                    if activeSessionID == session.id {
                        state = .idle(notice: nil)
                    }
                    return nil
                }
                if let reason = handle.endReason {
                    endRecording(meeting, interruptedBecause: reason)
                } else {
                    Log.teams.notice(TeamsSpeakerRecording.startLine(enabled: namesEnabled,
                                                                     accessibilityGranted: permissions.accessibility))
                    let speakers = namesEnabled ? TeamsSpeakerRecording(observer: teamsSpeakerObserver) : nil
                    speakers?.resume(at: hostNow())
                    let updates = liveTranscriber.updates(locale: locale(), audio: handle.writtenAudio)
                    let liveTask = Task { [weak self] in
                        for await update in updates { self?.applyLive(update, to: meeting) }
                    }
                    state = .active(ActiveMeeting(session: session, folder: meeting, lock: lock, handle: handle,
                                                  liveTask: liveTask, speakers: speakers,
                                                  state: ActiveMeeting.State(clock: clock)))
                    return session.id
                }
            } catch {
                if meeting.stage() == nil { try? FileManager.default.removeItem(at: meeting.url) }
                throw error
            }
        } catch {
            guard activeSessionID == session.id else { return nil }
            state = .idle(notice: nil)
            guard !Task.isCancelled else { return nil }
            _ = alertStartFailure(error.localizedDescription, false)
        }
        return nil
    }

    private func missingGrant() async -> String? {
        permissions.refresh()
        guard permissions.screenRecording else {
            return "Ku-Ka needs Screen Recording permission to record the other people on the call."
        }
        guard permissions.microphone != .denied, await permissions.requestMicrophone() else {
            return "Ku-Ka needs Microphone permission to record your side of the call."
        }
        return nil
    }

    /// The one Stop, for the menu and the meeting controls. Never starts a meeting.
    func stopRecording() {
        guard case .active(let meeting) = state else { return }
        let speakers = meeting.speakers?.finish(clock: meeting.state.clock, endingAt: hostNow()) ?? .empty
        meeting.liveTask.cancel()
        // Not `meeting`: it holds the folder lock, which processing needs now.
        let folder = meeting.folder
        state = .idle(notice: .saved(folder))
        meeting.handle.stop()
        closeSavedNoticeLater { [weak self] in self?.closeNotice(ifSavedFor: folder) }
        onEnded?(RecordedMeeting(folder: folder, speakers: speakers))
    }

    private func closeNotice(ifSavedFor meeting: MeetingFolder) {
        guard case .idle(.saved(let saved)?) = state, saved == meeting else { return }
        state = .idle(notice: nil)
    }

    /// Quit: the recording stops, and the meeting waits for the next launch.
    func shutDown() {
        if case .active(let meeting) = state {
            meeting.speakers?.pause()
            meeting.liveTask.cancel()
            state = .idle(notice: nil)
            meeting.handle.stop()
            return
        }
        state = .idle(notice: nil)
    }

    func pause() {
        let time = hostNow()
        updateActive { state in
            guard state.clock.pause(at: time) else { return }
            if case .active(let meeting) = self.state { meeting.speakers?.pause() }
            state.live.settleTails()
        }
    }

    func resume() {
        let time = hostNow()
        updateActive {
            guard $0.clock.resume(at: time) else { return }
            if case .active(let meeting) = self.state { meeting.speakers?.resume(at: time) }
        }
    }

    func togglePause() {
        phase == .paused ? resume() : pause()
    }

    func setTranscriptOpen(_ isOpen: Bool) {
        updateActive { $0.isTranscriptOpen = isOpen }
    }

    func toggleTranscript() {
        updateActive { $0.isTranscriptOpen.toggle() }
    }

    /// The panel's Hide while recording, or its Close on a notice.
    func dismissControls() {
        switch state {
        case .active: updateActive { $0.isHidden = true }
        case .idle(_?): state = .idle(notice: nil)
        case .idle(nil), .starting: break
        }
    }

    func showControls() {
        updateActive { $0.isHidden = false }
        if controls != nil { onControlsRequest?(.focus) }
    }

    func restoreDefaultPosition() {
        onControlsRequest?(.restoreDefaultPosition)
    }

    /// The live task can already hold an update when Stop cancels it, and apply it once a
    /// later meeting is active. The folder check drops it.
    private func applyLive(_ update: LiveUpdate, to meeting: MeetingFolder) {
        updateActive(of: meeting) { $0.live.apply(update, now: hostNow(), clock: $0.clock) }
    }

    /// With `meeting`, only while it is the active meeting. A change that leaves the state as it
    /// was, such as a Pause the clock refuses, tells no one. A changed clock goes to the recording.
    private func updateActive(of meeting: MeetingFolder? = nil, _ change: (inout ActiveMeeting.State) -> Void) {
        guard case .active(var active) = state, meeting == nil || active.folder == meeting else { return }
        let before = active.state
        change(&active.state)
        guard active.state != before else { return }
        if active.state.clock != before.clock { active.handle.apply(active.state.clock) }
        state = .active(active)
    }

    private func handleInterruption(of meeting: MeetingFolder, reason: String) {
        guard case .active(let active) = state, active.folder == meeting else { return }
        let speakers = active.speakers?.finish(clock: active.state.clock, endingAt: hostNow()) ?? .empty
        active.liveTask.cancel()
        endRecording(meeting, interruptedBecause: reason, speakers: speakers)
    }

    private func endRecording(_ meeting: MeetingFolder, interruptedBecause reason: String,
                              speakers: TeamsSpeakerEvidence = .empty) {
        state = .idle(notice: .interrupted(reason: reason))
        notifier.post(title: "Recording Stopped", body: MeetingPanelCopy.interruptedNote(reason), onClick: nil)
        onEnded?(RecordedMeeting(folder: meeting, speakers: speakers))
    }

    private func reconcileDisplayTimer() {
        guard case .active(let meeting) = state, !meeting.state.clock.isPaused else {
            displayTimer?.invalidate()
            displayTimer = nil
            return
        }
        guard displayTimer == nil else { return }
        // The first tick comes on the next whole recorded second, so the shown seconds change on time.
        let recorded = meeting.state.clock.recordedTime(at: hostNow())
        let firstTick = Date().addingTimeInterval(1 - recorded.truncatingRemainder(dividingBy: 1))
        let timer = Timer(fire: firstTick, interval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onControlsChange?() }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    static func afterSixSeconds(_ work: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: 6, repeats: false) { _ in
            MainActor.assumeIsolated { work() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    static func showStartFailureAlert(reason: String, offersPermissions: Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Recording Did Not Start"
        alert.informativeText = reason
        alert.addButton(withTitle: offersPermissions ? "Open Permissions" : "OK")
        if offersPermissions { alert.addButton(withTitle: "Cancel") }
        NSApp.activate()
        return offersPermissions && alert.runModal() == .alertFirstButtonReturn
    }
}
