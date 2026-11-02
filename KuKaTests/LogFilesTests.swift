import XCTest
import Darwin
import os
@testable import KuKa

final class LogFilesTests: XCTestCase {
    private var root: URL!
    private var folder: URL { root.appendingPathComponent("logs") }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        return calendar
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testAppendsWholeLinesToLocalDateWithOwnerOnlyPermissions() async throws {
        let files = makeFiles()
        files.append(line("first"))
        files.append(line("second"))
        await files.flush()
        XCTAssertEqual(try contents("Ku-Ka-2026-10-30.log"),
                       "2026-10-30 13:00:00.000 +0200 [42] info app: first\n" +
                       "2026-10-30 13:00:00.000 +0200 [42] info app: second\n")
        XCTAssertEqual(try permissions(folder), 0o700)
        XCTAssertEqual(try permissions(folder.appendingPathComponent("Ku-Ka-2026-10-30.log")), 0o600)
    }

    func testUsesTheLinesLocalDateAcrossMidnightAndRepeatsCleanup() async throws {
        let clock = OSAllocatedUnfairLock(initialState: logDate("2026-10-30T21:59:59Z"))
        let files = LogFiles(folder: folder, clock: { clock.withLock { $0 } }, calendar: calendar,
                             onFailure: { XCTFail("Unexpected file error: \($0)") })
        files.append(line("before", date: clock.withLock { $0 }))
        await files.flush()
        try seed("Ku-Ka-2026-10-16.log", text: "fourteen days old")
        clock.withLock { $0 = logDate("2026-10-30T22:00:00Z") }
        files.append(line("after", date: clock.withLock { $0 }))
        await files.flush()
        XCTAssertEqual(try names(), ["Ku-Ka-2026-10-30.log", "Ku-Ka-2026-10-31.log"])
        XCTAssertTrue(try contents("Ku-Ka-2026-10-30.log").contains("before"))
        XCTAssertTrue(try contents("Ku-Ka-2026-10-31.log").contains("after"))
    }

    func testLaunchRetentionUsesCalendarDaysAcrossDaylightSavingAndKeepsBoundary() async throws {
        try seed("Ku-Ka-2026-10-15.log", text: "old")
        try seed("Ku-Ka-2026-10-16.log", text: "boundary")
        try seed("Ku-Ka-2026-10-30.log", text: "today")
        let files = makeFiles()
        await files.flush()
        XCTAssertEqual(try names(), ["Ku-Ka-2026-10-16.log", "Ku-Ka-2026-10-30.log"])
    }

    func testSizeLimitDeletesOldestFilesFirstAndKeepsExactBoundary() async throws {
        try seedBytes("Ku-Ka-2026-10-28.log", count: 1)
        try seedBytes("Ku-Ka-2026-10-29.log", count: 10_000_000)
        try seedBytes("Ku-Ka-2026-10-30.log", count: 10_000_000)
        let files = makeFiles()
        await files.flush()
        XCTAssertEqual(try names(), ["Ku-Ka-2026-10-29.log", "Ku-Ka-2026-10-30.log"])
    }

    func testSizeLimitNeverDeletesTodayEvenWhenTodayAloneExceedsLimit() async throws {
        try seedBytes("Ku-Ka-2026-10-29.log", count: 1)
        try seedBytes("Ku-Ka-2026-10-30.log", count: 20_000_001)
        let files = makeFiles()
        await files.flush()
        XCTAssertEqual(try names(), ["Ku-Ka-2026-10-30.log"])
    }

