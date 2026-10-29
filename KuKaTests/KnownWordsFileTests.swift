import XCTest
@testable import KuKa

final class KnownWordsFileTests: XCTestCase {
    private var folder: URL!
    private var listURL: URL!
    private var lockURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        folder = try makeTemporaryDirectory()
        listURL = folder.appendingPathComponent("Meetings/known-words.md")
        lockURL = folder.appendingPathComponent("Application Support/Ku-Ka/known-words.lock")
    }

    private func list() -> KnownWordsFile {
        KnownWordsFile(url: { [listURL] in listURL! }, lockURL: lockURL, now: { localDate(2026, 10, 28, 10, 0) })
    }

    private func write(_ text: String, to url: URL? = nil) throws {
        let url = url ?? listURL!
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func testEachReadSeesTheFileAsItIsNow() throws {
        let file = list()
        try write("- Convio → **Konvio** ✓\n")
        XCTAssertEqual(file.read().words.map(\.right), ["Konvio"])

        try write("- Convio → **Konvio** ✓\n- Yuri → **Jyri**\n")

        XCTAssertEqual(file.read().words.map(\.right), ["Konvio", "Jyri"])
    }

    func testAMissingFileReadsAsAnEmptyList() {
        let read = list().read()

        XCTAssertEqual(read.words, [])
        XCTAssertEqual(read.correctAsHeard, [])
    }

    func testAddCreatesAMissingFolderAndFileThatStartsWithTheHeader() throws {
        try list().add(.replacement(heard: "Konvya", right: "Konvio", confirmed: true))

        XCTAssertEqual(try String(contentsOf: listURL, encoding: .utf8), KnownWordsList.newFileHeader
            + "\n## Added by Ku-Ka\n\n- Konvya → **Konvio** ✓ confirmed 2026-10-28 by Ku-Ka\n")
    }

    func testAddReadsTheFileAgainSoALineThatAnotherEditorWroteIsKept() throws {
        let file = list()
        try write("- Convio → **Konvio** ✓\n")
        _ = file.read()
        try write("- Convio → **Konvio** ✓\n- Yuri → **Jyri**\n")

        try file.add(.replacement(heard: "Konvya", right: "Konvio", confirmed: true))

        XCTAssertEqual(try String(contentsOf: listURL, encoding: .utf8),
                       "- Convio → **Konvio** ✓\n- Konvya → **Konvio** ✓ confirmed 2026-10-28 by Ku-Ka\n- Yuri → **Jyri**\n")
    }

    func testAddOfAnAnswerTheListAlreadyHasDoesNotTouchTheFile() throws {
        try write("- Convio → **Konvio** ✓\n")
        let lastWeek = localDate(2026, 10, 21, 9, 0)
        try FileManager.default.setAttributes([.modificationDate: lastWeek], ofItemAtPath: listURL.path)

        try list().add(.replacement(heard: "convio", right: "Konvio", confirmed: true))

        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: listURL.path)[.modificationDate] as? Date, lastWeek)
        XCTAssertEqual(try String(contentsOf: listURL, encoding: .utf8), "- Convio → **Konvio** ✓\n")
    }

    func testAddThroughASymlinkChangesTheTargetAndKeepsTheLink() throws {
        let target = folder.appendingPathComponent("dotfiles/terms.md")
        try write("- Convio → **Konvio** ✓\n", to: target)
        try FileManager.default.createDirectory(at: listURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: listURL, withDestinationURL: target)

        try list().add(.replacement(heard: "Konvya", right: "Konvio", confirmed: true))

        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: listURL.path), target.path)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8),
                       "- Convio → **Konvio** ✓\n- Konvya → **Konvio** ✓ confirmed 2026-10-28 by Ku-Ka\n")
    }

    func testAddWhileAnotherHolderHasTheLockThrowsBusyAndLeavesTheFileUnchanged() throws {
        try write("- Convio → **Konvio** ✓\n")
        try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let otherKuKa = try FileLock.acquire(at: lockURL)
        defer { otherKuKa.release() }

        XCTAssertThrowsError(try list().add(.replacement(heard: "Konvya", right: "Konvio", confirmed: true))) {
            XCTAssertEqual($0 as? KnownWordsFileError, .busy)
        }
        XCTAssertEqual(try String(contentsOf: listURL, encoding: .utf8), "- Convio → **Konvio** ✓\n")
        XCTAssertEqual(KnownWordsFileError.busy.localizedDescription, "Another Ku-Ka is saving to the known-words list. Try again.")
    }

    func testAFileThatIsNotUTF8ReadsAsEmptyAndAddLeavesItsBytesUnchanged() throws {
        let latin1 = try XCTUnwrap("- Mäkki -> **Mäki**\n".data(using: .isoLatin1))
        try FileManager.default.createDirectory(at: listURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try latin1.write(to: listURL)

        XCTAssertEqual(list().read().words, [])
        XCTAssertThrowsError(try list().add(.replacement(heard: "Konvya", right: "Konvio", confirmed: true))) {
            XCTAssertEqual($0 as? KnownWordsFileError, .notText(path: listURL.path))
        }
        XCTAssertEqual(try Data(contentsOf: listURL), latin1)
        XCTAssertEqual(KnownWordsFileError.notText(path: "/Users/test/terms.md").localizedDescription,
                       "Ku-Ka cannot read /Users/test/terms.md as text, so it did not change it.")
    }

    func testAnAnswerThatTheListWouldNotReadBackIsRefusedAndTheFileIsUnchanged() throws {
        let unclosed = [
            "---\ntitle: Terms\n- Convio → **Konvio** ✓\n",
            "# Terms\n\n```\n- Convio → **Konvio** ✓\n",
        ]
        for text in unclosed {
            try write(text)
            for addition in [try KnownWordAddition.replacement(heard: "Konvya", right: "Konvio", confirmed: true),
                             try KnownWordAddition.correctAsHeard("Aino")] {
                XCTAssertThrowsError(try list().add(addition), "\(text)") {
                    XCTAssertEqual($0 as? KnownWordsFileError, .notReadBack(path: listURL.path))
                }
            }
            XCTAssertEqual(try String(contentsOf: listURL, encoding: .utf8), text)
        }
        XCTAssertEqual(KnownWordsFileError.notReadBack(path: "/Users/test/terms.md").localizedDescription,
                       "Ku-Ka did not change /Users/test/terms.md, because it could not read the new line back. Check that the “---” block at the top and every code block (```) in the list are closed.")
    }

    func testAWriteOrALockThatFailsThrowsCouldNotWriteAndLeavesTheFileUnchanged() throws {
        try write("- Convio → **Konvio** ✓\n")
        try write("", to: lockURL)

        for (readOnly, permissions) in [(listURL.deletingLastPathComponent(), 0o755), (lockURL!, 0o644)] {
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: readOnly.path) }

            XCTAssertThrowsError(try list().add(.replacement(heard: "Konvya", right: "Konvio", confirmed: true))) { error in
                guard case .couldNotWrite(let path, let reason)? = error as? KnownWordsFileError else {
                    return XCTFail("\(readOnly.lastPathComponent): \(error)")
                }
                XCTAssertEqual(path, listURL.path)
                XCTAssertFalse(reason.isEmpty || reason.hasSuffix("."), reason)
            }
            XCTAssertEqual(try String(contentsOf: listURL, encoding: .utf8), "- Convio → **Konvio** ✓\n")
        }
        XCTAssertEqual(KnownWordsFileError.couldNotWrite(path: "/Users/test/terms.md", reason: "Permission denied").localizedDescription,
                       "Ku-Ka could not save to /Users/test/terms.md: Permission denied.")
    }
}
