import XCTest
@testable import KuKa

// MARK: - Mock FileManager

class MockFileManager: FileManaging {
    var homeDirectoryForCurrentUser: URL = URL(fileURLWithPath: "/tmp/kuka-test")
    var createdDirectories: [URL] = []
    var writtenFiles: [(data: Data, url: URL)] = []
    var removedItems: [URL] = []

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]?) throws {
        createdDirectories.append(url)
    }

    func writeImageData(_ data: Data, to url: URL) throws {
        writtenFiles.append((data, url))
    }

    func removeItem(at url: URL) throws {
        removedItems.append(url)
    }

    func fileExists(at url: URL) -> Bool {
        writtenFiles.contains { $0.url == url } && !removedItems.contains(url)
    }
}

// MARK: - Mock Clipboard

class MockClipboard: ClipboardManaging {
    var copiedCount = 0
    var clearedCount = 0
    var lastTiffData: Data?
    var lastPngData: Data?

    func copyImage(tiffData: Data?, pngData: Data) {
        copiedCount += 1
        lastTiffData = tiffData
        lastPngData = pngData
    }

    func clearClipboard() {
        clearedCount += 1
    }
}

// MARK: - Mock Screen Capture

class MockScreenCapture: ScreenCapturing {
    var imageToReturn: CGImage?
    var windowImageToReturn: CGImage?

    func captureScreen(rect: CGRect) async -> CGImage? {
        imageToReturn
    }

    func captureWindow(windowID: CGWindowID) async -> CGImage? {
        windowImageToReturn ?? imageToReturn
    }

    /// Creates a 1x1 red CGImage for testing
    static func make1x1Image() -> CGImage {
        makeImage(width: 1, height: 1)
    }

    /// Creates a solid-color CGImage of the given pixel size (red by default)
    static func makeImage(width: Int, height: Int, red: CGFloat = 1, green: CGFloat = 0, blue: CGFloat = 0) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}

// MARK: - Mock WindowListProvider

class MockWindowListProvider: WindowListProvider {
    var windows: [WindowInfo] = []

    func windowsOnScreen() -> [WindowInfo] {
        windows
    }
}

// MARK: - Mock WindowControlling (window tiling)

@MainActor
class MockWindowControlling: WindowControlling {
    var focusedWindowToReturn: FocusedWindow?
    /// What `setFrame` returns on every call — set to `nil` to simulate a
    /// failed move (e.g. the AX re-read failing).
    var achievedFrameToReturn: CGRect?
    private(set) var setFrameCalls: [(frame: CGRect, handle: WindowHandle)] = []

    func focusedWindow() -> FocusedWindow? {
        focusedWindowToReturn
    }

    @discardableResult
    func setFrame(_ frame: CGRect, of handle: WindowHandle) -> CGRect? {
        setFrameCalls.append((frame, handle))
        return achievedFrameToReturn
    }
}

// MARK: - Mock StageManagerDetecting

class MockStageManagerDetecting: StageManagerDetecting {
    var isStageManagerEnabled: Bool = false
}

// MARK: - Fake Sleep Preventer

class FakeSleepPreventer: SleepPreventing {
    private(set) var beginCount = 0
    private(set) var endCount = 0
    private(set) var lastReason: String?
    private(set) var lastKeepDisplayAwake: Bool?
    private(set) var isPreventing = false
    /// One-shot failure switch for exercising assertion-creation failure.
    var failNextBegin = false

    func begin(reason: String, keepDisplayAwake: Bool) -> Bool {
        guard !isPreventing else { return true }
        if failNextBegin {
            failNextBegin = false
            return false
        }
        isPreventing = true
        beginCount += 1
        lastReason = reason
        lastKeepDisplayAwake = keepDisplayAwake
        return true
    }

    func end() {
        guard isPreventing else { return }
        isPreventing = false
        endCount += 1
    }
}

// MARK: - Fake ImageStore

class FakeImageStore: ImageStoring {
    private(set) var storedImages: [CGImage] = []
    private(set) var combinedCalls: [(top: NSImage, bottom: NSImage)] = []
    private(set) var annotatedCalls: [(image: NSImage, url: URL)] = []
    private(set) var deletedURLs: [URL] = []
    var combinedResultToReturn: CaptureResult?

    func store(cgImage: CGImage) -> CaptureResult {
        storedImages.append(cgImage)
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return CaptureResult(image: image, fileURL: URL(fileURLWithPath: "/tmp/kuka-test/stored-\(storedImages.count).png"))
    }

    func storeCombined(top: NSImage, bottom: NSImage) -> CaptureResult? {
        combinedCalls.append((top, bottom))
        return combinedResultToReturn
    }

    func saveAnnotated(image: NSImage, to url: URL) {
        annotatedCalls.append((image, url))
    }

    func delete(at url: URL) {
        deletedURLs.append(url)
    }
}

// MARK: - Fake LoginItem

class FakeLoginItem: LoginItemManaging {
    var isEnabled = false
    var errorToThrow: Error?
    private(set) var setCalls: [Bool] = []

    func setEnabled(_ enabled: Bool) throws {
        if let errorToThrow { throw errorToThrow }
        setCalls.append(enabled)
        isEnabled = enabled
    }
}

// MARK: - Fake Screens

