import Foundation
import Darwin

enum MeetingTypedNotesFile {
    static let maximumBytes = 65_536

    static func read(in meeting: MeetingFolder) throws -> String {
        let descriptor = open(meeting.url(for: .notes).path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { return "" }
            throw MeetingStepError("Could not read notes.md. Check the meeting folder and try again.")
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw MeetingStepError("notes.md must be a regular text file.")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw MeetingStepError(sizeMessage) }
        guard let text = String(data: data, encoding: .utf8), !text.utf8.contains(0) else {
            throw MeetingStepError("notes.md must be UTF-8 text without NUL characters.")
        }
        return text
    }

    static func validate(_ text: String) throws {
        guard text.utf8.count <= maximumBytes else { throw MeetingStepError(sizeMessage) }
        guard !text.utf8.contains(0) else { throw MeetingStepError("Remove the NUL character before saving these notes.") }
    }

    static let sizeMessage = "Notes can contain up to 64 KiB of text. Shorten them before saving."
}

enum TypedNotesSummaryState: Equatable {
    case idle
    case waitingForSave
    case queued
    case processing
    case summarizing(snapshot: String)
    case updated(snapshot: String)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .waitingForSave, .queued, .processing, .summarizing: true
        case .idle, .updated, .failed: false
        }
    }
}

enum TypedNotesSummaryResult {
    case updated(snapshot: String)
    case failed(String)

    var state: TypedNotesSummaryState {
        switch self {
        case .updated(let snapshot): return .updated(snapshot: snapshot)
        case .failed(let message): return .failed(message)
        }
    }
}

@MainActor
final class MeetingTypedNotesSession {
    let meeting: MeetingFolder
    private var lock: FileLock?
    private(set) var text: String
    private(set) var savedText: String
    private(set) var saveError: String?
    var context: () -> (recordingPhase: RecorderPhase, summaryState: TypedNotesSummaryState) = { (.idle, .idle) } {
        didSet { onChange?() }
    }
    var onChange: (() -> Void)?
    var onSaved: (() -> Void)?

    init(meeting: MeetingFolder) throws {
        self.meeting = meeting
        do {
            lock = try FileLock.acquire(at: meeting.url.appendingPathComponent(".notes.lock"))
        } catch FileLockError.held {
            throw MeetingStepError("Another Ku-Ka has these notes open. Close that notes window and try again.")
        }
        text = try MeetingTypedNotesFile.read(in: meeting)
        savedText = text
    }

    var hasUnsavedChanges: Bool { text != savedText || saveError != nil }
    var canUpdateSummary: Bool {
        let context = context()
        return Self.canUpdateSummary(meeting, recordingPhase: context.recordingPhase,
                                     summaryState: context.summaryState, hasUnsavedChanges: hasUnsavedChanges)
    }

    static func canUpdateSummary(_ meeting: MeetingFolder, recordingPhase: RecorderPhase,
                                 summaryState: TypedNotesSummaryState, hasUnsavedChanges: Bool) -> Bool {
        !recordingPhase.isCapturing && !summaryState.isBusy && !hasUnsavedChanges && meeting.stage() == .done
    }

    func edit(_ text: String) {
        self.text = text
        save()
    }

    func save() {
        do {
            guard lock != nil else { throw MeetingStepError("Reopen the notes window before editing this meeting.") }
            try MeetingTypedNotesFile.validate(text)
            guard try MeetingTypedNotesFile.read(in: meeting) == savedText else {
                throw MeetingStepError("notes.md changed outside this window. Copy your draft, then choose Reload saved notes.")
            }
            if hasUnsavedChanges { try meeting.write(text, to: .notes) }
            savedText = text
            saveError = nil
            onSaved?()
        } catch {
            saveError = error.localizedDescription
        }
        onChange?()
    }

    func reloadSavedNotes() {
        do {
            let saved = try MeetingTypedNotesFile.read(in: meeting)
            text = saved
            savedText = saved
            saveError = nil
            onSaved?()
        } catch {
            saveError = error.localizedDescription
        }
        onChange?()
    }

    @discardableResult
    func close() -> Bool {
        guard !hasUnsavedChanges else { return false }
        lock?.release()
        lock = nil
        return true
    }

    var summaryMessage: String {
        let (recordingPhase, summaryState) = context()
        if recordingPhase.isCapturing {
            return recordingPhase == .paused
                ? "Recording paused. You can keep writing."
                : "Recording. Your notes will be included after Stop."
        }
        switch summaryState {
        case .idle:
            return meeting.stage() == .done
                ? "Choose Update summary to use these saved notes."
                : "The summary will be available when processing finishes."
        case .waitingForSave: return "Save your notes to start the summary."
        case .queued: return "Waiting to make the summary."
        case .processing: return "Processing the recording. You can keep writing."
        case .summarizing(let snapshot):
            return snapshot == text
                ? "Making the summary. You can keep writing."
                : "Making the summary from earlier notes. Your latest edits will need an update."
        case .updated(let snapshot):
            return snapshot == text && !hasUnsavedChanges
                ? "Summary includes these saved notes."
                : "Saved notes have changed. Update the summary to include them."
        case .failed(let message): return message
        }
    }
}
