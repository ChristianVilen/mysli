import XCTest
@testable import KuKa

struct TestError: LocalizedError {
    let errorDescription: String?
}

let defaultNotes = "## Summary\nShip Friday."

extension Result where Success == CommandResult, Failure == any Error {
    static func reply(_ stdout: String) -> Self {
        .success(CommandResult(termination: .exited(0), stdout: stdout, stderr: ""))
    }
}

/// The processor of the meeting tests: fake engines, a fake CLI runner that finds every CLI, a trash that
/// deletes, and a fixed clock.
@MainActor
func makeMeetingProcessor(transcribers: [Transcribing] = [FakeTranscriber()],
                          roomLabeller: RoomLabelling = FakeRoomLabeller(),
                          runner: CommandRunning = FakeCommandRunner(),
                          knownWords: @escaping () -> KnownWordsList = { .empty },
                          locale: Locale = Locale(identifier: "en-US"),
                          trash: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) })
    -> MeetingProcessor {
    MeetingProcessor(
        transcribers: transcribers,
        roomLabeller: roomLabeller,
        summarizer: Summarizer(runner: runner, home: URL(fileURLWithPath: "/Users/test"), isExecutable: { _ in true }),
        knownWords: knownWords,
        locale: { locale },
        trash: trash,
        now: { localDate(2026, 10, 23, 15, 0) })
}

/// `transcribe` waits until its task is cancelled. With `downloadWaits`, `download` also waits, after `onStart`.
final class SuspendedTranscriber: FakeTranscriber {
    var downloadWaits = false

    override func download(for locale: Locale, onStart: @MainActor () -> Void) async throws {
        guard downloadWaits else { return try await super.download(for: locale, onStart: onStart) }
        await onStart()
        try await Task.sleep(for: .seconds(60))
    }

    override func transcribe(_ audio: URL) async throws -> TrackTranscript {
        try await Task.sleep(for: .seconds(60))
        return TrackTranscript(segments: [], duration: 0)
    }
}

@MainActor
class MeetingProcessorTestCase: XCTestCase {
    var whisper: FakeTranscriber!
    var apple: FakeTranscriber!
    var labeller: FakeRoomLabeller!
    var runner: FakeCommandRunner!
    var trashed: [String] = []
    var progress: [MeetingProgress] = []
    /// Read by the processor at each use, so a test can change the list between two runs.
    var knownWords = KnownWordsList.empty

    override func setUp() async throws {
        whisper = makeTranscriber(named: "Whisper")
        apple = makeTranscriber(named: "Apple")
        labeller = FakeRoomLabeller()
        runner = FakeCommandRunner()
        runner.results["agy"] = .reply(defaultNotes)
        trashed = []
        progress = []
        knownWords = .empty
    }

    func makeTranscriber(named name: String) -> FakeTranscriber {
        let transcriber = FakeTranscriber(name: name)
        transcriber.byFileName["them.caf"] = .success(TrackTranscript(
            segments: [TranscriptSegment(start: 1, end: 3, text: "Let's ship on Friday")], duration: 60))
        transcriber.byFileName["me.caf"] = .success(TrackTranscript(
            segments: [TranscriptSegment(start: 4, end: 5, text: "Sounds good")], duration: 59))
        return transcriber
    }

    func makeProcessor(transcribers: [Transcribing]? = nil, runner: CommandRunning? = nil) -> MeetingProcessor {
        makeMeetingProcessor(
            transcribers: transcribers ?? [whisper, apple],
            roomLabeller: labeller,
            runner: runner ?? self.runner,
            knownWords: { [unowned self] in knownWords },
            trash: { [unowned self] url in
                trashed.append(url.lastPathComponent)
                try FileManager.default.removeItem(at: url)
            })
    }

    func makeMeeting() throws -> MeetingFolder {
        let meeting = try MeetingFolder.create(in: try makeTemporaryDirectory(), startingAt: localDate(2026, 10, 23, 14, 2))
        for track in MeetingTrack.allCases {
            FileManager.default.createFile(atPath: meeting.audioURL(track).path, contents: Data())
        }
        return meeting
    }

    func process(_ meeting: MeetingFolder, with processor: MeetingProcessor? = nil) async -> MeetingOutcome {
        await (processor ?? makeProcessor()).process(meeting) { [unowned self] in progress.append($0) }
    }

    func audioExists(_ meeting: MeetingFolder) -> Bool {
        FileManager.default.fileExists(atPath: meeting.audioURL(.system).path)
    }
}

