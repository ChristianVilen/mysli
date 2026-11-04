import Cocoa

/// Owns the Meeting Notes menu and serial processing queue.
@MainActor
final class MeetingNotesController: NSObject, NSMenuItemValidation, MenuSection {
    private enum Job: Equatable {
        case process(RecordedMeeting)
        case updateNotes(MeetingFolder)
        case updateSummary(MeetingFolder)

        var meeting: MeetingFolder {
            switch self {
            case .process(let recording): return recording.folder
            case .updateNotes(let meeting), .updateSummary(let meeting): return meeting
            }
        }

        static func == (lhs: Job, rhs: Job) -> Bool {
            switch (lhs, rhs) {
            case (.process(let lhs), .process(let rhs)): return lhs.folder == rhs.folder
            case (.updateNotes(let lhs), .updateNotes(let rhs)): return lhs == rhs
            case (.updateSummary(let lhs), .updateSummary(let rhs)): return lhs == rhs
            default: return false
            }
        }
    }

    private let recorder: MeetingRecorder
    private let root: () -> URL
    private let processor: MeetingProcessor
    private let summaryTool: () -> SummaryTool
    /// The number of open questions of a meeting, or with nil, of every done meeting.
    private let wordsToCheck: (MeetingFolder?) -> Int
    private let notifier: Notifying
    private let openURL: (URL) -> Void
    private let meterInterval: TimeInterval

    private var queue: [Job] = []
    private var current: (job: Job, activity: String, snapshot: String?)?
    private var processingTask: Task<Void, Never>?
    private var menuIsOpen = false
    private var meterTimer: Timer?
    private var notesSessions: [MeetingFolder: MeetingTypedNotesSession] = [:]
    private var summaryResults: [MeetingFolder: TypedNotesSummaryResult] = [:]
    private var awaitingNotes: [RecordedMeeting] = []
    private(set) var recentNotesMeetings: [MeetingFolder] = []

    private let statusLineItem: NSMenuItem
    private let meterItem: NSMenuItem
    private let meterView = RecordingAudioMeterView()
    private let recordItem: NSMenuItem
    private let pauseItem: NSMenuItem
    private let showControlsItem: NSMenuItem
    private let restorePositionItem: NSMenuItem
    private let progressItem: NSMenuItem
    private let waitingItem: NSMenuItem
    private let checkWordsItem: NSMenuItem
    private let retryItem: NSMenuItem
    private let openFolderItem: NSMenuItem
    private let writeNotesItem: NSMenuItem
    private let recentNotesItem = NSMenuItem(title: "Recent Meeting Notes", action: nil, keyEquivalent: "")

    /// Fires on every change of the recorder's `phase`, Starting and quit included.
    var onStateChange: (() -> Void)?
    /// Nil selects the oldest unfinished review.
    var onCheckWords: (@MainActor (MeetingFolder?) -> Void)?
    var onOpenTypedNotes: ((MeetingFolder) -> Void)?

