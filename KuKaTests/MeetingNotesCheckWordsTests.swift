import XCTest
@testable import KuKa

@MainActor
final class MeetingNotesCheckWordsTests: MeetingNotesTestCase {
    private let askTheVendors = "Ask Convio, Brightlane and Yuri on Friday"

    private func hearTheVendors(suspects heard: [String]) throws {
        try XCTUnwrap(transcriber as? FakeTranscriber).byFileName["them.caf"] = .success(TrackTranscript(
            segments: [TranscriptSegment(start: 1, end: 3, text: askTheVendors)], duration: 60))
        let items = heard.map { #"{"heard": "\#($0)", "kind": "company", "quote": "\#(askTheVendors)"}"# }
        runner.results["agy"] = .success(CommandResult(
            termination: .exited(0),
            stdout: "## Summary\nAsk the vendors.\n\n```ku-ka-review\n[\(items.joined(separator: ", "))]\n```\n",
            stderr: ""))
    }

    @discardableResult
    private func reviewedMeeting(at date: Date, asking heard: [String], skipped: Int = 0) throws -> MeetingFolder {
        let meeting = try MeetingFolder.create(in: root, startingAt: date)
        try meeting.write("**[00:00:01] Them:** \(askTheVendors)\n", to: .transcript)
        try meeting.write("# \(meeting.title)\n\nAsk the vendors.\n", to: .summary)
        let questions = heard.map { #"{"heard": "\#($0)", "kind": "company", "quote": "\#(askTheVendors)"}"# }
        try meeting.write(#"{"questions": [\#(questions.joined(separator: ", "))]}"#, to: .questions)
        let skips = heard.prefix(skipped).map { #""\#($0)""# }
        try meeting.write(#"{"skipped": [\#(skips.joined(separator: ", "))]}"#, to: .skipped)
        return meeting
    }

    func testNotesWithQuestionsSayHowManyWordsToCheckAndAClickOpensTheReview() async throws {
        try hearTheVendors(suspects: ["Convio", "Brightlane", "Yuri"])
        try leftoverMeeting(at: localDate(2026, 10, 22, 9, 0))

        sut.resumeUnfinished()
        await sut.waitUntilIdle()

        XCTAssertEqual(notifications, ["Meeting Notes Ready: Meeting on 2026-10-22 at 09:00. 3 words to check. Click to check them."])
        let meeting = try XCTUnwrap(MeetingFolder.all(in: root).first?.0)
        XCTAssertEqual(notifier.posted.last?.click, .checkWords(meeting))
        XCTAssertEqual(item(titled: "Check Words (3)…")?.isHidden, false, "read again when the queue ends")
    }

    func testNotesWithOneQuestionSayOneWord() async throws {
        try hearTheVendors(suspects: ["Convio"])
        try leftoverMeeting(at: localDate(2026, 10, 22, 9, 0))

        sut.resumeUnfinished()
        await sut.waitUntilIdle()

        XCTAssertEqual(notifications, ["Meeting Notes Ready: Meeting on 2026-10-22 at 09:00. 1 word to check. Click to check them."])
    }

    func testCheckWordsCountsTheOpenQuestionsOfEveryDoneMeetingWhenTheMenuOpens() throws {
        sut.menuWillOpen()
        XCTAssertFalse(visibleTitles.contains { $0.hasPrefix("Check Words") }, "hidden without questions")

        try reviewedMeeting(at: localDate(2026, 10, 22, 9, 0), asking: ["Convio", "Yuri"], skipped: 1)
        try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: ["Brightlane", "Convio"])
        try reviewedMeeting(at: localDate(2026, 10, 24, 9, 0), asking: ["Quorix"], skipped: 1)
        sut.menuWillOpen()

        XCTAssertEqual(visibleTitles, ["Meeting Notes", "Start Recording Meeting", "Check Words (3)…", "Open Meetings Folder", ""])
    }

    func testCheckWordsLeavesOutTheQuestionsWhoseWordTheListLearnedSince() throws {
        try reviewedMeeting(at: localDate(2026, 10, 22, 9, 0), asking: ["Convio", "Yuri"])
        try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: ["Convio"])
        knownWords = KnownWordsList(markdown: "- Convio → **Konvio** ✓\n")

        sut.menuWillOpen()

        XCTAssertEqual(visibleTitles, ["Meeting Notes", "Start Recording Meeting", "Check Words (1)…", "Open Meetings Folder", ""])
    }

    func testTheMenuListsTheProgressThenCheckWordsThenRetry() async throws {
        transcriber = SuspendedTranscriber()
        sut = makeController()
        try leftoverMeeting(at: localDate(2026, 10, 22, 9, 0))
        try leftoverMeeting(at: localDate(2026, 10, 22, 10, 0))
        try leftoverMeeting(at: localDate(2026, 10, 22, 11, 0), failure: "Speech model missing")
        try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: ["Convio"])

        sut.resumeUnfinished()
        sut.menuWillOpen()
        await waitUntil { visibleTitles.count > 6 }

        XCTAssertEqual(visibleTitles, ["Meeting Notes", "Start Recording Meeting",
                                       "Transcribing: Meeting on 2026-10-22 at 09:00", "1 more meeting waiting",
                                       "Check Words (1)…", "Retry Failed Meeting", "Open Meetings Folder", ""])
    }

    func testAMeetingsFolderThatIsASymlinkKeepsRecoveryRetryAndCheckWords() async throws {
        let base = try makeTemporaryDirectory()
        let target = base.appendingPathComponent("Cloud Meetings", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        root = base.appendingPathComponent("Meetings", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: target)
        try leftoverMeeting(at: localDate(2026, 10, 22, 9, 0))
        try leftoverMeeting(at: localDate(2026, 10, 22, 10, 0), failure: "Speech model missing")
        try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: ["Convio"])

        sut.menuWillOpen()
        XCTAssertEqual(visibleTitles, ["Meeting Notes", "Start Recording Meeting", "Check Words (1)…", "Retry Failed Meeting",
                                       "Open Meetings Folder", ""])
        sut.resumeUnfinished()
        await sut.waitUntilIdle()

        XCTAssertEqual(notifications, ["Meeting Notes Ready: Meeting on 2026-10-22 at 09:00. Click to open the summary."])
    }

    func testChoosingCheckWordsAsksForTheOldestUnfinishedReview() throws {
        try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: ["Convio"])
        var asked: [MeetingFolder?] = []
        sut.onCheckWords = { asked.append($0) }
        sut.menuWillOpen()

        let checkWords = try XCTUnwrap(item(titled: "Check Words (1)…"))
        _ = (checkWords.target as? NSObject)?.perform(checkWords.action, with: checkWords)

        XCTAssertEqual(asked, [nil])
    }

    func testUpdateNotesWaitsForTheMeetingThatIsProcessedAndThenSaysWhatItDoes() async throws {
        let gate = GatedCommandRunner()
        self.gate = gate
        sut = makeController()
        try leftoverMeeting(at: localDate(2026, 10, 22, 9, 0), transcript: true)
        let reviewed = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: ["Convio"])
        sut.resumeUnfinished()
        await waitUntil { gate.waiting == 1 }

        sut.updateNotes(reviewed)

        XCTAssertEqual(visibleTitles, ["Meeting Notes", "Start Recording Meeting",
                                       "Summarizing: Meeting on 2026-10-22 at 09:00", "1 more meeting waiting",
                                       "Open Meetings Folder", ""])
        gate.letOneThrough()
        await waitUntil { gate.runs == 2 && gate.waiting == 1 }
        XCTAssertEqual(visibleTitles, ["Meeting Notes", "Start Recording Meeting",
                                       "Updating notes: Meeting on 2026-10-23 at 09:00", "Open Meetings Folder", ""])
        gate.letOneThrough()
        await sut.waitUntilIdle()
        XCTAssertEqual(notifications, ["Meeting Notes Ready: Meeting on 2026-10-22 at 09:00. Click to open the summary.",
                                       "Notes Updated: Meeting on 2026-10-23 at 09:00. Click to open the summary."])
        XCTAssertEqual(notifier.posted.last?.click, .open(reviewed.url(for: .summary)))
        XCTAssertEqual(try reviewed.read(.summary), "# Meeting on 2026-10-23 at 09:00\n\n## Summary\nShip Friday.\n")
    }

