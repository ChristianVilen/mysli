import Foundation

/// `<name>/` exists only when the model is complete: that is the only install
/// state. A download writes `.<name>.partial/`, which the next download
/// continues in, and holds `.lock`, because the hub downloader appends to
/// fixed `.incomplete` paths that two Ku-Ka processes would corrupt.
struct ModelInstall {
    let root: URL
    let name: String
    let label: String
    /// How long `install` waits while another Ku-Ka holds the lock.
    var lockWait: Duration = .zero

    var folder: URL { root.appendingPathComponent(name, isDirectory: true) }
    private var partial: URL { root.appendingPathComponent(".\(name).partial", isDirectory: true) }

    var isInstalled: Bool { FileManager.default.fileExists(atPath: folder.path) }

    /// Calls `download` only while this Ku-Ka holds the lock and the model is
    /// still missing. A failed or cancelled `download` keeps the partial folder.
    @concurrent
    func install(using download: (URL) async throws -> Void) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        excludeFromBackup()
        guard let lock = try await acquireLock() else { return }
        defer { lock.release() }
        // Another Ku-Ka can install the model and release the lock before this one gets it.
        guard !isInstalled else { return }
        try await download(partial)
        try FileManager.default.moveItem(at: partial, to: folder)
    }

    /// Nil if another Ku-Ka installed the model while holding the lock.
    private func acquireLock() async throws -> FileLock? {
        let clock = ContinuousClock()
        let deadline = clock.now + lockWait
        while true {
            do {
                return try FileLock.acquire(at: root.appendingPathComponent(".lock"))
            } catch FileLockError.held {
                if isInstalled { return nil }
                guard clock.now < deadline else {
                    throw MeetingStepError("Another Ku-Ka is downloading the \(label) model.")
                }
                try await Task.sleep(for: .milliseconds(250))
            } catch FileLockError.failed(let reason) {
                throw MeetingStepError("Ku-Ka could not lock the \(label) models folder \(root.path): \(reason).")
            }
        }
    }

    func excludeFromBackup() {
        var folder = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try folder.setResourceValues(values)
        } catch {
            NSLog("Ku-Ka: could not exclude the \(label) model cache from backups: \(error)")
        }
    }
}