    /// Claims the recorder's `onChange` and `onEnded`.
    init(recorder: MeetingRecorder,
         root: @escaping () -> URL,
         processor: MeetingProcessor,
         wordsToCheck: @escaping (MeetingFolder?) -> Int,
         summaryTool: @escaping () -> SummaryTool,
         notifier: Notifying = SystemNotifier.shared,
         openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
         meterInterval: TimeInterval = 0.1) {
        self.recorder = recorder
        self.root = root
        self.processor = processor
        self.summaryTool = summaryTool
        self.wordsToCheck = wordsToCheck
        self.notifier = notifier
        self.openURL = openURL
        self.meterInterval = meterInterval
        statusLineItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        meterItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        recordItem = NSMenuItem(title: "", action: #selector(recordClicked), keyEquivalent: "")
        pauseItem = NSMenuItem(title: "", action: #selector(pauseClicked), keyEquivalent: "")
        showControlsItem = NSMenuItem(title: "Show Meeting Controls", action: #selector(showControlsClicked), keyEquivalent: "")
        restorePositionItem = NSMenuItem(title: "Restore Default Position", action: #selector(restorePositionClicked),
                                         keyEquivalent: "")
        progressItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        waitingItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        checkWordsItem = NSMenuItem(title: "", action: #selector(checkWordsClicked), keyEquivalent: "")
        retryItem = NSMenuItem(title: "", action: #selector(retryClicked), keyEquivalent: "")
        openFolderItem = NSMenuItem(title: "Open Meetings Folder", action: #selector(openFolderClicked), keyEquivalent: "")
        writeNotesItem = NSMenuItem(title: "Write Meeting Notes…", action: #selector(writeNotesClicked), keyEquivalent: "")
        super.init()
        meterItem.view = meterView
        for item in [recordItem, pauseItem, showControlsItem, restorePositionItem, checkWordsItem, retryItem, openFolderItem, writeNotesItem] {
            item.target = self
        }
        for item in [statusLineItem, meterItem, pauseItem, showControlsItem, restorePositionItem, progressItem, waitingItem,
                     checkWordsItem, retryItem] {
            item.isHidden = true
        }
        recorder.onChange = { [weak self] in
            if let meeting = self?.recorder.activeMeeting { self?.remember(meeting) }
            self?.refreshNotesSessions()
            self?.updateMenu()
            self?.onStateChange?()
        }
        recorder.onEnded = { [weak self] in self?.recordingEnded($0) }
    }

    isolated deinit {
        meterTimer?.invalidate()
    }

    func buildMenuSection(into menu: NSMenu) {
        let header = NSMenuItem(title: "Meeting Notes", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for item in [statusLineItem, meterItem, recordItem, pauseItem, writeNotesItem, showControlsItem, restorePositionItem, progressItem,
                     waitingItem, checkWordsItem, retryItem, recentNotesItem, openFolderItem] {
            menu.addItem(item)
        }
        menu.addItem(.separator())
        updateMenu()
        reloadRecentNotes()
    }

    func menuWillOpen() {
        menuIsOpen = true
        updateMenu()
        reloadFromDisk()
    }

    func menuTick() {
        updateMenu()
    }

    func menuDidClose() {
        menuIsOpen = false
        meterTimer?.invalidate()
        meterTimer = nil
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem !== recordItem || recorder.phase != .starting
    }

    func resumeUnfinished() {
        for (meeting, stage) in MeetingFolder.all(in: root()) {
            if case .pending = stage { enqueue(.process(RecordedMeeting(folder: meeting, speakers: .empty))) }
        }
    }

    /// Quit: stops the recording and the processing. Each meeting waits for the next launch.
    func shutDown() {
        recorder.shutDown()
        queue.removeAll()
        current = nil
        processingTask?.cancel()
    }

    func waitUntilIdle() async {
        await processingTask?.value
    }

    @objc private func recordClicked() {
        Task { await recorder.toggleRecording() }
    }

    @objc private func pauseClicked() {
        recorder.togglePause()
    }

    @objc private func showControlsClicked() {
        recorder.showControls()
    }

    @objc private func restorePositionClicked() {
        recorder.restoreDefaultPosition()
    }

    @objc private func retryClicked() {
        retryFailed()
    }

    func retryFailed() {
        for (meeting, stage) in MeetingFolder.all(in: root()) {
            guard case .failed = stage else { continue }
            do {
                try meeting.clearFailure()
                enqueue(.process(RecordedMeeting(folder: meeting, speakers: .empty)))
            } catch {
                Log.meeting.error("Could not clear the failure of \(meeting.name, privacy: .public) (code \((error as NSError).code)): \(error.localizedDescription)")
            }
        }
        reloadFromDisk()
    }

    func updateNotes(_ meeting: MeetingFolder) {
        enqueue(.updateNotes(meeting))
    }

    @discardableResult
    func updateSummary(_ meeting: MeetingFolder) -> Bool {
        let context = notesContext(for: meeting)
        guard MeetingTypedNotesSession.canUpdateSummary(meeting, recordingPhase: context.recordingPhase,
            summaryState: context.summaryState, hasUnsavedChanges: notesSessions[meeting]?.hasUnsavedChanges == true)
        else { return false }
        enqueue(.updateSummary(meeting))
        return true
    }

    func typedNotes(for meeting: MeetingFolder) throws -> MeetingTypedNotesSession {
        if let session = notesSessions[meeting] { return session }
        let session = try MeetingTypedNotesSession(meeting: meeting)
        session.noteTime = { [weak self] in self?.recorder.noteTime(for: meeting) ?? .afterRecording }
        notesSessions[meeting] = session
        session.context = { [weak self] in self?.notesContext(for: meeting) ?? (.idle, .idle) }
        session.onSaved = { [weak self] in self?.notesSaved(for: meeting) }
        remember(meeting)
        refreshNotesSessions()
        return session
    }

    var hasUnsavedTypedNotes: Bool { notesSessions.values.contains { $0.hasUnsavedChanges } }
    var unsavedNotesMeetings: [MeetingFolder] { notesSessions.values.filter(\.hasUnsavedChanges).map(\.meeting) }

    @discardableResult
    func closeTypedNotes(for meeting: MeetingFolder) -> Bool {
        guard let session = notesSessions[meeting], session.close() else { return false }
        notesSessions.removeValue(forKey: meeting)
        pruneSummaryResults()
        return true
    }

    func openCurrentTypedNotes() {
        if let meeting = recorder.activeMeeting { onOpenTypedNotes?(meeting) }
    }

    @objc private func writeNotesClicked() { openCurrentTypedNotes() }

    @objc private func recentNotesClicked(_ sender: NSMenuItem) {
        guard let meeting = sender.representedObject as? MeetingFolder else { return }
        onOpenTypedNotes?(meeting)
    }

    private func recordingEnded(_ recording: RecordedMeeting) {
        if notesSessions[recording.folder]?.hasUnsavedChanges == true {
            awaitingNotes.append(recording)
            refreshNotesSessions()
        } else {
            enqueue(.process(recording))
        }
    }

    private func notesSaved(for meeting: MeetingFolder) {
        let ready = awaitingNotes.filter { $0.folder == meeting }
        awaitingNotes.removeAll { $0.folder == meeting }
        for recording in ready { enqueue(.process(recording)) }
    }

    private func setSummaryResult(_ result: TypedNotesSummaryResult?, for meeting: MeetingFolder) {
        summaryResults[meeting] = result
        refreshNotesSessions()
    }

    private func notesContext(for meeting: MeetingFolder) -> (recordingPhase: RecorderPhase, summaryState: TypedNotesSummaryState) {
        let phase = recorder.activeMeeting == meeting ? recorder.phase : .idle
        if let current, current.job.meeting == meeting {
            return (phase, current.snapshot.map { .summarizing(snapshot: $0) } ?? .processing)
        }
        if queue.contains(where: { $0.meeting == meeting }) { return (phase, .queued) }
        if awaitingNotes.contains(where: { $0.folder == meeting }) { return (phase, .waitingForSave) }
        return (phase, summaryResults[meeting]?.state ?? .idle)
    }

    private func refreshNotesSessions() {
        for session in notesSessions.values { session.onChange?() }
    }

    private func remember(_ meeting: MeetingFolder) {
        recentNotesMeetings.removeAll { $0 == meeting }
        recentNotesMeetings.insert(meeting, at: 0)
        recentNotesMeetings = Array(recentNotesMeetings.prefix(5))
        pruneSummaryResults()
        rebuildRecentNotesMenu()
    }

    private func reloadRecentNotes() {
        let disk = MeetingFolder.all(in: root()).reversed().map(\.0)
        var seen = Set<MeetingFolder>()
        recentNotesMeetings = Array((recentNotesMeetings + disk).filter { seen.insert($0).inserted }.prefix(5))
        rebuildRecentNotesMenu()
    }

    private func rebuildRecentNotesMenu() {
        let submenu = NSMenu()
        let unsaved = unsavedNotesMeetings.filter { !recentNotesMeetings.contains($0) }.sorted { $0.name > $1.name }
        for meeting in recentNotesMeetings + unsaved {
            let item = NSMenuItem(title: meeting.title, action: #selector(recentNotesClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = meeting
            submenu.addItem(item)
        }
        recentNotesItem.submenu = submenu
        recentNotesItem.isHidden = submenu.items.isEmpty
    }

    private func pruneSummaryResults() {
        let retained = Set(recentNotesMeetings + Array(notesSessions.keys) + queue.map(\.meeting)
            + awaitingNotes.map(\.folder) + [current?.job.meeting].compactMap { $0 })
        summaryResults = summaryResults.filter { retained.contains($0.key) }
    }

    @objc private func checkWordsClicked() {
        onCheckWords?(nil)
    }

    @objc private func openFolderClicked() {
        let root = root()
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        openURL(root)
    }

    func meetingsFolderChanged() {
        reloadFromDisk()
    }

    private func enqueue(_ job: Job) {
        guard !queue.contains(job), current?.job != job else { return }
        queue.append(job)
        refreshNotesSessions()
        updateMenu()
        guard processingTask == nil else { return }
        processingTask = Task { [weak self] in await self?.processQueue() }
    }

    private func processQueue() async {
        while !queue.isEmpty, !Task.isCancelled {
            let job = queue.removeFirst()
            let tool = summaryTool()
            current = (job, "Processing", nil)
            refreshNotesSessions()
            let summaryInput: (String) -> Void = { [weak self] notes in
                self?.current?.snapshot = notes
                self?.refreshNotesSessions()
            }
            switch job {
            case .process(let recording):
                let meeting = recording.folder
                let outcome = await processor.process(meeting, speakers: recording.speakers, tool: tool,
                                                       summaryInput: summaryInput) { [weak self] progress in
                    self?.current?.activity = progress.title
                    self?.updateMenu()
                }
                let snapshot = current?.snapshot
                current = nil
                switch outcome {
                case .done: setSummaryResult(snapshot.map { .updated(snapshot: $0) }, for: meeting)
                case .noSpeech: setSummaryResult(.updated(snapshot: ""), for: meeting)
                case .failed: setSummaryResult(.failed("Processing failed. Use Retry Failed Meeting in the Mysli menu."), for: meeting)
                case .busy, .gone: setSummaryResult(.failed("The meeting folder is unavailable or in use."), for: meeting)
                case .cancelled: setSummaryResult(nil, for: meeting)
                }
                report(outcome, for: meeting)
            case .updateNotes(let meeting):
                current?.activity = "Updating notes"
                updateMenu()
                let outcome = await processor.updateNotes(meeting, tool: tool, summaryInput: summaryInput)
                let snapshot = current?.snapshot
                current = nil
                finishSummaryUpdate(outcome, for: meeting, snapshot: snapshot)
                report(outcome, for: meeting)
            case .updateSummary(let meeting):
                current?.activity = "Updating summary"
                updateMenu()
                let outcome = await processor.updateSummary(meeting, tool: tool, summaryInput: summaryInput)
                let snapshot = current?.snapshot
                current = nil
                finishSummaryUpdate(outcome, for: meeting, snapshot: snapshot)
            }
        }
        processingTask = nil
        pruneSummaryResults()
        updateMenu()
        reloadFromDisk()
    }

    private func finishSummaryUpdate(_ outcome: NotesUpdateOutcome, for meeting: MeetingFolder, snapshot: String?) {
        switch outcome {
        case .updated: setSummaryResult(snapshot.map { .updated(snapshot: $0) }, for: meeting)
        case .cancelled: setSummaryResult(nil, for: meeting)
        case .busy: setSummaryResult(.failed("The meeting folder is in use. Try Update summary again."), for: meeting)
        case .notReady: setSummaryResult(.failed("The meeting is not ready, or its folder was moved or deleted."), for: meeting)
        case .failed, .summaryToolFailed:
            setSummaryResult(.failed("The summary could not be updated. The previous summary is unchanged. Try again."), for: meeting)
        }
    }

    private func report(_ outcome: MeetingOutcome, for meeting: MeetingFolder) {
        // The tool output stays in error.md; a notification is too short for it.
        switch outcome {
        case .done(let summary):
            switch wordsToCheck(meeting) {
            case 0:
                notifier.post(title: "Meeting Notes Ready", body: "\(meeting.title). Click to open the summary.", onClick: .open(summary))
            case let open:
                notifier.post(title: "Meeting Notes Ready",
                              body: "\(meeting.title). \(Self.wordCount(open)). Click to check them.",
                              onClick: .checkWords(meeting))
            }
        case .failed(.transcribe, _):
            notifier.post(title: MeetingStep.transcribe.failureHeading,
                          body: "\(meeting.title). Choose Retry Failed Meeting in the Mysli menu to try again. Click to see what went wrong.",
                          onClick: .open(meeting.url(for: .failure)))
        case .failed(.summarize, _):
            notifier.post(title: MeetingStep.summarize.failureHeading,
                          body: "The transcript of \(meeting.title) is ready. Choose Retry Failed Meeting in the Mysli menu to try the summary again. Click to see what went wrong.",
                          onClick: .open(meeting.url(for: .failure)))
        case .noSpeech:
            notifier.post(title: "No Speech Detected",
                          body: "\(meeting.title). The audio is in the meeting folder. Click to open it.",
                          onClick: .open(meeting.url))
        case .cancelled, .busy, .gone:
            break
        }
    }

    /// The review window said that a notification follows, so every outcome but a quit posts one.
    private func report(_ outcome: NotesUpdateOutcome, for meeting: MeetingFolder) {
        switch outcome {
        case .updated(let summary):
            notifier.post(title: "Notes Updated", body: "\(meeting.title). Click to open the summary.", onClick: .open(summary))
        case .summaryToolFailed(let failures):
            for failure in failures {
                Log.meeting.error("Could not update the notes of \(meeting.name, privacy: .public): \(failure.logMessage)")
            }
            notifier.post(title: "Notes Not Updated",
                          body: "\(meeting.title). The summary tool did not answer, so the summary did not change. The transcript has your answers.",
                          onClick: .open(meeting.url(for: .summary)))
        case .failed(let message):
            Log.meeting.error("Could not update the notes of \(meeting.name, privacy: .public): \(message)")
            notifier.post(title: "Notes Not Updated",
                          body: "\(meeting.title). Mysli could not update the notes, so the summary did not change.",
                          onClick: .open(meeting.url(for: .summary)))
        case .busy:
            notifier.post(title: "Notes Not Updated",
                          body: "\(meeting.title). The meeting folder was in use, for example by another Mysli, so the notes did not change. Click to open Check Words and choose Update Notes again.",
                          onClick: .checkWords(meeting))
        case .notReady:
            notifier.post(title: "Notes Not Updated",
                          body: "\(meeting.title). The meeting is not finished, or its folder was moved or deleted, so the notes did not change.",
                          onClick: nil)
        case .cancelled:
            break
        }
    }

    private var statusLine: String? {
        guard recorder.phase != .starting else { return "Starting Recording" }
        guard let recorded = recorder.recordedTime.map(RecordedTime.format) else { return nil }
        return recorder.phase == .paused ? "Paused · \(recorded)" : "● Recording · \(recorded)"
    }

    private func updateMenu() {
        let phase = recorder.phase
        let statusLine = statusLine
        statusLineItem.isHidden = statusLine == nil
        if let statusLine {
            if let title = recorder.displayTitle {
                let shortTitle = title.count > 48 ? String(title.prefix(47)) + "…" : title
                statusLineItem.title = "\(statusLine) · \(shortTitle)"
                statusLineItem.toolTip = title
                statusLineItem.setAccessibilityLabel("\(statusLine) · \(title)")
            } else {
                statusLineItem.title = statusLine
                statusLineItem.toolTip = nil
                statusLineItem.setAccessibilityLabel(nil)
            }
        }
        recordItem.title = phase.isCapturing ? "Stop Recording Meeting" : "Start Recording Meeting"
        writeNotesItem.isHidden = !phase.isCapturing
        pauseItem.title = phase == .paused ? "Resume Recording" : "Pause Recording"
        for item in [pauseItem, showControlsItem, restorePositionItem, meterItem] { item.isHidden = !phase.isCapturing }
        reconcileMeterTimer()
        progressItem.isHidden = current == nil
        waitingItem.isHidden = current == nil || queue.isEmpty
        if let current {
            progressItem.title = "\(current.activity): \(current.job.meeting.title)"
            waitingItem.title = queue.count == 1 ? "1 more meeting waiting" : "\(queue.count) more meetings waiting"
        }
    }

    private func reconcileMeterTimer() {
        let phase = recorder.phase
        guard menuIsOpen, phase.isCapturing else {
            meterTimer?.invalidate()
            meterTimer = nil
            if !phase.isCapturing { meterView.show(.silent) }
            return
        }
        refreshMeters()
        guard meterTimer == nil else { return }
        let timer = Timer(timeInterval: meterInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMeters() }
        }
        // .common mode: the menu is open, and menu tracking does not fire default-mode timers.
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func refreshMeters() {
        guard menuIsOpen, let levels = recorder.audioLevels() else { return }
        meterView.show(levels)
    }

    /// Other processes can change failures and word reviews on disk.
    private func reloadFromDisk() {
        reloadRecentNotes()
        let failed = MeetingFolder.all(in: root()).filter {
            if case .failed = $0.1 { return true }
            return false
        }
        retryItem.isHidden = failed.isEmpty
        retryItem.title = failed.count == 1 ? "Retry Failed Meeting" : "Retry \(failed.count) Failed Meetings"
        let open = wordsToCheck(nil)
        checkWordsItem.isHidden = open == 0
        checkWordsItem.title = "Check Words (\(open))…"
    }

    private static func wordCount(_ count: Int) -> String {
        count == 1 ? "1 word to check" : "\(count) words to check"
    }
}
