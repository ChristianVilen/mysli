import Foundation

enum KnownWordsFileError: LocalizedError, Equatable {
    case busy
    /// The bytes are not UTF-8. Ku-Ka leaves the file unchanged.
    case notText(path: String)
    /// The folder, the lock, the read, or the write failed. `reason` has no final period.
    case couldNotWrite(path: String, reason: String)
    /// The list would not read the new line, for example because it is after a "---" block or a
    /// code block that is never closed. Ku-Ka leaves the file unchanged.
    case notReadBack(path: String)

    var errorDescription: String? {
        switch self {
        case .busy: return "Another Ku-Ka is saving to the known-words list. Try again."
        case .notText(let path): return "Ku-Ka cannot read \(path) as text, so it did not change it."
        case .notReadBack(let path):
            return "Ku-Ka did not change \(path), because it could not read the new line back. Check that the “---” block at the top and every code block (```) in the list are closed."
        case .couldNotWrite(let path, let reason): return "Ku-Ka could not save to \(path): \(reason)."
        }
    }
}

/// The known-words list on disk. It reads the file at each use and keeps no copy, because the user
/// and the user's own tools edit the file at any time.
struct KnownWordsFile {
    /// Not next to the list, so Ku-Ka puts no file in the folder of the user's own list.
    static let defaultLockURL = URL.applicationSupportDirectory.appendingPathComponent("Ku-Ka/known-words.lock")

    private let url: () -> URL
    private let lockURL: URL
    private let now: () -> Date

    /// `url` is read at each use, as `Settings.meetingsFolder` is.
    init(url: @escaping () -> URL, lockURL: URL = KnownWordsFile.defaultLockURL, now: @escaping () -> Date = { Date() }) {
        self.url = url
        self.lockURL = lockURL
        self.now = now
    }

    /// A missing file is an empty list. A file that cannot be read or is not UTF-8 is logged and
    /// read as empty, so a problem with the list never stops a summary.
    func read() -> KnownWordsList {
        let url = url()
        do {
            guard let markdown = try Self.text(at: url) else {
                Log.meeting.error("The known-words list \(url.path, privacy: .public) is not UTF-8 text, so Ku-Ka does not use it.")
                return .empty
            }
            return KnownWordsList(markdown: markdown)
        } catch {
            Log.meeting.error("Could not read the known-words list \(url.path, privacy: .public) (code \((error as NSError).code)): \(error.localizedDescription)")
            return .empty
        }
    }

    /// Inserts the line for `addition`, creating the folder and the file when they are missing, and
    /// writes nothing when the list already says it or would not read the new line back. Under the
    /// lock it reads the file again and writes the whole file atomically to the path with symlinks
    /// resolved, so a link stays a link. The lock stops only another Ku-Ka: an edit by a text editor
    /// is lost only when it lands between the read and the rename. On a throw the file is unchanged.
    func add(_ addition: KnownWordAddition) throws {
        let listed = url()
        do {
            try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let lock = try FileLock.acquire(at: lockURL)
            defer { lock.release() }
            try insert(addition, into: listed)
        } catch FileLockError.held {
            throw KnownWordsFileError.busy
        } catch let error as KnownWordsFileError {
            throw error
        } catch FileLockError.failed(let reason) {
            throw KnownWordsFileError.couldNotWrite(path: listed.path, reason: reason)
        } catch {
            let reason = error.localizedDescription
            throw KnownWordsFileError.couldNotWrite(path: listed.path, reason: reason.hasSuffix(".") ? String(reason.dropLast()) : reason)
        }
    }

    private func insert(_ addition: KnownWordAddition, into listed: URL) throws {
        let target = listed.resolvingSymlinksInPath()
        guard let markdown = try Self.text(at: target) else { throw KnownWordsFileError.notText(path: listed.path) }
        guard let text = KnownWordsList(markdown: markdown).adding(addition, on: now()) else { return }
        // Without this, an answer would land in an unclosed block, and each later answer would add
        // another "Added by Ku-Ka" heading.
        guard KnownWordsList(markdown: text).says(addition) else { throw KnownWordsFileError.notReadBack(path: listed.path) }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: target, options: .atomic)
    }

    /// "" for a file that does not exist, and nil for bytes that are not UTF-8. The text keeps
    /// every byte, also a byte order mark, so writing it back changes nothing.
    private static func text(at url: URL) throws -> String? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return ""
        }
        return String(validating: data, as: UTF8.self)
    }
}