@MainActor
class MeetingNotesTestCase: XCTestCase {
    var root: URL!
    var screenRecording = true
    var microphone = MicrophoneAccess.granted
    var answerMicrophonePrompt: () async -> Bool = { false }
    var capture: FakeMeetingAudioCapture!
    var liveTranscriber: FakeLiveTranscriber!
    var transcriber: Transcribing!
    var roomLabeller: FakeRoomLabeller!
    var runner: FakeCommandRunner!
    /// Replaces `runner` in the next `makeController()` when set.
    var gate: CommandRunning?
    var clock = localDate(2026, 10, 23, 14, 2)
    var hostTime = HostTime(seconds: 1_000)
    var notifier: FakeNotifier!
    var notifications: [String] { notifier.posted.map { "\($0.title): \($0.body)" } }
    /// Read by the processor and the controller at each use.
    var knownWords = KnownWordsList.empty
    var alerts: [String] = []
    var opened: [URL] = []
    var pickedFolder: URL?
    var pickerRoots: [URL] = []
    var savedRoots: [URL] = []
    var permissionWindows = 0
    var stateChanges = 0
    var controlsRequests: [MeetingControlsRequest] = []
    var recorder: MeetingRecorder!
    var sut: MeetingNotesController!
    var menu: NSMenu!

    override func setUp() async throws {
        root = try makeTemporaryDirectory().appendingPathComponent("Meetings", isDirectory: true)
        capture = FakeMeetingAudioCapture()
        liveTranscriber = FakeLiveTranscriber()
        let fakeTranscriber = FakeTranscriber()
        fakeTranscriber.byFileName["them.caf"] = .success(TrackTranscript(
            segments: [TranscriptSegment(start: 1, end: 3, text: "Let's ship on Friday")], duration: 60))
        transcriber = fakeTranscriber
        roomLabeller = FakeRoomLabeller()
        runner = FakeCommandRunner()
        runner.results["agy"] = .reply(defaultNotes)
        notifier = FakeNotifier()
        sut = makeController()
    }

    override func tearDown() async throws {
        sut.shutDown()
        await sut.waitUntilIdle()
    }

    func makeController() -> MeetingNotesController {
        let permissions = PermissionsManager(
            isAccessibilityTrusted: { true },
            hasScreenCaptureAccess: { [unowned self] in screenRecording },
            microphoneAccess: { [unowned self] in microphone },
            requestMicrophoneAccess: { [unowned self] in await answerMicrophonePrompt() })
        recorder = MeetingRecorder(
            permissions: permissions,
            root: { [unowned self] in root },
            capture: capture,
            liveTranscriber: liveTranscriber,
            notifier: notifier,
            alertStartFailure: { [unowned self] reason, offersPermissions in
                alerts.append(reason)
                return offersPermissions
            },
            now: { [unowned self] in clock },
            hostNow: { [unowned self] in hostTime },
            closeSavedNoticeLater: { _ in })
        recorder.onShowPermissions = { [unowned self] in permissionWindows += 1 }
        recorder.onControlsRequest = { [unowned self] in controlsRequests.append($0) }
        let controller = MeetingNotesController(
            recorder: recorder,
            root: { [unowned self] in root },
            processor: makeMeetingProcessor(
                transcribers: [transcriber],
                roomLabeller: roomLabeller,
                runner: gate ?? runner,
                knownWords: { [unowned self] in knownWords }),
            wordsToCheck: { [unowned self] in WordReview.openQuestionCount(of: $0, in: root, knownWords: knownWords) },
            chooseFolder: { [unowned self] in pickerRoots.append($0); return pickedFolder },
            setRoot: { [unowned self] in savedRoots.append($0); root = $0 },
            notifier: notifier,
            openURL: { [unowned self] in opened.append($0) })
        controller.onStateChange = { [unowned self] in stateChanges += 1 }
        menu = NSMenu()
        controller.buildMenuSection(into: menu)
        return controller
    }

    var visibleTitles: [String] {
        menu.items.filter { !$0.isHidden && $0.view == nil }.map(\.title)
    }

    func item(titled title: String) -> NSMenuItem? {
        menu.items.first { $0.title == title }
    }

    @discardableResult
    func leftoverMeeting(at date: Date, failure: String? = nil, transcript: Bool = false) throws -> MeetingFolder {
        let meeting = try MeetingFolder.create(in: root, startingAt: date)
        FileManager.default.createFile(atPath: meeting.audioURL(.system).path, contents: Data())
        if transcript { try meeting.write("**[00:00:01] Them:** Hello", to: .transcript) }
        if let failure { try meeting.write(failure, to: .failure) }
        return meeting
    }
}
