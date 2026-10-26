import Cocoa

@MainActor
final class MeetingNotesController: NSObject, NSMenuItemValidation, MenuSection {
    private enum Recorder {
        case idle
        case starting
        case recording(MeetingFolder, since: Date, ActiveRecording, MeetingLock)
    }

    private let permissions: PermissionsManager
    private let root: () -> URL
    private let capture: MeetingAudioCapturing
    private let processor: MeetingProcessor
    private let notifier: Notifying
    /// Returns true when the user chose Open Permissions.
    private let alertStartFailure: @MainActor (_ reason: String, _ offersPermissions: Bool) -> Bool
    private let openURL: (URL) -> Void
    private let now: () -> Date

    private var recorder: Recorder = .idle
    private var queue: [MeetingFolder] = []
    private var current: (meeting: MeetingFolder, activity: String)?
    private var processingTask: Task<Void, Never>?

    private let statusLineItem: NSMenuItem
    private let recordItem: NSMenuItem
    private let progressItem: NSMenuItem
    private let waitingItem: NSMenuItem
    private let retryItem: NSMenuItem
    private let openFolderItem: NSMenuItem

    var onStateChange: (() -> Void)?
    var onShowPermissions: (() -> Void)?

    var isRecording: Bool {
        if case .recording = recorder { return true }
        return false
    }