    func testTheSameUpdateNotesAskedAgainWhileItWaitsOrRunsRunsOnceAlsoThroughASymlink() async throws {
        let base = try makeTemporaryDirectory()
        let target = base.appendingPathComponent("Cloud Drive", isDirectory: true)
        let link = base.appendingPathComponent("Drive", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        root = link.appendingPathComponent("Meetings", isDirectory: true)
        let gate = GatedCommandRunner()
        self.gate = gate
        sut = makeController()
        try leftoverMeeting(at: localDate(2026, 10, 22, 9, 0), transcript: true)
        let created = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: ["Convio"])
        let listed = try XCTUnwrap(WordReview.unfinished(in: root, knownWords: .empty).first?.meeting)
        XCTAssertEqual(created, listed, "the review window and the notification name one folder")
        sut.resumeUnfinished()
        await waitUntil { gate.waiting == 1 }

        sut.updateNotes(created)
        sut.updateNotes(listed)
        sut.updateNotes(created)
        XCTAssertTrue(visibleTitles.contains("1 more meeting waiting"))
        gate.letOneThrough()
        await waitUntil { gate.runs == 2 && gate.waiting == 1 }
        sut.updateNotes(listed)
        for _ in 0..<3 { gate.letOneThrough() }
        await sut.waitUntilIdle()

        XCTAssertEqual(gate.runs, 2, "one summary, then one update")
        XCTAssertEqual(notifications.filter { $0.hasPrefix("Notes Updated") }.count, 1)
    }

