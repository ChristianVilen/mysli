import XCTest
import Darwin
@testable import KuKa

final class MeetingContextFileTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testAbsentAndBlankFilesGiveNoContext() throws {
        XCTAssertNil(MeetingContextFile(url: { nil }).read())
        let file = root.appendingPathComponent("context.md")
        let reader = MeetingContextFile(url: { file })
        XCTAssertNil(reader.read())
        for text in ["", " \n\t"] {
            try Data(text.utf8).write(to: file)
            XCTAssertNil(reader.read())
        }
    }

    func testReadsFreshBytesAndTheFreshPathWithoutChangingTheText() throws {
        var file = root.appendingPathComponent("first.md")
        let reader = MeetingContextFile(url: { file })
        try Data(" First\n".utf8).write(to: file)
        XCTAssertEqual(reader.read(), " First\n")
        try Data("Second".utf8).write(to: file)
        XCTAssertEqual(reader.read(), "Second")
        file = root.appendingPathComponent("second.md")
        try Data("Third".utf8).write(to: file)
        XCTAssertEqual(reader.read(), "Third")
    }

    func testLimitCountsUTF8BytesAndRejectsTheWholeOversizedFile() throws {
        let file = root.appendingPathComponent("context.md")
        let reader = MeetingContextFile(url: { file })
        let exact = String(repeating: "ä", count: 8192)
        try Data(exact.utf8).write(to: file)
        XCTAssertEqual(reader.read(), exact)
        try Data((exact + "x").utf8).write(to: file)
        XCTAssertNil(reader.read())
        let ascii = String(repeating: "a", count: 16384)
        try Data(ascii.utf8).write(to: file)
        XCTAssertEqual(reader.read(), ascii)
        try Data((ascii + "x").utf8).write(to: file)
        XCTAssertNil(reader.read())
        try Data([0xff]).write(to: file)
        XCTAssertNil(reader.read())
    }

    func testNULInUTF8TextOmitsTheWholeFile() throws {
        let file = root.appendingPathComponent("context.md")
        try Data("Project: Konvio\u{0}\nPeople: Aino".utf8).write(to: file)
        XCTAssertNil(MeetingContextFile(url: { file }).read())
    }

    func testFollowsASymlinkToARegularFile() throws {
        let file = root.appendingPathComponent("target.md")
        let link = root.appendingPathComponent("context.md")
        try Data("Background".utf8).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertEqual(MeetingContextFile(url: { link }).read(), "Background")
    }

    func testRejectsDirectoriesAndFIFOsWithoutWaitingForAWriter() throws {
        XCTAssertNil(MeetingContextFile(url: { self.root }).read())
        let fifo = root.appendingPathComponent("fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertNil(MeetingContextFile(url: { fifo }).read())
    }

    func testUnreadableFileIsOmitted() throws {
        let file = root.appendingPathComponent("private-%d-%@.md")
        try Data("secret".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        XCTAssertNil(MeetingContextFile(url: { file }).read())
    }
}
