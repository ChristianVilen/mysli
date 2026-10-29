import Foundation

enum MeetingTrack: CaseIterable, Hashable {
    case microphone
    case system

    var fileName: String {
        switch self {
        case .microphone: return "me.caf"
        case .system: return "them.caf"
        }
    }

    var speaker: Speaker {
        switch self {
        case .microphone: return .me
        case .system: return .them
        }
    }
}

/// Only `Transcript.merge` makes `.room`. In one transcript the room numbers run 1...N in the
/// order of each voice's first line, and the microphone lines are all `.me` or all `.room`.
enum Speaker: Hashable, Sendable {
    case me
    case them
    case room(Int)

    var label: String {
        switch self {
        case .me: return "Me"
        case .them: return "Them"
        case .room(let number): return "Room \(number)"
        }
    }

    var track: MeetingTrack {
        switch self {
        case .me, .room: return .microphone
        case .them: return .system
        }
    }
}

/// Only the transcript, the summary, and the failure (and the audio) decide `MeetingStage`.
enum MeetingDocument: String, CaseIterable {
    case transcript = "transcript.md"
    case summary = "summary.md"
    case failure = "error.md"
    /// The transcript as the transcriber wrote it, before known words.
    case heardTranscript = ".transcript-as-heard.md"
    /// Only the summarize step writes this, before `summary.md`.
    case questions = "review.json"
    /// Only `saveSkip` writes this, after `summary.md`.
    case skipped = "review-skipped.json"
}

enum MeetingStep: Equatable {
    case transcribe
    case summarize

    var failureHeading: String {
        switch self {
        case .transcribe: return "Transcription Failed"
        case .summarize: return "Summary Failed"
        }
    }
}

enum MeetingModel: Equatable {
    case speech
    case speaker
}

enum MeetingProgress: Equatable {
    case step(MeetingStep)
    case downloading(MeetingModel)

    var title: String {
        switch self {
        case .step(.transcribe): return "Transcribing"
        case .step(.summarize): return "Summarizing"
        case .downloading(.speech): return "Downloading speech model"
        case .downloading(.speaker): return "Downloading speaker model"
        }
    }
}

struct MeetingFolderContents: Equatable {
    var audio: Set<MeetingTrack> = []
    var hasTranscript = false
    var hasSummary = false
    var hasFailure = false
}

enum MeetingStage: Equatable {
    case pending(MeetingStep)
    case failed(MeetingStep)
    case done

    init?(_ contents: MeetingFolderContents) {
        let next: MeetingStep?
        if contents.hasSummary {
            next = nil
        } else if contents.hasTranscript {
            next = .summarize
        } else if !contents.audio.isEmpty {
            next = .transcribe
        } else {
            return nil
        }
        switch next {
        case nil: self = .done
        case let step?: self = contents.hasFailure ? .failed(step) : .pending(step)
        }
    }
}

struct MeetingFolder: Hashable {
    /// Resolves the root with `realpath` (including "/var" to "/private/var") before adding the name,
    /// so every value for one meeting compares equal, even before its folder exists.
    let url: URL

    init(url: URL) {
        self.init(name: url.lastPathComponent, inResolved: Self.resolved(url.deletingLastPathComponent()))
    }

    private init(name: String, inResolved root: URL) {
        url = root.appendingPathComponent(name, isDirectory: true)
    }

    /// `URL.resolvingSymlinksInPath()` is not used: it removes "/private" only from a path that
    /// exists, and it resolves nothing in a path that does not exist yet. The parts at the end that
    /// do not exist yet are kept as given.
    private static func resolved(_ folder: URL) -> URL {
        let path = folder.standardizedFileURL.path
        if let real = realpath(path, nil) {
            defer { free(real) }
            return URL(fileURLWithPath: String(cString: real), isDirectory: true)
        }
        let parent = folder.standardizedFileURL.deletingLastPathComponent()
        guard parent.path != path else { return URL(fileURLWithPath: path, isDirectory: true) }
        return resolved(parent).appendingPathComponent(folder.lastPathComponent, isDirectory: true)
    }

    var name: String { url.lastPathComponent }

    static func folderName(startingAt date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return formatter.string(from: date)
    }

    var title: String {
        guard let match = name.wholeMatch(of: #/(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})(?:-(\d+))?/#) else {
            return name
        }
        let title = "Meeting on \(match.1) at \(match.2):\(match.3)"
        return match.4.map { "\(title) (\($0))" } ?? title
    }

    static func create(in root: URL, startingAt date: Date) throws -> MeetingFolder {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let root = resolved(root)
        let base = folderName(startingAt: date)
        var suffix = 1
        while true {
            let name = suffix == 1 ? base : "\(base)-\(suffix)"
            let meeting = MeetingFolder(name: name, inResolved: root)
            do {
                // Without intermediate directories this fails when the folder
                // exists, so the check and the claim are one step.
                try fileManager.createDirectory(at: meeting.url, withIntermediateDirectories: false)
            } catch CocoaError.fileWriteFileExists {
                suffix += 1
                continue
            }
            try fileManager.createDirectory(at: meeting.audioFolder, withIntermediateDirectories: false)
            return meeting
        }
    }

