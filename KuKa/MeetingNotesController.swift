import Cocoa

@MainActor
enum MeetingsFolderPicker {
    static func choose(current: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = current
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Owns the Meeting Notes menu and serial processing queue.
@MainActor
final class MeetingNotesController: NSObject, NSMenuItemValidation, MenuSection {
    private enum Job: Equatable {
        case process(RecordedMeeting)
        case updateNotes(MeetingFolder)

        var meeting: MeetingFolder {
            switch self {
            case .process(let recording): return recording.folder
            case .updateNotes(let meeting): return meeting
            }
        }

        static func == (lhs: Job, rhs: Job) -> Bool {
            switch (lhs, rhs) {
            case (.process(let lhs), .process(let rhs)): return lhs.folder == rhs.folder
            case (.updateNotes(let lhs), .updateNotes(let rhs)): return lhs == rhs
            default: return false
            }
        }
    }

    private let recorder: MeetingRecorder
    private let root: () -> URL
    private let processor: MeetingProcessor
    /// The number of open questions of a meeting, or with nil, of every done meeting.
    private let wordsToCheck: (MeetingFolder?) -> Int
    private let notifier: Notifying
    private let openURL: (URL) -> Void
    private let chooseFolder: @MainActor (URL) -> URL?
    private let setRoot: (URL) -> Void

    private var queue: [Job] = []
    private var current: (job: Job, activity: String)?
    private var processingTask: Task<Void, Never>?
    private var menuIsOpen = false
    private var meterTimer: Timer?

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
    private let chooseFolderItem: NSMenuItem

    /// Fires on every change of the recorder's `phase`, Starting and quit included.
    var onStateChange: (() -> Void)?
    /// Nil selects the oldest unfinished review.
    var onCheckWords: (@MainActor (MeetingFolder?) -> Void)?

    /// Claims the recorder's `onChange` and `onEnded`.
    init(recorder: MeetingRecorder,
         root: @escaping () -> URL,
         processor: MeetingProcessor,
         wordsToCheck: @escaping (MeetingFolder?) -> Int,
         chooseFolder: @escaping @MainActor (URL) -> URL? = MeetingsFolderPicker.choose,
         setRoot: @escaping (URL) -> Void,
         notifier: Notifying = SystemNotifier.shared,
         openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.recorder = recorder
        self.root = root
        self.processor = processor
        self.wordsToCheck = wordsToCheck
        self.notifier = notifier
        self.openURL = openURL
        self.chooseFolder = chooseFolder
        self.setRoot = setRoot
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
        chooseFolderItem = NSMenuItem(title: "Choose Meetings Folder…", action: #selector(chooseFolderClicked), keyEquivalent: "")
        super.init()
        meterItem.view = meterView
        for item in [recordItem, pauseItem, showControlsItem, restorePositionItem, checkWordsItem, retryItem, openFolderItem,
                     chooseFolderItem] {
            item.target = self
        }
        for item in [statusLineItem, meterItem, pauseItem, showControlsItem, restorePositionItem, progressItem, waitingItem,
                     checkWordsItem, retryItem] {
            item.isHidden = true
        }
        recorder.onChange = { [weak self] in
            self?.updateMenu()
            self?.onStateChange?()
        }
        recorder.onEnded = { [weak self] in self?.enqueue(.process($0)) }
    }

    isolated deinit {
        meterTimer?.invalidate()
    }

    func buildMenuSection(into menu: NSMenu) {
        let header = NSMenuItem(title: "Meeting Notes", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for item in [statusLineItem, meterItem, recordItem, pauseItem, showControlsItem, restorePositionItem, progressItem,
                     waitingItem, checkWordsItem, retryItem, openFolderItem, chooseFolderItem] {
            menu.addItem(item)
        }
        menu.addItem(.separator())
        updateMenu()
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
                NSLog("Ku-Ka: could not clear the failure of \(meeting.name): \(error)")
            }
        }
        reloadFromDisk()
    }

    func updateNotes(_ meeting: MeetingFolder) {
        enqueue(.updateNotes(meeting))
    }

    @objc private func checkWordsClicked() {
        onCheckWords?(nil)
    }

    @objc private func openFolderClicked() {
        let root = root()
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        openURL(root)
    }

    @objc private func chooseFolderClicked() {
        guard let chosen = chooseFolder(root()) else { return }
        setRoot(chosen)
        reloadFromDisk()
    }

    private func enqueue(_ job: Job) {
        guard !queue.contains(job), current?.job != job else { return }
        queue.append(job)
        updateMenu()
        guard processingTask == nil else { return }
        processingTask = Task { [weak self] in await self?.processQueue() }
    }

    private func processQueue() async {
        while !queue.isEmpty, !Task.isCancelled {
            let job = queue.removeFirst()
            switch job {
            case .process(let recording):
                let meeting = recording.folder
                let outcome = await processor.process(meeting, speakers: recording.speakers) { [weak self] progress in
                    self?.current = (job, progress.title)
                    self?.updateMenu()
                }
                current = nil
                report(outcome, for: meeting)
            case .updateNotes(let meeting):
                current = (job, "Updating notes")
                updateMenu()
                let outcome = await processor.updateNotes(meeting)
                current = nil
                report(outcome, for: meeting)
            }
        }
        processingTask = nil
        updateMenu()
        reloadFromDisk()
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
                          body: "\(meeting.title). Choose Retry Failed Meeting in the Ku-Ka menu to try again. Click to see what went wrong.",
                          onClick: .open(meeting.url(for: .failure)))
        case .failed(.summarize, _):
            notifier.post(title: MeetingStep.summarize.failureHeading,
                          body: "The transcript of \(meeting.title) is ready. Choose Retry Failed Meeting in the Ku-Ka menu to try the summary again. Click to see what went wrong.",
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
        case .summaryToolFailed(let message):
            NSLog("Ku-Ka: could not update the notes of %@: %@", meeting.name, message)
            notifier.post(title: "Notes Not Updated",
                          body: "\(meeting.title). The summary tool did not answer, so the summary did not change. The transcript has your answers.",
                          onClick: .open(meeting.url(for: .summary)))
        case .failed(let message):
            NSLog("Ku-Ka: could not update the notes of %@: %@", meeting.name, message)
            notifier.post(title: "Notes Not Updated",
                          body: "\(meeting.title). Ku-Ka could not update the notes, so the summary did not change.",
                          onClick: .open(meeting.url(for: .summary)))
        case .busy:
            notifier.post(title: "Notes Not Updated",
                          body: "\(meeting.title). The meeting folder was in use, for example by another Ku-Ka, so the notes did not change. Click to open Check Words and choose Update Notes again.",
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
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMeters() }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func refreshMeters() {
        guard menuIsOpen, let levels = recorder.audioLevels() else { return }
        meterView.show(levels)
    }

    /// Other processes can change failures and word reviews on disk.
    private func reloadFromDisk() {
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
