import XCTest
@testable import KuKa

@MainActor
final class MeetingNotesControllerTests: MeetingNotesTestCase {
    func testCalendarTitleAppearsInRecordingStatus() async {
        _ = await recorder.startRecording(title: "Planning")
        sut.menuWillOpen()
        XCTAssertTrue(visibleTitles.contains("● Recording · 0:00 · Planning"), "\(visibleTitles)")
        hostTime = HostTime(seconds: 1_010)
        recorder.pause()
        sut.menuWillOpen()
        XCTAssertTrue(visibleTitles.contains("Paused · 0:10 · Planning"), "\(visibleTitles)")
    }

    func testLongCalendarTitleDoesNotStretchMenu() async throws {
        let title = String(repeating: "A", count: 120)
        _ = await recorder.startRecording(title: title)
        sut.menuWillOpen()
        let status = try XCTUnwrap(item(titled: "● Recording · 0:00 · \(String(repeating: "A", count: 47))…"))
        XCTAssertEqual(status.toolTip, title)
        XCTAssertEqual(status.accessibilityLabel(), "● Recording · 0:00 · \(title)")
    }

    private func changeFolder(to folder: URL) {
        root = folder
        sut.meetingsFolderChanged()
    }

    func testChangingTheFolderImmediatelyChangesOpenAndTheNextRecording() async throws {
        let previous = try XCTUnwrap(root)
        let newFolder = previous.deletingLastPathComponent().appendingPathComponent("New notes", isDirectory: true)
        try leftoverMeeting(at: clock, failure: "Failed")
        sut.menuWillOpen()
        let retry = try XCTUnwrap(item(titled: "Retry Failed Meeting"))

        changeFolder(to: newFolder)

        XCTAssertFalse(FileManager.default.fileExists(atPath: newFolder.path))
        XCTAssertTrue(retry.isHidden)
        let open = try XCTUnwrap(item(titled: "Open Meetings Folder"))
        _ = (open.target as? NSObject)?.perform(open.action, with: open)
        XCTAssertEqual(opened, [newFolder])
        await recorder.toggleRecording()
        XCTAssertEqual(MeetingFolder.all(in: newFolder).count, 1)
        XCTAssertEqual(MeetingFolder.all(in: previous).count, 1)
    }

    func testChangingTheFolderKeepsTheActiveAndQueuedMeetingsAtTheirOriginalPaths() async throws {
        let previous = try XCTUnwrap(root)
        let queued = try leftoverMeeting(at: localDate(2026, 10, 22, 9, 0))
        let nextQueued = try leftoverMeeting(at: localDate(2026, 10, 22, 10, 0))
        await recorder.toggleRecording()
        let active = try XCTUnwrap(MeetingFolder.all(in: previous).last?.0)
        sut.resumeUnfinished()
        let newFolder = previous.deletingLastPathComponent().appendingPathComponent("Other notes")

        changeFolder(to: newFolder)
        recorder.stopRecording()
        await sut.waitUntilIdle()

        XCTAssertEqual(queued.stage(), .done)
        XCTAssertEqual(nextQueued.stage(), .done)
        XCTAssertEqual(active.stage(), .done)
        XCTAssertFalse(FileManager.default.fileExists(atPath: newFolder.path))
        XCTAssertEqual(notifier.posted.compactMap(\.url).map { $0.deletingLastPathComponent() },
                       [queued.url, nextQueued.url, active.url])
    }