    /// The resolved root is listed, because `contentsOfDirectory(at:)` fails for a root that is
    /// itself a symlink. A meeting folder that is a symlink is not a meeting.
    static func all(in root: URL) -> [(MeetingFolder, MeetingStage)] {
        let root = resolved(root)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        return urls
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { MeetingFolder(name: $0.lastPathComponent, inResolved: root) }
            .sorted { $0.name < $1.name }
            .compactMap { meeting in meeting.stage().map { (meeting, $0) } }
    }

    func audioURL(_ track: MeetingTrack) -> URL {
        audioFolder.appendingPathComponent(track.fileName)
    }

    func url(for document: MeetingDocument) -> URL {
        url.appendingPathComponent(document.rawValue)
    }

    func stage() -> MeetingStage? {
        let fileManager = FileManager.default
        return MeetingStage(MeetingFolderContents(
            audio: Set(MeetingTrack.allCases.filter { fileManager.fileExists(atPath: audioURL($0).path) }),
            hasTranscript: fileManager.fileExists(atPath: url(for: .transcript).path),
            hasSummary: fileManager.fileExists(atPath: url(for: .summary).path),
            hasFailure: fileManager.fileExists(atPath: url(for: .failure).path)))
    }

    func write(_ text: String, to document: MeetingDocument) throws {
        // Atomic: stage() treats an existing file as a finished step, so a
        // half-written file must never have the real name.
        try Data(text.utf8).write(to: url(for: document), options: .atomic)
    }

    func read(_ document: MeetingDocument) throws -> String {
        try String(contentsOf: url(for: document), encoding: .utf8)
    }

    /// When the heard copy is missing, saves `transcript.md` without its correction note as the copy.
    /// Later runs use that copy so corrections never apply twice.
    func heardTranscript() throws -> String {
        do {
            return try read(.heardTranscript)
        } catch CocoaError.fileReadNoSuchFile {
            let heard = Transcript.withoutCorrectionNote(try read(.transcript))
            try write(heard, to: .heardTranscript)
            return heard
        }
    }

    func clearFailure() throws {
        let failure = url(for: .failure)
        guard FileManager.default.fileExists(atPath: failure.path) else { return }
        try FileManager.default.removeItem(at: failure)
    }

    /// True while the room labeller loads its model and diarizes. Left behind, it means that an
    /// earlier attempt stopped there, for example in a crash. `stage()` never reads it.
    var roomLabelsStarted: Bool {
        FileManager.default.fileExists(atPath: roomLabelsMarker.path)
    }

    func markRoomLabelsStarted() throws {
        try Data().write(to: roomLabelsMarker, options: .atomic)
    }

    /// Accepts a missing marker: a cancel during labelling can remove it first.
    func clearRoomLabelsStarted() throws {
        do {
            try FileManager.default.removeItem(at: roomLabelsMarker)
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    private var roomLabelsMarker: URL {
        url.appendingPathComponent(".room-labels-started")
    }

    func discardAudio(trash: (URL) throws -> Void) throws {
        guard FileManager.default.fileExists(atPath: audioFolder.path) else { return }
        try trash(audioFolder)
    }

    /// Throws `MeetingLockError.held` when a recorder or processor already
    /// holds the folder, in this process or another Ku-Ka, and `.failed`
    /// when the folder cannot be locked at all: it is gone, read-only, or
    /// on a file system without `flock`.
    func lock() throws -> FileLock {
        do {
            return try FileLock.acquire(at: url.appendingPathComponent(".lock"))
        } catch FileLockError.held {
            throw MeetingLockError.held(self)
        } catch FileLockError.failed(let reason) {
            throw MeetingLockError.failed(self, reason: reason)
        }
    }

    private var audioFolder: URL {
        url.appendingPathComponent("audio", isDirectory: true)
    }
}

enum MeetingLockError: LocalizedError, Equatable {
    case held(MeetingFolder)
    case failed(MeetingFolder, reason: String)

    var errorDescription: String? {
        switch self {
        case .held(let meeting):
            return "Another Ku-Ka is using the meeting folder \(meeting.url.path)."
        case .failed(let meeting, let reason):
            return "Ku-Ka could not lock the meeting folder \(meeting.url.path): \(reason)."
        }
    }
}

enum FileLockError: Error, Equatable {
    case held
    case failed(reason: String)
}

/// The system also releases the `flock` when the process ends, so a crash
/// leaves no stale lock behind.
final class FileLock {
    private var descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    static func acquire(at url: URL) throws -> FileLock {
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw FileLockError.failed(reason: String(cString: strerror(errno))) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            throw code == EWOULDBLOCK ? FileLockError.held : .failed(reason: String(cString: strerror(code)))
        }
        return FileLock(descriptor: descriptor)
    }

    func release() {
        guard descriptor >= 0 else { return }
        close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}