    init(permissions: PermissionsManager,
         root: @escaping () -> URL,
         capture: MeetingAudioCapturing = ScreenCaptureMeetingAudio(),
         processor: MeetingProcessor = MeetingProcessor(),
         notifier: Notifying = SystemNotifier.shared,
         alertStartFailure: @escaping @MainActor (String, Bool) -> Bool = MeetingNotesController.showStartFailureAlert,
         openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
         now: @escaping () -> Date = { Date() }) {
        self.permissions = permissions
        self.root = root
        self.capture = capture
        self.processor = processor
        self.notifier = notifier
        self.alertStartFailure = alertStartFailure
        self.openURL = openURL
        self.now = now
        statusLineItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        recordItem = NSMenuItem(title: "", action: #selector(recordClicked), keyEquivalent: "")
        progressItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        waitingItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        retryItem = NSMenuItem(title: "", action: #selector(retryClicked), keyEquivalent: "")
        openFolderItem = NSMenuItem(title: "Open Meetings Folder", action: #selector(openFolderClicked), keyEquivalent: "")
        super.init()
        for item in [recordItem, retryItem, openFolderItem] { item.target = self }
        for item in [statusLineItem, progressItem, waitingItem, retryItem] { item.isHidden = true }
    }

    func buildMenuSection(into menu: NSMenu) {
        let header = NSMenuItem(title: "Meeting Notes", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for item in [statusLineItem, recordItem, progressItem, waitingItem, retryItem, openFolderItem] {
            menu.addItem(item)
        }
        menu.addItem(.separator())
        updateMenu()
    }

    func menuWillOpen() {
        updateMenu()
        reloadFailedMeetingsFromDisk()
    }

    func menuTick() {
        updateMenu()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem === recordItem, case .starting = recorder else { return true }
        return false
    }

    func resumeUnfinished() {
        for (meeting, stage) in MeetingFolder.all(in: root()) {
            if case .pending = stage { enqueue(meeting) }
        }
    }

    func shutDown() {
        if case .recording(_, _, let handle, _) = recorder { handle.stop() }
        recorder = .idle
        processingTask?.cancel()
    }

    func waitUntilIdle() async {
        await processingTask?.value
    }

    @objc private func recordClicked() {
        Task { await toggleRecording() }
    }

    func toggleRecording() async {
        switch recorder {
        case .idle: await start()
        case .recording: stop()
        case .starting: break
        }
    }

    private func start() async {
        recorder = .starting
        updateMenu()
        notifier.requestPermission()
        if let reason = await missingGrant() {
            recorder = .idle
            updateMenu()
            if alertStartFailure(reason, true) { onShowPermissions?() }
            return
        }
        let startedAt = now()
        do {
            let meeting = try MeetingFolder.create(in: root(), startingAt: startedAt)
            do {
                let lock = try meeting.lock()
                let handle = try await capture.start(into: meeting) { [weak self] reason in
                    self?.handleInterruption(of: meeting, reason: reason)
                }
                if let reason = handle.endReason {
                    endRecording(meeting, interruptedBecause: reason)
                } else {
                    recorder = .recording(meeting, since: startedAt, handle, lock)
                    onStateChange?()
                }
            } catch {
                try? FileManager.default.removeItem(at: meeting.url)
                throw error
            }
        } catch {
            recorder = .idle
            _ = alertStartFailure(error.localizedDescription, false)
        }
        updateMenu()
    }

    /// Nil when recording can start, otherwise the reason it cannot.
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

    private func stop() {
        guard case .recording(let meeting, _, let handle, _) = recorder else { return }
        handle.stop()
        recorder = .idle
        updateMenu()
        onStateChange?()
        enqueue(meeting)
    }

    private func handleInterruption(of meeting: MeetingFolder, reason: String) {
        guard case .recording(let recording, _, _, _) = recorder, recording == meeting else { return }
        endRecording(meeting, interruptedBecause: reason)
    }

    private func endRecording(_ meeting: MeetingFolder, interruptedBecause reason: String) {
        recorder = .idle
        updateMenu()
        onStateChange?()
        notifier.post(title: "Recording Stopped",
                      body: "\(reason) Ku-Ka makes notes from what it recorded. To record the rest, choose Start Recording Meeting.",
                      opening: nil)
        enqueue(meeting)
    }

    @objc private func retryClicked() {
        retryFailed()
    }

    func retryFailed() {
        for (meeting, stage) in MeetingFolder.all(in: root()) {
            guard case .failed = stage else { continue }
            do {
                try meeting.clearFailure()
                enqueue(meeting)
            } catch {
                NSLog("Ku-Ka: could not clear the failure of \(meeting.name): \(error)")
            }
        }
        reloadFailedMeetingsFromDisk()
    }

    @objc private func openFolderClicked() {
        let root = root()
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        openURL(root)
    }

    private func enqueue(_ meeting: MeetingFolder) {
        guard !queue.contains(meeting), current?.meeting != meeting else { return }
        queue.append(meeting)
        updateMenu()
        guard processingTask == nil else { return }
        processingTask = Task { [weak self] in await self?.processQueue() }
    }

    private func processQueue() async {
        while !queue.isEmpty, !Task.isCancelled {
            let meeting = queue.removeFirst()
            let outcome = await processor.process(meeting, onStep: { [weak self] step in
                self?.current = (meeting, step.progressVerb)
                self?.updateMenu()
            }, onDownload: { [weak self] in
                self?.current = (meeting, "Downloading speech model")
                self?.updateMenu()
            })
            current = nil
            report(outcome, for: meeting)
        }
        processingTask = nil
        updateMenu()
        reloadFailedMeetingsFromDisk()
    }

    private func report(_ outcome: MeetingOutcome, for meeting: MeetingFolder) {
        // The tool output stays in error.md; a notification is too short for it.
        switch outcome {
        case .done(let summary):
            notifier.post(title: "Meeting Notes Ready", body: "\(meeting.title). Click to open the summary.", opening: summary)
        case .failed(.transcribe, _):
            notifier.post(title: MeetingStep.transcribe.failureHeading,
                          body: "\(meeting.title). Choose Retry Failed Meeting in the Ku-Ka menu to try again. Click to see what went wrong.",
                          opening: meeting.url(for: .failure))
        case .failed(.summarize, _):
            notifier.post(title: MeetingStep.summarize.failureHeading,
                          body: "The transcript of \(meeting.title) is ready. Choose Retry Failed Meeting in the Ku-Ka menu to try the summary again. Click to see what went wrong.",
                          opening: meeting.url(for: .failure))
        case .noSpeech:
            notifier.post(title: "No Speech Detected",
                          body: "\(meeting.title). The audio is in the meeting folder. Click to open it.",
                          opening: meeting.url)
        case .cancelled, .busy, .gone:
            break
        }
    }

    private func updateMenu() {
        switch recorder {
        case .idle:
            statusLineItem.isHidden = true
        case .starting:
            statusLineItem.title = "Starting Recording"
            statusLineItem.isHidden = false
        case .recording(_, let since, _, _):
            statusLineItem.title = "● Recording · \(Self.formatElapsed(now().timeIntervalSince(since)))"
            statusLineItem.isHidden = false
        }
        recordItem.title = isRecording ? "Stop Recording Meeting" : "Start Recording Meeting"
        progressItem.isHidden = current == nil
        waitingItem.isHidden = current == nil || queue.isEmpty
        if let current {
            progressItem.title = "\(current.activity): \(current.meeting.title)"
            waitingItem.title = queue.count == 1 ? "1 more meeting waiting" : "\(queue.count) more meetings waiting"
        }
    }

    private func reloadFailedMeetingsFromDisk() {
        let failed = MeetingFolder.all(in: root()).filter {
            if case .failed = $0.1 { return true }
            return false
        }
        retryItem.isHidden = failed.isEmpty
        retryItem.title = failed.count == 1 ? "Retry Failed Meeting" : "Retry \(failed.count) Failed Meetings"
    }

    static func formatElapsed(_ interval: TimeInterval) -> String {
        let seconds = Int(max(0, interval))
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds % 60)
            : String(format: "%d:%02d", minutes, seconds % 60)
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