    func testAnUpdateWithoutANewSummarySaysTheSummaryDidNotChange() async throws {
        let reviewed = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: ["Convio"])
        let summary = try reviewed.read(.summary)
        runner.results["agy"] = .success(CommandResult(termination: .exited(1), stdout: "", stderr: "authentication failed"))
        runner.results["claude"] = .success(CommandResult(termination: .timedOut, stdout: "", stderr: ""))

        sut.updateNotes(reviewed)
        await sut.waitUntilIdle()

        XCTAssertEqual(notifications, ["Notes Not Updated: Meeting on 2026-10-23 at 09:00. The summary tool did not answer, so the summary did not change. The transcript has your answers."])
        XCTAssertEqual(notifier.posted.last?.click, .open(reviewed.url(for: .summary)))
        XCTAssertEqual(try reviewed.read(.summary), summary)
    }

    func testAnUpdateThatFailsBeforeTheSummaryToolClaimsNothingAboutTheTranscript() async throws {
        let reviewed = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: ["Convio"])
        let summary = try reviewed.read(.summary)
        try FileManager.default.removeItem(at: reviewed.url(for: .transcript))

        sut.updateNotes(reviewed)
        await sut.waitUntilIdle()

        XCTAssertEqual(notifications, ["Notes Not Updated: Meeting on 2026-10-23 at 09:00. Ku-Ka could not update the notes, so the summary did not change."])
        XCTAssertEqual(notifier.posted.last?.click, .open(reviewed.url(for: .summary)))
        XCTAssertEqual(try reviewed.read(.summary), summary)
        XCTAssertEqual(runner.calls.count, 0, "no CLI ran")
    }

    func testAnUpdateOfABusyOrGoneMeetingSaysWhyTheNotesDidNotChange() async throws {
        let busy = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: ["Convio"])
        let gone = try reviewedMeeting(at: localDate(2026, 10, 24, 9, 0), asking: ["Yuri"])
        let otherKuKa = try busy.lock()
        try FileManager.default.removeItem(at: gone.url)

        sut.updateNotes(busy)
        sut.updateNotes(gone)
        await sut.waitUntilIdle()
        otherKuKa.release()

        XCTAssertEqual(notifications, [
            "Notes Not Updated: Meeting on 2026-10-23 at 09:00. The meeting folder was in use, for example by another Ku-Ka, so the notes did not change. Click to open Check Words and choose Update Notes again.",
            "Notes Not Updated: Meeting on 2026-10-24 at 09:00. The meeting is not finished, or its folder was moved or deleted, so the notes did not change.",
        ])
        XCTAssertEqual(notifier.posted.map(\.click), [.checkWords(busy), nil])
    }

    func testQuittingCancelsTheUpdateThatRunsAndTheOneThatWaitsAndPostsNothing() async throws {
        let gate = GatedCommandRunner()
        self.gate = gate
        sut = makeController()
        let running = try reviewedMeeting(at: localDate(2026, 10, 23, 9, 0), asking: ["Convio"])
        let waiting = try reviewedMeeting(at: localDate(2026, 10, 24, 9, 0), asking: ["Yuri"])
        let summary = try running.read(.summary)
        sut.updateNotes(running)
        sut.updateNotes(waiting)
        await waitUntil { gate.waiting == 1 }

        sut.shutDown()
        await sut.waitUntilIdle()

        XCTAssertEqual(notifications, [])
        XCTAssertEqual(try running.read(.summary), summary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: waiting.url(for: .heardTranscript).path), "never started")
    }
}

/// Waits for a pass or cancellation. Counts are locked because `run` executes off the main actor.
private final class GatedCommandRunner: CommandRunning {
    private let lock = NSLock()
    private var started = 0
    private var finished = 0
    private var passes = 0

    var runs: Int { lock.withLock { started } }
    var waiting: Int { lock.withLock { started - finished } }

    func letOneThrough() {
        lock.withLock { passes += 1 }
    }

    func run(executable: URL, arguments: [String], input: String?, searchPath: [String],
             timeout: Duration) async throws -> CommandResult {
        lock.withLock { started += 1 }
        defer { lock.withLock { finished += 1 } }
        while !takePass() {
            try await Task.sleep(for: .milliseconds(10))
        }
        return CommandResult(termination: .exited(0), stdout: defaultNotes, stderr: "")
    }

    private func takePass() -> Bool {
        lock.withLock {
            guard passes > 0 else { return false }
            passes -= 1
            return true
        }
    }
}