    private func meetingNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
    }

    func testTheIdleMenuOffersToStartRecording() {
        XCTAssertEqual(visibleTitles, ["Meeting Notes", "Start Recording Meeting", "Open Meetings Folder", ""])
        XCTAssertEqual(recorder.phase, .idle)
    }

    func testHiddenControlsKeepRecordingAndShowMeetingControlsBringsThemBackWithFocus() async throws {
        await recorder.toggleRecording()

        recorder.dismissControls()
        XCTAssertNil(recorder.controls)
        XCTAssertEqual(recorder.phase, .recording)

        let show = try XCTUnwrap(item(titled: "Show Meeting Controls"))
        _ = (show.target as? NSObject)?.perform(show.action, with: show)

        XCTAssertEqual(recorder.controls, MeetingControls(status: .recording, recordedTime: 0))
        XCTAssertEqual(controlsRequests, [.focus])
    }

    func testRestoreDefaultPositionAsksThePanelToMoveBack() async throws {
        await recorder.toggleRecording()

        let restore = try XCTUnwrap(item(titled: "Restore Default Position"))
        _ = (restore.target as? NSObject)?.perform(restore.action, with: restore)

        XCTAssertEqual(controlsRequests, [.restoreDefaultPosition])
    }

    func testAMenuTickShowsTheRecordedTime() async {
        await recorder.toggleRecording()
        hostTime = hostTime + 245

        sut.menuTick()

        XCTAssertTrue(visibleTitles.contains("● Recording · 4:05"), "\(visibleTitles)")
    }

    func testRecordingCommandsWhileIdleDoNothingAndStartNothing() {
        recorder.pause()
        recorder.resume()
        recorder.togglePause()
        recorder.stopRecording()

        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertEqual(stateChanges, 0)
        XCTAssertEqual(capture.recordings.count, 0)
        XCTAssertEqual(meetingNames(), [])
    }

    func testTheMenuOffersPauseWhileRecordingAndResumeWhilePaused() async throws {
        await recorder.toggleRecording()
        XCTAssertEqual(visibleTitles, ["Meeting Notes", "● Recording · 0:00", "Stop Recording Meeting", "Pause Recording",
                                       "Write Meeting Notes…", "Show Meeting Controls", "Restore Default Position", "Recent Meeting Notes", "Open Meetings Folder", ""])

        hostTime = HostTime(seconds: 1_010)
        let pause = try XCTUnwrap(item(titled: "Pause Recording"))
        _ = (pause.target as? NSObject)?.perform(pause.action, with: pause)

        XCTAssertEqual(recorder.phase, .paused)
        XCTAssertEqual(visibleTitles, ["Meeting Notes", "Paused · 0:10", "Stop Recording Meeting", "Resume Recording",
                                       "Write Meeting Notes…", "Show Meeting Controls", "Restore Default Position", "Recent Meeting Notes", "Open Meetings Folder", ""])

        hostTime = HostTime(seconds: 1_040)
        let resume = try XCTUnwrap(item(titled: "Resume Recording"))
        _ = (resume.target as? NSObject)?.perform(resume.action, with: resume)

        XCTAssertEqual(recorder.phase, .recording)
    }

    func testStoppingAndRestartingCannotShowThePreviousRecordingLevels() async throws {
        await recorder.toggleRecording()
        try XCTUnwrap(capture.recordings.last).levels = RecordingAudioLevels(microphone: 1, system: 0.5)
        sut.menuWillOpen()
        let meterItem = try XCTUnwrap(menu.items.first { $0.view != nil })
        XCTAssertEqual(levelIndicators(in: try XCTUnwrap(meterItem.view)).map(\.doubleValue), [1, 0.5])

        await recorder.toggleRecording()
        await sut.waitUntilIdle()
        XCTAssertTrue(meterItem.isHidden)

        await recorder.toggleRecording()
        XCTAssertFalse(meterItem.isHidden)
        XCTAssertEqual(levelIndicators(in: try XCTUnwrap(meterItem.view)).map(\.doubleValue), [0, 0])
    }

    func testStatusMenuCloseStopsMeterUpdatesAndReopenReadsCurrentLevels() async throws {
        let interval: TimeInterval = 0.005
        meterInterval = interval
        sut = makeController()
        await recorder.toggleRecording()
        let handle = try XCTUnwrap(capture.recordings.last)
        handle.levels = RecordingAudioLevels(microphone: 0.2, system: 0.8)
        menu.removeAllItems()
        let statusMenu = StatusMenu(sections: [sut])
        statusMenu.menuWillOpen(statusMenu.menu)
        defer { statusMenu.menuDidClose(statusMenu.menu) }
        let meterItem = try XCTUnwrap(statusMenu.menu.items.first { $0.view != nil })
        let indicators = levelIndicators(in: try XCTUnwrap(meterItem.view))
        XCTAssertEqual(indicators.map(\.doubleValue), [0.2, 0.8])

        handle.levels = RecordingAudioLevels(microphone: 0.7, system: 0.3)
        runMenuLoop(for: 1) { indicators.map(\.doubleValue) == [0.7, 0.3] }
        XCTAssertEqual(indicators.map(\.doubleValue), [0.7, 0.3])

        statusMenu.menuDidClose(statusMenu.menu)
        handle.levels = RecordingAudioLevels(microphone: 0.1, system: 0.9)
        runMenuLoop(for: 4 * interval)
        XCTAssertEqual(indicators.map(\.doubleValue), [0.7, 0.3])

        statusMenu.menuWillOpen(statusMenu.menu)
        XCTAssertEqual(indicators.map(\.doubleValue), [0.1, 0.9])
        sut.shutDown()
        XCTAssertTrue(meterItem.isHidden)
    }

    private func levelIndicators(in view: NSView) -> [NSLevelIndicator] {
        if let indicator = view as? NSLevelIndicator { return [indicator] }
        return view.subviews.flatMap { levelIndicators(in: $0) }
    }

    /// Runs the run loop as an open menu does, for `duration` or until `done`.
    private func runMenuLoop(for duration: TimeInterval, until done: () -> Bool = { false }) {
        let deadline = Date().addingTimeInterval(duration)
        while !done(), Date() < deadline {
            RunLoop.current.run(mode: .eventTracking, before: min(deadline, Date().addingTimeInterval(0.001)))
        }
    }

    func testStopProcessesTheMeetingAndSaysTheNotesAreReady() async throws {
        await recorder.toggleRecording()

        await recorder.toggleRecording()
        await sut.waitUntilIdle()

        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertEqual(stateChanges, 3, "starting, recording, then idle")
        XCTAssertEqual(capture.recordings.first?.stopCount, 1)
        XCTAssertEqual(notifications, ["Meeting Notes Ready: Meeting on 2026-10-23 at 14:02. Click to open the summary."])
        let meeting = try XCTUnwrap(MeetingFolder.all(in: root).first?.0)
        XCTAssertEqual(meeting.stage(), .done)
        XCTAssertEqual(notifier.posted.last?.url?.resolvingSymlinksInPath(), meeting.url(for: .summary).resolvingSymlinksInPath(),
                       "a click opens the summary")
        XCTAssertEqual(notifier.permissionRequests, 1, "asked at Start, not at the first notice")
        XCTAssertEqual(visibleTitles, ["Meeting Notes", "Start Recording Meeting", "Recent Meeting Notes", "Open Meetings Folder", ""])
    }

    func testCaptureEndingOnItsOwnSaysSoAtOnceAndProcessesWhatWasRecorded() async throws {
        await recorder.toggleRecording()

        capture.interrupt(reason: "The display was disconnected.")

        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertEqual(notifications, ["Recording Stopped: The display was disconnected. Ku-Ka makes notes from what it recorded. To record the rest, choose Start Recording Meeting."])
        await sut.waitUntilIdle()
        XCTAssertEqual(notifications.last, "Meeting Notes Ready: Meeting on 2026-10-23 at 14:02. Click to open the summary.")
    }

    func testACaptureThatEndsWhileStartingIsReportedAndProcessed() async throws {
        capture.endsWhileStarting = "The microphone stopped."

        await recorder.toggleRecording()

        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertEqual(notifications, ["Recording Stopped: The microphone stopped. Ku-Ka makes notes from what it recorded. To record the rest, choose Start Recording Meeting."])
        XCTAssertEqual(liveTranscriber.starts.count, 0)
        await sut.waitUntilIdle()
        XCTAssertEqual(notifications.last, "Meeting Notes Ready: Meeting on 2026-10-23 at 14:02. Click to open the summary.")
    }

    func testCaptureThatCannotStartLeavesNoFolderAndSaysWhy() async {
        capture.startError = TestError(errorDescription: "No display is available to capture audio from.")

        await recorder.toggleRecording()

        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertEqual(meetingNames(), [])
        XCTAssertEqual(alerts, ["No display is available to capture audio from."])
        XCTAssertEqual(permissionWindows, 0)
        XCTAssertEqual(notifications, [])
    }

    func testMissingScreenRecordingSaysWhyAndOffersThePermissionsWindow() async {
        screenRecording = false

        await recorder.toggleRecording()

        XCTAssertEqual(alerts, ["Ku-Ka needs Screen Recording permission to record the other people on the call."])
        XCTAssertEqual(permissionWindows, 1)
        XCTAssertEqual(capture.recordings.count, 0)
        XCTAssertEqual(meetingNames(), [])
    }

    func testASecondClickWhileTheMicrophonePromptIsUpStartsNothing() async {
        microphone = .notDetermined
        var prompt: CheckedContinuation<Bool, Never>?
        answerMicrophonePrompt = { await withCheckedContinuation { prompt = $0 } }
        let firstClick = Task { await recorder.toggleRecording() }
        await waitUntil { prompt != nil }
        XCTAssertTrue(visibleTitles.contains("Starting Recording"))
        XCTAssertEqual(item(titled: "Start Recording Meeting").map(sut.validateMenuItem), false, "the record item is disabled while starting")

        await recorder.toggleRecording()
        microphone = .granted
        prompt?.resume(returning: true)
        await firstClick.value

        XCTAssertEqual(capture.recordings.count, 1)
        XCTAssertEqual(recorder.phase, .recording)
    }

    func testLaunchFinishesUnfinishedMeetingsOnceAndLeavesFailedOnesForRetry() async throws {
        try leftoverMeeting(at: localDate(2026, 10, 22, 9, 0))
        let failed = try leftoverMeeting(at: localDate(2026, 10, 22, 10, 0), failure: "Speech model missing")

        sut.resumeUnfinished()
        sut.resumeUnfinished()
        await sut.waitUntilIdle()

        XCTAssertEqual(notifications, ["Meeting Notes Ready: Meeting on 2026-10-22 at 09:00. Click to open the summary."])
        XCTAssertEqual(failed.stage(), .failed(.transcribe))
    }

    func testRetryRunsFailedMeetingsFromTheStepThatFailed() async throws {
        let failed = try leftoverMeeting(at: localDate(2026, 10, 22, 10, 0), failure: "agy exited with status 1", transcript: true)
        sut.menuWillOpen()
        XCTAssertEqual(visibleTitles, ["Meeting Notes", "Start Recording Meeting", "Retry Failed Meeting", "Recent Meeting Notes", "Open Meetings Folder", ""])

        let retry = try XCTUnwrap(item(titled: "Retry Failed Meeting"))
        _ = (retry.target as? NSObject)?.perform(retry.action, with: retry)
        await sut.waitUntilIdle()

        XCTAssertEqual(failed.stage(), .done)
        XCTAssertEqual(notifications, ["Meeting Notes Ready: Meeting on 2026-10-22 at 10:00. Click to open the summary."])
        XCTAssertEqual(visibleTitles, ["Meeting Notes", "Start Recording Meeting", "Recent Meeting Notes", "Open Meetings Folder", ""])
    }

    func testTheRetryItemCountsTheFailedMeetings() throws {
        try leftoverMeeting(at: localDate(2026, 10, 22, 9, 0), failure: "Speech model missing")
        try leftoverMeeting(at: localDate(2026, 10, 22, 10, 0), failure: "agy exited with status 1", transcript: true)

        sut.menuWillOpen()

        XCTAssertNotNil(item(titled: "Retry 2 Failed Meetings"))
    }

    func testAFailedTranscriptionIsReportedWithTheRetryHint() async throws {
        (transcriber as? FakeTranscriber)?.byFileName["them.caf"] = .failure(TestError(errorDescription: "The audio file could not be read."))
        try leftoverMeeting(at: localDate(2026, 10, 22, 9, 0))

        sut.resumeUnfinished()
        await sut.waitUntilIdle()

        XCTAssertEqual(notifications, ["Transcription Failed: Meeting on 2026-10-22 at 09:00. Choose Retry Failed Meeting in the Ku-Ka menu to try again. Click to see what went wrong."])
    }

    func testTheProgressItemNamesTheStepAndTheWaitingMeetings() async throws {
        transcriber = SuspendedTranscriber()
        sut = makeController()
        try leftoverMeeting(at: localDate(2026, 10, 22, 9, 0))
        try leftoverMeeting(at: localDate(2026, 10, 22, 10, 0))

        sut.resumeUnfinished()
        await waitUntil { visibleTitles.contains("Transcribing: Meeting on 2026-10-22 at 09:00") }

        XCTAssertEqual(visibleTitles, ["Meeting Notes", "Start Recording Meeting",
                                       "Transcribing: Meeting on 2026-10-22 at 09:00", "1 more meeting waiting",
                                       "Open Meetings Folder", ""])
    }

    func testQuittingWhileRecordingClosesTheFilesAndLeavesTheMeetingForTheNextLaunch() async throws {
        await recorder.toggleRecording()

        sut.shutDown()
        await sut.waitUntilIdle()

        XCTAssertEqual(capture.recordings.first?.stopCount, 1)
        XCTAssertEqual(MeetingFolder.all(in: root).map { $0.1 }, [.pending(.transcribe)])
        XCTAssertEqual(notifications, [])
    }

    func testQuittingWhileProcessingMarksNothingFailed() async throws {
        transcriber = SuspendedTranscriber()
        sut = makeController()
        let meeting = try leftoverMeeting(at: localDate(2026, 10, 22, 9, 0))
        FileManager.default.createFile(atPath: meeting.url.appendingPathComponent(".room-labels-started").path,
                                       contents: Data())
        sut.resumeUnfinished()
        await waitUntil { visibleTitles.contains("Transcribing: Meeting on 2026-10-22 at 09:00") }
        XCTAssertNotNil(item(titled: "Transcribing: Meeting on 2026-10-22 at 09:00"))

        sut.shutDown()
        await sut.waitUntilIdle()

        XCTAssertEqual(meeting.stage(), .pending(.transcribe))
        XCTAssertEqual(notifications, [])
        XCTAssertTrue(meeting.roomLabelsStarted, "the marker that a crash left, so the next run still skips room labels")
    }

    func testQuittingWhileLabellingRoomsRemovesTheMarkerSoTheNextRunLabelsTheMeeting() async throws {
        try XCTUnwrap(transcriber as? FakeTranscriber).byFileName["me.caf"] = .success(TrackTranscript(
            segments: [TranscriptSegment(start: 4, end: 5, text: "Sounds good")], duration: 59))
        roomLabeller = WaitingRoomLabeller()
        sut = makeController()
        let meeting = try leftoverMeeting(at: localDate(2026, 10, 22, 9, 0))
        FileManager.default.createFile(atPath: meeting.audioURL(.microphone).path, contents: Data())
        sut.resumeUnfinished()
        await waitUntil { [unowned self] in roomLabeller.calls == ["label me.caf"] }
        XCTAssertTrue(meeting.roomLabelsStarted)

        sut.shutDown()

        XCTAssertFalse(meeting.roomLabelsStarted, "the process ends before the processor removes the marker")
        await sut.waitUntilIdle()
        roomLabeller = FakeRoomLabeller()
        sut = makeController()
        sut.resumeUnfinished()
        await sut.waitUntilIdle()
        XCTAssertEqual(roomLabeller.calls, ["label me.caf"])
        XCTAssertFalse(try meeting.read(.transcript).contains("There are no room labels"))
    }

    func testOpenMeetingsFolderCreatesAndOpensTheConfiguredFolder() throws {
        let open = try XCTUnwrap(item(titled: "Open Meetings Folder"))

        _ = (open.target as? NSObject)?.perform(open.action, with: open)

        XCTAssertEqual(opened, [root])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }
}

/// `label` waits until its task is cancelled.
private final class WaitingRoomLabeller: FakeRoomLabeller {
    override func label(_ microphone: URL) async -> RoomLabels {
        let result = await super.label(microphone)
        try? await Task.sleep(for: .seconds(60))
        return result
    }
}
