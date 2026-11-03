import XCTest
@testable import KuKa

final class ModelInstallTests: XCTestCase {
    private var root: URL!
    private var downloads: [String] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = try makeTemporaryDirectory().appendingPathComponent("models", isDirectory: true)
        downloads = []
    }

    private var partial: String { root.path + "/.model.partial" }

    private func makeInstall(lockWait: Duration = .zero) -> ModelInstall {
        ModelInstall(root: root, name: "model", label: "Test", lockWait: lockWait, lockRetryInterval: .milliseconds(5))
    }

    /// Writes into the partial folder before it throws, so the partial-folder rules run for real.
    private func download(failingWith error: Error? = nil) -> (URL) async throws -> Void {
        { [unowned self] partial in
            downloads.append(partial.path)
            try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
            try Data("weights".utf8).write(to: partial.appendingPathComponent("model.bin"))
            if let error { throw error }
        }
    }

    private func folderContents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
    }

    private func lockAsAnotherKuKa() throws -> FileLock {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try FileLock.acquire(at: root.appendingPathComponent(".lock"))
    }

    func testTheModelIsInstalledOnlyByTheFinalRename() async throws {
        let install = makeInstall()
        XCTAssertFalse(install.isInstalled)

        try await install.install(using: download())

        XCTAssertTrue(install.isInstalled)
        XCTAssertEqual(downloads, [partial])
        XCTAssertEqual(try folderContents(), [".lock", "model"])
        XCTAssertEqual(try String(contentsOf: install.folder.appendingPathComponent("model.bin"), encoding: .utf8), "weights")
    }

    func testAFailedDownloadKeepsThePartialFolderAndTheNextDownloadResumesThere() async throws {
        let install = makeInstall()

        do {
            try await install.install(using: download(failingWith: TestError(errorDescription: "The network connection was lost.")))
            XCTFail("The download did not fail.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The network connection was lost.")
        }

        XCTAssertFalse(install.isInstalled)
        XCTAssertEqual(try folderContents(), [".lock", ".model.partial"])

        try await install.install(using: download())

        XCTAssertEqual(downloads, [partial, partial])
        XCTAssertEqual(try folderContents(), [".lock", "model"])
    }

    func testTheDownloadRunsOnlyWhileThisKuKaHoldsTheLock() async throws {
        let lock = root.appendingPathComponent(".lock")
        let writeModel = download()
        var lockDuringDownload: [String] = []

        try await makeInstall().install { partial in
            do {
                try FileLock.acquire(at: lock).release()
                lockDuringDownload.append("free")
            } catch FileLockError.held {
                lockDuringDownload.append("held")
            } catch {
                lockDuringDownload.append("\(error)")
            }
            try await writeModel(partial)
        }

        XCTAssertEqual(lockDuringDownload, ["held"])
    }

    func testAWaitingDownloadUsesTheModelThatAnotherKuKaInstalled() async throws {
        let install = makeInstall(lockWait: .seconds(5))
        let otherKuKa = try lockAsAnotherKuKa()
        let waiting = Task { try await install.install(using: download()) }
        try await Task.sleep(for: .milliseconds(30))

        try FileManager.default.createDirectory(at: install.folder, withIntermediateDirectories: false)
        otherKuKa.release()
        try await waiting.value

        XCTAssertEqual(downloads, [])
    }

    func testAWaitingDownloadStartsWhenAnotherKuKaStopsWithoutTheModel() async throws {
        let install = makeInstall(lockWait: .seconds(5))
        let otherKuKa = try lockAsAnotherKuKa()
        let waiting = Task { try await install.install(using: download()) }
        try await Task.sleep(for: .milliseconds(30))

        otherKuKa.release()
        try await waiting.value

        XCTAssertTrue(install.isInstalled)
        XCTAssertEqual(downloads, [partial])
    }

    func testAModelThatAnotherKuKaInstalledIsUsedAtOnceEvenWhileItHoldsTheLock() async throws {
        let install = makeInstall(lockWait: .seconds(5))
        let otherKuKa = try lockAsAnotherKuKa()
        defer { otherKuKa.release() }
        try FileManager.default.createDirectory(at: install.folder, withIntermediateDirectories: false)

        try await install.install(using: download())

        XCTAssertEqual(downloads, [])
    }

    func testInstallExcludesTheModelsFolderFromBackups() async throws {
        try await makeInstall().install(using: download())

        XCTAssertEqual(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }
}