struct FakeScreens: Screens {
    var all: [ScreenGeometry] = []
    var mainIndex: Int?
}

// MARK: - Fake Pasteboard

class FakePasteboard: PasteboardReading, PasteboardWriting {
    var changeCount = 0
    /// Scripted result for the next `readCurrentItem` call.
    var currentItem: ClipboardItem?
    private(set) var readCount = 0
    private(set) var lastNow: Date?
    private(set) var writes: [(item: ClipboardItem, withFormatting: Bool)] = []
    /// Fires synchronously from `write`, before it returns — lets a test
    /// observe exactly when a write happened relative to other calls.
    var onWrite: (() -> Void)?

    func readCurrentItem(now: Date) -> ClipboardItem? {
        readCount += 1
        lastNow = now
        return currentItem
    }

    func write(_ item: ClipboardItem, withFormatting: Bool) -> Int {
        writes.append((item, withFormatting))
        // Mimics the real pasteboard: a write becomes what's "currently"
        // there and bumps changeCount, so a subsequent poll reads it back
        // as new content.
        currentItem = item
        changeCount += 1
        // Captured immediately, before onWrite fires — mirrors
        // SystemPasteboard, where clearContents() hands back the change
        // count before any later step (or, here, a test's onWrite hook
        // simulating a racing third-party copy) can bump it further.
        let newChangeCount = changeCount
        onWrite?()
        return newChangeCount
    }
}

// MARK: - Fake Keystroke Sender

class FakeKeystrokeSender: KeystrokeSending {
    private(set) var sendCount = 0

    func sendPasteKeystroke() {
        sendCount += 1
    }
}

class FakeNotifier: Notifying {
    private(set) var permissionRequests = 0
    private(set) var posted: [(title: String, body: String, url: URL?)] = []

    func requestPermission() {
        permissionRequests += 1
    }

    func post(title: String, body: String, opening url: URL?) {
        posted.append((title, body, url))
    }
}

class FakeActiveRecording: ActiveRecording {
    var endReason: String?
    private(set) var stopCount = 0

    func stop() {
        stopCount += 1
    }
}

class FakeMeetingAudioCapture: MeetingAudioCapturing {
    var startError: Error?
    /// Ends the capture with this reason before `start` returns.
    var endsWhileStarting: String?
    private(set) var recordings: [FakeActiveRecording] = []
    private var interruptHandler: (@MainActor (String) -> Void)?

    @MainActor
    func start(into meeting: MeetingFolder,
               onInterrupted: @escaping @MainActor (String) -> Void) async throws -> ActiveRecording {
        if let startError { throw startError }
        for track in MeetingTrack.allCases {
            FileManager.default.createFile(atPath: meeting.audioURL(track).path, contents: Data())
        }
        interruptHandler = onInterrupted
        let recording = FakeActiveRecording()
        recordings.append(recording)
        if let reason = endsWhileStarting {
            recording.endReason = reason
            onInterrupted(reason)
        }
        return recording
    }

    @MainActor
    func interrupt(reason: String) {
        interruptHandler?(reason)
    }
}

class FakeTranscriber: Transcribing {
    let name: String
    var byFileName: [String: Result<TrackTranscript, Error>] = [:]
    var modelIsMissing = false
    var failure: (stage: TranscriberFailure.Stage, error: Error)?
    private(set) var downloads: [String] = []
    private(set) var loads: [String] = []
    private(set) var transcribed: [String] = []

    init(name: String = "Fake") {
        self.name = name
    }

    func needsDownload(for locale: Locale) async throws -> Bool {
        if let failure, failure.stage == .unavailable { throw failure.error }
        return modelIsMissing
    }

    func download(for locale: Locale) async throws {
        downloads.append(locale.identifier(.bcp47))
        if let failure, failure.stage == .download { throw failure.error }
        modelIsMissing = false
    }

    func load(for locale: Locale) async throws -> any TranscriptionSession {
        loads.append(locale.identifier(.bcp47))
        if let failure, failure.stage == .load { throw failure.error }
        return Session(transcriber: self)
    }

    func transcribe(_ audio: URL) async throws -> TrackTranscript {
        transcribed.append(audio.lastPathComponent)
        return try byFileName[audio.lastPathComponent, default: .success(TrackTranscript(segments: [], duration: 0))].get()
    }

    private struct Session: TranscriptionSession {
        let transcriber: FakeTranscriber

        func transcribe(_ audio: URL) async throws -> TrackTranscript {
            try await transcriber.transcribe(audio)
        }
    }
}

class FakeCommandRunner: CommandRunning {
    var results: [String: Result<CommandResult, Error>] = [:]
    private(set) var calls: [(executable: URL, arguments: [String], input: String?, searchPath: [String])] = []

    func run(executable: URL, arguments: [String], input: String?, searchPath: [String],
             timeout: Duration) async throws -> CommandResult {
        calls.append((executable, arguments, input, searchPath))
        return try results[executable.lastPathComponent,
                           default: .success(CommandResult(termination: .exited(127), stdout: "", stderr: "not faked"))].get()
    }
}

extension XCTestCase {
    func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KuKaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

@MainActor
func waitUntil(_ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(5)
    while !condition(), Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

func localDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day,
                                               hour: hour, minute: minute, second: second))!
}
