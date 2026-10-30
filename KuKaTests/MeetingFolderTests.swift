import XCTest
@testable import KuKa

final class MeetingFolderTests: XCTestCase {
    func testUntrustedTitleIsOnePlainHeadingInBothDocuments() {
        let title = "Review\n# Forged **Me:** [link](../secret) <tag>"
        let expected = "# Review \\# Forged \\*\\*Me:\\*\\* \\[link\\]\\(../secret\\) \\<tag\\>\n"
        XCTAssertTrue(Transcript.markdown([], title: title, duration: 0, by: "Fake", after: [], rooms: .notDiarized).hasPrefix(expected))
        XCTAssertEqual(SummaryDocument.markdown(title: title, body: "Notes"), expected + "\nNotes\n")
        XCTAssertTrue(SummaryDocument.noSpeech(title: title).hasPrefix(expected))
    }

    func testSavedTitleHasABoundedLengthAndBlankTitleKeepsDate() throws {
        let meeting = try MeetingFolder.create(in: try makeTemporaryDirectory(), startingAt: localDate(2026, 10, 23, 14, 2))
        try meeting.saveDisplayTitle(" \n\t ")
        XCTAssertEqual(meeting.title, "Meeting on 2026-10-23 at 14:02")
        try meeting.saveDisplayTitle(String(repeating: "a", count: 301))
        XCTAssertEqual(meeting.title, String(repeating: "a", count: 300))
    }

    func testTitleTruncationDoesNotLeaveAnInvalidTrailingSpace() throws {
        let meeting = try MeetingFolder.create(in: try makeTemporaryDirectory(), startingAt: localDate(2026, 10, 23, 14, 2))
        try meeting.saveDisplayTitle(String(repeating: "a", count: 299) + " b")
        XCTAssertEqual(meeting.title, String(repeating: "a", count: 299))
    }

    func testDisplayTitleSurvivesReconstructionWithoutChangingIdentityOrStage() throws {
        let root = try makeTemporaryDirectory()
        let meeting = try MeetingFolder.create(in: root, startingAt: localDate(2026, 10, 23, 14, 2))
        try meeting.saveDisplayTitle("  ../Planning\n# Next **topic**  ")
        let restored = MeetingFolder(url: meeting.url)
        XCTAssertEqual(restored.title, "../Planning # Next **topic**")
        XCTAssertEqual(restored, meeting)
        XCTAssertEqual(restored.name, "2026-10-23_14-02")
        XCTAssertNil(restored.stage())
        XCTAssertTrue(MeetingFolder.all(in: root).isEmpty)
        try restored.write("speech", to: .transcript)
        XCTAssertEqual(MeetingFolder.all(in: root).first?.0.title, "../Planning # Next **topic**")
    }

    func testInvalidAndOversizedTitleMetadataFallsBackToDatedTitle() throws {
        let meeting = try MeetingFolder.create(in: try makeTemporaryDirectory(), startingAt: localDate(2026, 10, 23, 14, 2))
        let metadata = meeting.url.appendingPathComponent("meeting.json")
        let invalid = ["{}", #"{"version":2,"title":"Wrong"}"#, #"{"version":1,"title":" "}"#,
                       #"{"version":1,"title":"First\nSecond"}"#,
                       "{\"version\":1,\"title\":\"" + String(repeating: "x", count: 301) + "\"}",
                       "{\"version\":1,\"title\":\"Wrong\",\"padding\":\"" + String(repeating: "x", count: 16_384) + "\"}"]
        for text in invalid {
            try Data(text.utf8).write(to: metadata)
            XCTAssertEqual(meeting.title, "Meeting on 2026-10-23 at 14:02")
        }
    }

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

        XCTAssertEqual(meeting.name, "2026-10-23_14-02")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("2026-10-23_14-02/audio").path,
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

    func testTheRoomLabelsMarkerDoesNotChangeTheStage() throws {
        let meeting = try MeetingFolder.create(in: try makeTemporaryDirectory(), startingAt: localDate(2026, 10, 23, 14, 2))

        try meeting.markRoomLabelsStarted()
        XCTAssertTrue(meeting.roomLabelsStarted)
        XCTAssertNil(meeting.stage(), "the marker does not make a folder a meeting")

        FileManager.default.createFile(atPath: meeting.audioURL(.microphone).path, contents: Data())
        XCTAssertEqual(meeting.stage(), .pending(.transcribe))

        try meeting.write("# Transcript", to: .transcript)
        XCTAssertEqual(meeting.stage(), .pending(.summarize))

        try meeting.clearRoomLabelsStarted()
        try meeting.clearRoomLabelsStarted()
        XCTAssertFalse(meeting.roomLabelsStarted)
        XCTAssertEqual(meeting.stage(), .pending(.summarize))
    }

