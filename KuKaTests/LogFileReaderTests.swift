import XCTest
import os
@testable import KuKa

final class LogFileReaderTests: XCTestCase {
    private var root: URL!
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .gmt
        return value
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testReadsOnlyOwnedRegularFilesInDateOrderAndPreservesUnknownRows() async throws {
        try put("Ku-Ka-2026-10-30.log", "2026-10-30 11:00:00.000 +0000 [42] error app: failed\nraw ä\n")
        try put("Ku-Ka-2026-10-29.log", "older raw")
        try put("notes.txt", "unrelated")
        try put("Ku-Ka-2026-02-30.log", "invalid date")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Ku-Ka-2026-10-28.log"),
                                                  withDestinationURL: root.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Ku-Ka-2026-10-27.log"), withIntermediateDirectories: false)
        let reader = LogFileReader(folder: root, timeZone: .gmt)
        let rows = try await reader.rows(in: nil)
        XCTAssertEqual(rows.map(\.text), ["older raw", "2026-10-30 11:00:00.000 +0000 [42] error app: failed", "raw ä"])
        XCTAssertEqual(rows.map(\.day), [logDate("2026-10-29T00:00:00Z"), logDate("2026-10-30T00:00:00Z"), logDate("2026-10-30T00:00:00Z")])
        XCTAssertEqual(rows[1].line?.level, .error)
        XCTAssertNil(rows[0].line)
    }

    func testSkipsUnchangedFilesAndReloadsChangedAndReplacedFiles() async throws {
        let url = try put("Ku-Ka-2026-10-30.log", "first\n")
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let reader = LogFileReader(folder: root, timeZone: .gmt, load: { url in
            calls.withLock { $0 += 1 }
            return try Data(contentsOf: url)
        })
        let first = try await reader.rows(in: nil)
        let unchanged = try await reader.rows(in: nil)
        XCTAssertEqual(first.map(\.text), ["first"])
        XCTAssertEqual(unchanged.map(\.text), ["first"])
        XCTAssertEqual(calls.withLock { $0 }, 1)
        try Data("longer second\n".utf8).write(to: url)
        let stamp = logDate("2026-10-30T12:00:00Z")
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)
        let changed = try await reader.rows(in: nil)
        XCTAssertEqual(changed.map(\.text), ["longer second"])
        XCTAssertEqual(calls.withLock { $0 }, 2)
        try Data("same-length!!\n".utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)
        let replaced = try await reader.rows(in: nil)
        XCTAssertEqual(replaced.map(\.text), ["same-length!!"])
        XCTAssertEqual(calls.withLock { $0 }, 3)
        try FileManager.default.removeItem(at: url)
        let deleted = try await reader.rows(in: nil)
        XCTAssertTrue(deleted.isEmpty)
    }

    func testRowIdentitySurvivesAppendButNotFileReplacement() async throws {
        let url = try put("Ku-Ka-2026-10-30.log", "repeat\nrepeat\n")
        let reader = LogFileReader(folder: root, timeZone: .gmt)
        let first = try await reader.rows(in: nil)
        XCTAssertNotEqual(first[0].id, first[1].id)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("next\n".utf8))
        try handle.close()
        let appended = try await reader.rows(in: nil)
        XCTAssertEqual(Array(appended.prefix(2)).map(\.id), first.map(\.id))
        try Data("repeat\nrepeat\nnext\n".utf8).write(to: url, options: .atomic)
        let replaced = try await reader.rows(in: nil)
        XCTAssertNotEqual(replaced[0].id, first[0].id)
    }

    func testRangeDoesNotLoadOtherDaysAndAnEmptyFileHasNoRows() async throws {
        try put("Ku-Ka-2026-10-29.log", "old\n")
        try put("Ku-Ka-2026-10-30.log", "")
        try put("Ku-Ka-2026-10-31.log", "future\n")
        let loaded = OSAllocatedUnfairLock(initialState: [String]())
        let reader = LogFileReader(folder: root, timeZone: .gmt, load: { url in
            loaded.withLock { $0.append(url.lastPathComponent) }
            return try Data(contentsOf: url)
        })
        let interval = DateInterval(start: logDate("2026-10-30T00:00:00Z"), end: logDate("2026-10-31T00:00:00Z"))
        let rows = try await reader.rows(in: interval)
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(loaded.withLock { $0 }, ["Ku-Ka-2026-10-30.log"])
    }

    func testMissingFolderIsEmptyButReadFailuresAreReported() async throws {
        let reader = LogFileReader(folder: root.appendingPathComponent("missing"))
        let missing = try await reader.rows(in: nil)
        XCTAssertTrue(missing.isEmpty)
        try put("Ku-Ka-2026-10-30.log", "line\n")
        let failed = LogFileReader(folder: root, load: { _ in throw CocoaError(.fileReadNoPermission) })
        do {
            _ = try await failed.rows(in: nil)
            XCTFail("A failed read must reach the window")
        } catch { XCTAssertEqual((error as NSError).code, CocoaError.fileReadNoPermission.rawValue) }
    }

    func testReaderRangesCoverWholeCalendarDaysAndEverythingHasNoBounds() {
        let now = logDate("2026-10-30T11:00:00Z")
        let launch = logDate("2026-10-28T12:00:00Z")
        XCTAssertEqual(LogRange.thisLaunch.interval(now: now, launchDate: launch, calendar: calendar),
                       DateInterval(start: logDate("2026-10-28T00:00:00Z"), end: logDate("2026-10-31T00:00:00Z")))
        XCTAssertEqual(LogRange.today.interval(now: now, launchDate: launch, calendar: calendar)?.start,
                       logDate("2026-10-30T00:00:00Z"))
        XCTAssertEqual(LogRange.lastSevenDays.interval(now: now, launchDate: launch, calendar: calendar)?.start,
                       logDate("2026-10-24T00:00:00Z"))
        XCTAssertNil(LogRange.everything.interval(now: now, launchDate: launch, calendar: calendar))
    }

    @discardableResult
    private func put(_ name: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }
}
