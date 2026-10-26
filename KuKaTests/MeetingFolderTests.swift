import XCTest
@testable import KuKa

final class MeetingFolderTests: XCTestCase {
    func testStageFollowsTheMostAdvancedFile() {
        let cases: [(MeetingFolderContents, MeetingStage?)] = [
            (MeetingFolderContents(hasSummary: true), .done),
            (MeetingFolderContents(hasTranscript: true, hasSummary: true, hasFailure: true), .done),
            (MeetingFolderContents(hasTranscript: true), .pending(.summarize)),
            (MeetingFolderContents(audio: [.system], hasTranscript: true), .pending(.summarize)),
            (MeetingFolderContents(hasTranscript: true, hasFailure: true), .failed(.summarize)),
            (MeetingFolderContents(audio: [.system]), .pending(.transcribe)),
            (MeetingFolderContents(audio: [.microphone, .system], hasFailure: true), .failed(.transcribe)),
            (MeetingFolderContents(), nil),
            (MeetingFolderContents(hasFailure: true), nil),
        ]
        for (contents, expected) in cases {
            XCTAssertEqual(MeetingStage(contents), expected, "\(contents)")
        }
    }

    func testFolderNameIsTheLocalStartMinute() {
        XCTAssertEqual(MeetingFolder.folderName(startingAt: localDate(2026, 10, 23, 14, 2, 59)), "2026-10-23_14-02")
    }

    func testTitleReadsTheStartBackFromTheName() {
        let root = URL(fileURLWithPath: "/tmp/meetings", isDirectory: true)
        func title(_ name: String) -> String {
            MeetingFolder(url: root.appendingPathComponent(name, isDirectory: true)).title
        }
        XCTAssertEqual(title("2026-10-23_14-02"), "Meeting on 2026-10-23 at 14:02")
        XCTAssertEqual(title("2026-10-23_14-02-2"), "Meeting on 2026-10-23 at 14:02 (2)")
        XCTAssertEqual(title("Design review"), "Design review")
    }

    func testCreateMakesTheDatedFolderAndItsAudioFolder() throws {
        let root = try makeTemporaryDirectory().appendingPathComponent("Meetings", isDirectory: true)

        let meeting = try MeetingFolder.create(in: root, startingAt: localDate(2026, 10, 23, 14, 2))

        XCTAssertEqual(meeting.url.path, root.appendingPathComponent("2026-10-23_14-02").path)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: meeting.url.appendingPathComponent("audio").path,
                                                     isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testCreateAddsANumberWhenTheMinuteIsTaken() throws {
        let root = try makeTemporaryDirectory()
        let start = localDate(2026, 10, 23, 14, 2)

        let names = try (1...3).map { _ in try MeetingFolder.create(in: root, startingAt: start).name }

        XCTAssertEqual(names, ["2026-10-23_14-02", "2026-10-23_14-02-2", "2026-10-23_14-02-3"])
    }

    func testStageIsReadFromTheFilesOnDisk() throws {
        let meeting = try MeetingFolder.create(in: try makeTemporaryDirectory(), startingAt: localDate(2026, 10, 23, 14, 2))
        XCTAssertNil(meeting.stage(), "an empty audio folder is not a meeting yet")

        FileManager.default.createFile(atPath: meeting.audioURL(.system).path, contents: Data())
        XCTAssertEqual(meeting.stage(), .pending(.transcribe))

        try meeting.write("Speech model missing", to: .failure)
        XCTAssertEqual(meeting.stage(), .failed(.transcribe))

        try meeting.write("# Transcript", to: .transcript)
        XCTAssertEqual(meeting.stage(), .failed(.summarize))

        try meeting.clearFailure()
        XCTAssertEqual(meeting.stage(), .pending(.summarize))

        try meeting.write("# Summary", to: .summary)
        XCTAssertEqual(meeting.stage(), .done)
    }

    func testOnlyOneWriterCanLockAMeetingAtATime() throws {
        let meeting = try MeetingFolder.create(in: try makeTemporaryDirectory(), startingAt: localDate(2026, 10, 23, 14, 2))

        let first = try meeting.lock()
        XCTAssertThrowsError(try meeting.lock()) { XCTAssertEqual($0 as? MeetingLockError, .held(meeting)) }
        first.release()

        XCTAssertNoThrow(try meeting.lock())
        XCTAssertNil(meeting.stage(), "the lock file does not make a folder a meeting")
    }

    func testClearFailureCanRunTwice() throws {
        let meeting = try MeetingFolder.create(in: try makeTemporaryDirectory(), startingAt: localDate(2026, 10, 23, 14, 2))
        try meeting.write("# Transcript", to: .transcript)
        try meeting.write("CLI failed", to: .failure)

        try meeting.clearFailure()
        try meeting.clearFailure()

        XCTAssertEqual(meeting.stage(), .pending(.summarize))
    }

    func testAllListsMeetingsOldestFirstAndSkipsEverythingElse() throws {
        let root = try makeTemporaryDirectory()
        let later = try MeetingFolder.create(in: root, startingAt: localDate(2026, 10, 24, 9, 0))
        try later.write("# Transcript", to: .transcript)
        let earlier = try MeetingFolder.create(in: root, startingAt: localDate(2026, 10, 23, 14, 2))
        try earlier.write("# Summary", to: .summary)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Notes"), withIntermediateDirectories: false)
        FileManager.default.createFile(atPath: root.appendingPathComponent("readme.txt").path, contents: Data("hi".utf8))

        let meetings = MeetingFolder.all(in: root)

        XCTAssertEqual(meetings.map { $0.0.name }, ["2026-10-23_14-02", "2026-10-24_09-00"])
        XCTAssertEqual(meetings.map { $0.1 }, [.done, .pending(.summarize)])
        XCTAssertEqual(MeetingFolder.all(in: root.appendingPathComponent("missing")).map { $0.0.name }, [])
    }

    func testDiscardAudioTrashesTheAudioFolderOnlyWhileItExists() throws {
        let meeting = try MeetingFolder.create(in: try makeTemporaryDirectory(), startingAt: localDate(2026, 10, 23, 14, 2))
        FileManager.default.createFile(atPath: meeting.audioURL(.microphone).path, contents: Data())
        var trashed: [String] = []
        let trash: (URL) throws -> Void = { url in
            trashed.append(url.lastPathComponent)
            try FileManager.default.removeItem(at: url)
        }

        try meeting.discardAudio(trash: trash)
        try meeting.discardAudio(trash: trash)

        XCTAssertEqual(trashed, ["audio"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: meeting.url.appendingPathComponent("audio").path))
    }
}