    func testTheHeardCopyAndTheReviewFilesNeverChangeTheStage() throws {
        let root = try makeTemporaryDirectory()
        let stages: [(MeetingStage?, [MeetingDocument], Bool)] = [
            (nil, [], false),
            (.pending(.transcribe), [], true),
            (.failed(.transcribe), [.failure], true),
            (.pending(.summarize), [.transcript], false),
            (.failed(.summarize), [.transcript, .failure], false),
            (.done, [.transcript, .summary], false),
        ]
        let extras: [[MeetingDocument]] = [[.heardTranscript], [.questions], [.skipped], [.heardTranscript, .questions, .skipped]]
        var minute = 0
        for (stage, documents, hasAudio) in stages {
            for extra in extras {
                minute += 1
                let meeting = try MeetingFolder.create(in: root, startingAt: localDate(2026, 10, 23, 14, minute))
                if hasAudio { FileManager.default.createFile(atPath: meeting.audioURL(.microphone).path, contents: Data()) }
                for document in documents + extra { try meeting.write("text", to: document) }

                XCTAssertEqual(meeting.stage(), stage, "\(documents.map(\.rawValue)) with \(extra.map(\.rawValue))")
            }
        }
    }

    func testWithoutAHeardCopyTheTranscriptWithoutItsNoteBecomesTheCopy() throws {
        let meeting = try MeetingFolder.create(in: try makeTemporaryDirectory(), startingAt: localDate(2026, 10, 23, 14, 2))
        try meeting.write("**[00:00:01] Them:** Ask Konvio.\n\n---\n\nKnown words applied: Convio → Konvio (1).\n", to: .transcript)

        let first = try meeting.heardTranscript()
        try meeting.write("**[00:00:01] Them:** Changed later.\n", to: .transcript)
        let second = try meeting.heardTranscript()

        XCTAssertEqual(first, "**[00:00:01] Them:** Ask Konvio.\n")
        XCTAssertEqual(second, first)
        XCTAssertEqual(try meeting.read(.heardTranscript), first)
    }

    func testWithoutATranscriptThereIsNoHeardTranscript() throws {
        let meeting = try MeetingFolder.create(in: try makeTemporaryDirectory(), startingAt: localDate(2026, 10, 23, 14, 2))

        XCTAssertThrowsError(try meeting.heardTranscript())
        XCTAssertFalse(FileManager.default.fileExists(atPath: meeting.url(for: .heardTranscript).path))
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

    func testAllFindsTheMeetingsOfAMeetingsFolderThatIsASymlink() throws {
        let base = try makeTemporaryDirectory()
        let target = base.appendingPathComponent("Cloud Meetings", isDirectory: true)
        let root = base.appendingPathComponent("Meetings", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: target)
        let meeting = try MeetingFolder.create(in: root, startingAt: localDate(2026, 10, 23, 14, 2))
        try meeting.write("# Summary", to: .summary)

        let listed = MeetingFolder.all(in: root)

        XCTAssertEqual(listed.map(\.0), [meeting])
        XCTAssertEqual(listed.map(\.1), [.done])
    }

    /// The temporary folder is under /var, which is a symlink to /private/var, and the meetings
    /// folder here is inside one more symlinked folder.
    func testEveryWayToNameOneMeetingGivesOneEqualValue() throws {
        let base = try makeTemporaryDirectory()
        XCTAssertTrue(base.path.hasPrefix("/var/"), base.path)
        let target = base.appendingPathComponent("Cloud Drive", isDirectory: true)
        let link = base.appendingPathComponent("Drive", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let root = link.appendingPathComponent("Meetings", isDirectory: true)
        let name = "2026-10-23_14-02"
        let beforeTheMeetingsFolder = MeetingFolder(url: root.appendingPathComponent(name, isDirectory: true))
        let created = try MeetingFolder.create(in: root, startingAt: localDate(2026, 10, 23, 14, 2))
        try created.write("# Transcript", to: .transcript)
        let listed = try XCTUnwrap(MeetingFolder.all(in: root).first?.0)
        let throughTheTarget = MeetingFolder(url: target.appendingPathComponent("Meetings").appendingPathComponent(name))
        let underPrivate = MeetingFolder(url: URL(fileURLWithPath: "/private" + root.path).appendingPathComponent(name))
        let clicked = NotificationClick(userInfo: NotificationClick.checkWords(created).userInfo)
        let other = try MeetingFolder.create(in: root, startingAt: localDate(2026, 10, 23, 15, 0))

        XCTAssertEqual(created, listed)
        XCTAssertEqual(beforeTheMeetingsFolder, listed)
        XCTAssertEqual(throughTheTarget, listed)
        XCTAssertEqual(underPrivate, listed)
        XCTAssertEqual(clicked, .checkWords(listed))
        XCTAssertEqual(Set([created, listed, beforeTheMeetingsFolder, throughTheTarget, underPrivate]).count, 1)
        XCTAssertNotEqual(other, created)
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
