import XCTest
import os
@testable import Mysli

final class LogOutputTests: XCTestCase {
    private var root: URL!
    private let date = logDate("2026-10-30T11:00:00Z")
    private var folder: URL { root.appendingPathComponent("logs") }
    private var file: URL { folder.appendingPathComponent("Mysli-2026-10-30.log") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testBothOutputsReceiveOnlyRedactedMessagesWithTheSameLevelsAndMetadata() async throws {
        let received = OSAllocatedUnfairLock(initialState: [LogLine]())
        let output = makeOutput(received)
        let files = makeFiles()
        output.enableFiles(files)
        let log = Log(category: "meeting", output: output)
        let secret = "Aino said private meeting words"
        let detail: LogMessage = "detail: \(secret)"
        log.info("\(detail)")
        log.notice("\(detail)")
        log.error("\(detail)")
        await files.flush()

        let lines = received.withLock { $0 }
        XCTAssertEqual(lines.map(\.message), Array(repeating: "detail: <private>", count: 3))
        XCTAssertEqual(lines.map(\.level), [.info, .notice, .error])
        XCTAssertEqual(lines.map(\.category), ["meeting", "meeting", "meeting"])
        XCTAssertEqual(lines.map(\.processID), [123, 123, 123])
        XCTAssertEqual(lines.map(\.date), [date, date, date])
        XCTAssertEqual(try text(), """
            2026-10-30 11:00:00.000 +0000 [123] info meeting: detail: <private>
            2026-10-30 11:00:00.000 +0000 [123] notice meeting: detail: <private>
            2026-10-30 11:00:00.000 +0000 [123] error meeting: detail: <private>

            """)
    }

    func testFileOutputStartsOffAndEnablingItReachesExistingCategories() async throws {
        let received = OSAllocatedUnfairLock(initialState: [LogLine]())
        let output = makeOutput(received)
        let app = Log(category: "app", output: output)
        let teams = Log(category: "teams", output: output)
        app.info("before enabling")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        let files = makeFiles()
        output.enableFiles(files)
        app.info("after enabling")
        teams.notice("scan changed")
        await files.flush()
        XCTAssertEqual(received.withLock { $0.map(\.message) }, ["before enabling", "after enabling", "scan changed"])
        XCTAssertEqual(try text(), """
            2026-10-30 11:00:00.000 +0000 [123] info app: after enabling
            2026-10-30 11:00:00.000 +0000 [123] notice teams: scan changed

            """)
    }

    func testFileFailureReportingBypassesFilesAndKeepsErrorDetailsPrivate() async throws {
        let received = OSAllocatedUnfairLock(initialState: [LogLine]())
        let output = makeOutput(received)
        let files = makeFiles()
        output.enableFiles(files)
        output.reportFileFailure(NSError(domain: "test", code: 513,
                                         userInfo: [NSLocalizedDescriptionKey: "private error detail"]))
        await files.flush()
        XCTAssertEqual(received.withLock { $0.map(\.message) }, ["Could not write log file (code 513): <private>"])
        XCTAssertEqual(received.withLock { $0.map(\.category) }, ["app"])
        XCTAssertEqual(received.withLock { $0.map(\.level) }, [.error])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    }

    private func makeOutput(_ received: OSAllocatedUnfairLock<[LogLine]>) -> LogOutput {
        LogOutput(clock: { logDate("2026-10-30T11:00:00Z") }, processID: 123, timeZone: { .gmt },
                  unified: { line in received.withLock { $0.append(line) } })
    }

    private func makeFiles() -> LogFiles {
        LogFiles(folder: folder, clock: { logDate("2026-10-30T11:00:00Z") },
                 onFailure: { XCTFail("Unexpected file error: \($0)") })
    }

    private func text() throws -> String { try String(contentsOf: file, encoding: .utf8) }
}