    func testDeleteAllRemovesOnlyOwnedRegularFilesAndNextAppendRecreatesToday() async throws {
        try seed("Ku-Ka-2026-10-29.log", text: "old")
        try seed("notes.txt", text: "keep")
        try seed("Ku-Ka-2026-02-30.log", text: "invalid date")
        try seed("Ku-Ka-2026-1-01.log", text: "invalid name")
        let directory = folder.appendingPathComponent("Ku-Ka-2026-10-01.log")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let outside = root.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: outside)
        let link = folder.appendingPathComponent("Ku-Ka-2026-10-02.log")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let files = makeFiles()
        files.append(line("delete me"))
        try await files.deleteAll()
        XCTAssertEqual(try names(), ["Ku-Ka-2026-02-30.log", "Ku-Ka-2026-1-01.log",
                                     "Ku-Ka-2026-10-01.log", "Ku-Ka-2026-10-02.log", "notes.txt"])
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "outside")
        files.append(line("new"))
        await files.flush()
        XCTAssertEqual(try contents("Ku-Ka-2026-10-30.log"),
                       "2026-10-30 13:00:00.000 +0200 [42] info app: new\n")
    }

    func testAnotherWriterCanDeleteAFileWithoutLeavingTheFirstWriterOnAnOldHandle() async throws {
        let first = makeFiles()
        let second = makeFiles()
        first.append(line("old"))
        await first.flush()
        try await second.deleteAll()
        first.append(line("new"))
        await first.flush()
        XCTAssertTrue(try contents("Ku-Ka-2026-10-30.log").hasSuffix("app: new\n"))
        XCTAssertFalse(try contents("Ku-Ka-2026-10-30.log").contains("old"))
    }

    func testConcurrentWritersKeepEveryUTF8LineWhole() async throws {
        let first = makeFiles()
        let second = makeFiles()
        let lines = (0..<200).map { line("message \($0) ä👩🏽‍💻") }
        DispatchQueue.concurrentPerform(iterations: 200) { index in
            (index.isMultiple(of: 2) ? first : second).append(lines[index])
        }
        await first.flush()
        await second.flush()
        let rows = try contents("Ku-Ka-2026-10-30.log").split(separator: "\n")
        XCTAssertEqual(rows.count, 200)
        let messages = rows.compactMap { LogLine(parsing: String($0))?.message }
        XCTAssertEqual(Set(messages), Set((0..<200).map { "message \($0) ä👩🏽‍💻" }))
    }

    func testWriteFailureIsReportedAndDoesNotFollowASymlink() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("outside.txt")
        try Data("unchanged".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("Ku-Ka-2026-10-30.log"),
                                                  withDestinationURL: outside)
        let failure = expectation(description: "write failure reported")
        let files = LogFiles(folder: folder, clock: { logDate("2026-10-30T11:00:00Z") },
                             calendar: calendar, onFailure: { _ in failure.fulfill() })
        files.append(line("must not write"))
        await files.flush()
        await fulfillment(of: [failure], timeout: 2)
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "unchanged")
    }

    func testDeleteAllRejectsASymlinkedRootFolder() async throws {
        try seed("Ku-Ka-2026-10-30.log", text: "keep")
        let link = root.appendingPathComponent("linked-logs")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        let failure = expectation(description: "invalid folder reported")
        let files = LogFiles(folder: link, calendar: calendar, onFailure: { _ in failure.fulfill() })
        await files.flush()
        await fulfillment(of: [failure], timeout: 2)
        do {
            try await files.deleteAll()
            XCTFail("Deletion through a symlink must fail")
        } catch {}
        XCTAssertEqual(try contents("Ku-Ka-2026-10-30.log"), "keep")
    }

    func testBoundedShutdownDrainFinishesAcceptedWrites() throws {
        let files = makeFiles()
        files.append(line("before quit"))
        XCTAssertTrue(files.flush(timeout: 2))
        XCTAssertEqual(try contents("Ku-Ka-2026-10-30.log"),
                       "2026-10-30 13:00:00.000 +0200 [42] info app: before quit\n")
    }

    func testShutdownDrainCanTimeOutWithoutWaitingForeverForTheWriter() throws {
        try seed("target", text: "keep")
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("Ku-Ka-2026-10-30.log"),
                                                  withDestinationURL: folder.appendingPathComponent("target"))
        let entered = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        let files = LogFiles(folder: folder, clock: { logDate("2026-10-30T11:00:00Z") }, onFailure: { _ in
            entered.signal()
            resume.wait()
        })
        files.append(line("fails"))
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        let finished = files.flush(timeout: 0.02)
        resume.signal()
        XCTAssertFalse(finished)
        XCTAssertTrue(files.flush(timeout: 2))
    }

    private func makeFiles() -> LogFiles {
        LogFiles(folder: folder, clock: { logDate("2026-10-30T11:00:00Z") },
                 calendar: calendar, onFailure: { XCTFail("Unexpected file error: \($0)") })
    }

    private func line(_ text: String, date: Date = logDate("2026-10-30T11:00:00Z")) -> LogLine {
        LogLine(date: date, processID: 42, level: .info, category: "app", message: text,
                timeZone: calendar.timeZone)
    }

    private func seed(_ name: String, text: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: folder.appendingPathComponent(name))
    }

    private func seedBytes(_ name: String, count: Int) throws {
        try seed(name, text: "")
        let handle = try FileHandle(forWritingTo: folder.appendingPathComponent(name))
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(count))
    }

    private func contents(_ name: String) throws -> String {
        try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
    }

    private func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    private func permissions(_ url: URL) throws -> Int {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber).intValue
    }
}
