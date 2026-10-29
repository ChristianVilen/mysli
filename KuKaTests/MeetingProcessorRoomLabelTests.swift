import XCTest
@testable import KuKa

@MainActor
final class MeetingProcessorRoomLabelTests: MeetingProcessorTestCase {
    private func twoVoices(on transcriber: FakeTranscriber) throws -> RoomLabels {
        transcriber.byFileName["me.caf"] = .success(TrackTranscript(segments: [
            TranscriptSegment(start: 4, end: 5, text: "Sounds good, I can ship it"),
            TranscriptSegment(start: 6, end: 7, text: "Friday works for me too"),
        ], duration: 59))
        return .voices(try XCTUnwrap(RoomVoices([VoiceTurn(voice: 7, start: 3.5, end: 5.5),
                                                 VoiceTurn(voice: 3, start: 5.5, end: 7.5)])))
    }

    func testRoomVoicesLabelTheMicrophoneLinesInTheTranscript() async throws {
        let meeting = try makeMeeting()
        labeller.result = try twoVoices(on: whisper)

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(try meeting.read(.transcript), """
        # Meeting on 2026-10-23 at 14:02

        Duration: 00:01:00

        Transcript by Whisper.

        "Room 1", "Room 2", and so on are voices on the microphone of the Mac that recorded the meeting. The microphone hears the person who recorded the meeting and anyone in the same room. Ku-Ka told the voices apart on this Mac and numbered them in the order they first spoke. Two people with similar voices can share one label, and one person can get two labels. No label tells which voice is the person who recorded the meeting. "Them" is everyone else on the call.

        **[00:00:01] Them:** Let's ship on Friday

        **[00:00:04] Room 1:** Sounds good, I can ship it

        **[00:00:06] Room 2:** Friday works for me too

        """)
    }

    func testTheRoomLabellerGetsTheMicrophoneTrackAfterBothTracksAreTranscribed() async throws {
        let meeting = try makeMeeting()
        let whisper = self.whisper!
        var transcribedBeforeLabelling: [String] = []
        labeller.onLabel = { transcribedBeforeLabelling = whisper.transcribed }

        _ = await process(meeting)

        XCTAssertEqual(labeller.calls, ["label me.caf"])
        XCTAssertEqual(transcribedBeforeLabelling, ["me.caf", "them.caf"])
    }

    func testRoomLabelsAlsoRunWhenAppleWroteTheText() async throws {
        let meeting = try makeMeeting()
        whisper.failure = (.load, MeetingStepError("The model files are damaged."))
        labeller.result = try twoVoices(on: apple)

        _ = await process(meeting)

        let transcript = try meeting.read(.transcript)
        XCTAssertTrue(transcript.contains("\n\nTranscript by Apple. Tried first:\n\n"))
        XCTAssertTrue(transcript.contains(
            "**[00:00:04] Room 1:** Sounds good, I can ship it\n\n**[00:00:06] Room 2:** Friday works for me too\n"))
    }

    func testARoomLabelFailureKeepsMeAndTheMeetingStillFinishes() async throws {
        let meeting = try makeMeeting()
        labeller.result = .failed(.load("Model is corrupt."))

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(try meeting.read(.transcript), """
        # Meeting on 2026-10-23 at 14:02

        Duration: 00:01:00

        Transcript by Whisper.

        There are no room labels. SpeakerKit could not load its model: Model is corrupt.

        "Me" is the microphone of the Mac that recorded the meeting. It hears the person who recorded the meeting and anyone in the same room. "Them" is everyone else on the call.

        **[00:00:01] Them:** Let's ship on Friday

        **[00:00:04] Me:** Sounds good

        """)
        XCTAssertFalse(FileManager.default.fileExists(atPath: meeting.url(for: .failure).path))
        let prompt = try XCTUnwrap(runner.calls.first?.arguments.last)
        XCTAssertFalse(prompt.contains("There are no room labels"))
        XCTAssertEqual(labeller.calls, ["label me.caf"])
    }

    func testTheSpeakerModelDownloadStepEndsWhenTheDownloadEnds() async throws {
        let meeting = try makeMeeting()
        labeller.modelIsMissing = true
        var events: [String] = []
        labeller.onDownloadEnd = { events.append("download ended") }
        labeller.onLabel = { events.append("label") }

        let outcome = await makeProcessor().process(meeting) { events.append($0.title) }

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(events, ["Transcribing", "Downloading speaker model", "download ended", "Transcribing", "label",
                                "Summarizing"])
    }

    func testAFailedSpeakerModelDownloadKeepsMeWithTheReasonAndNeverLabels() async throws {
        let meeting = try makeMeeting()
        labeller.modelIsMissing = true
        labeller.downloadError = MeetingStepError("The Internet connection appears to be offline.")

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(progress, [.step(.transcribe), .downloading(.speaker), .step(.transcribe), .step(.summarize)])
        XCTAssertEqual(labeller.calls, ["download"])
        let transcript = try meeting.read(.transcript)
        XCTAssertTrue(transcript.contains(
            "\n\nThere are no room labels. SpeakerKit could not download its model: The Internet connection appears to be offline.\n\n"))
        XCTAssertTrue(transcript.contains("**[00:00:04] Me:** Sounds good"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: meeting.url(for: .failure).path))
    }

    private func roomLabelsMarker(_ meeting: MeetingFolder) -> String {
        meeting.url.appendingPathComponent(".room-labels-started").path
    }

    func testAMarkerExistsOnlyWhileTheLabellerLabels() async throws {
        let meeting = try makeMeeting()
        var markerWhileLabelling: Bool?
        labeller.onLabel = { [unowned self] in
            markerWhileLabelling = FileManager.default.fileExists(atPath: roomLabelsMarker(meeting))
        }

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(markerWhileLabelling, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: roomLabelsMarker(meeting)))
    }

    func testAMarkerLeftByAnEarlierAttemptSkipsRoomLabels() async throws {
        let meeting = try makeMeeting()
        FileManager.default.createFile(atPath: roomLabelsMarker(meeting), contents: Data())
        labeller.modelIsMissing = true
        labeller.result = try twoVoices(on: whisper)

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(labeller.calls, [])
        let transcript = try meeting.read(.transcript)
        XCTAssertTrue(transcript.contains("\n\nThere are no room labels. Ku-Ka skipped them, because an earlier attempt "
            + "stopped while it told the voices apart, for example in a crash.\n\n"), transcript)
        XCTAssertTrue(transcript.contains("**[00:00:04] Me:** Sounds good, I can ship it"), transcript)
    }

    func testAMicrophoneTrackLongerThanThreeHoursIsNeverLabelled() async throws {
        for (duration, calls) in [(3.0 * 60 * 60, ["download", "label me.caf"]), (3.0 * 60 * 60 + 1, [])] {
            let meeting = try makeMeeting()
            labeller = FakeRoomLabeller()
            labeller.modelIsMissing = true
            whisper.byFileName["me.caf"] = .success(TrackTranscript(
                segments: [TranscriptSegment(start: 4, end: 5, text: "Sounds good")], duration: duration))

            let outcome = await process(meeting)

            XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)), "\(duration) s")
            XCTAssertEqual(labeller.calls, calls, "\(duration) s")
            XCTAssertEqual(try meeting.read(.transcript).contains(
                "\n\nThere are no room labels. Ku-Ka skipped them, because the microphone track is longer than 3 hours.\n\n"),
                calls.isEmpty, "\(duration) s")
        }
    }

    func testAMicrophoneWithOnlyEchoesIsNeverLabelled() async throws {
        let meeting = try makeMeeting()
        whisper.byFileName["me.caf"] = .success(TrackTranscript(
            segments: [TranscriptSegment(start: 1.5, end: 3.2, text: "Let's ship on Friday")], duration: 59))
        labeller.modelIsMissing = true
        labeller.result = .failed(.load("Model is corrupt."))

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .done(summary: meeting.url(for: .summary)))
        XCTAssertEqual(labeller.calls, [])
        XCTAssertEqual(progress, [.step(.transcribe), .step(.summarize)])
        XCTAssertFalse(try meeting.read(.transcript).contains("There are no room labels"))
    }

    func testAFailedTranscriptionNeverAsksForRoomLabels() async throws {
        let meeting = try makeMeeting()
        whisper.byFileName["them.caf"] = .failure(TestError(errorDescription: "Out of memory."))

        let outcome = await process(meeting)

        XCTAssertEqual(outcome, .failed(.transcribe, message: "Out of memory."))
        XCTAssertEqual(labeller.calls, [])
    }

    func testCancellingDuringRoomLabellingWritesNothingAndLeavesTheMeetingPending() async throws {
        for result in [try twoVoices(on: whisper), .failed(.download("cancelled"))] {
            let meeting = try makeMeeting()
            labeller.result = result
            labeller.cancelsItsTask = true
            let processor = makeProcessor()
            let run = Task { await process(meeting, with: processor) }

            let outcome = await run.value

            XCTAssertEqual(outcome, .cancelled, "\(result)")
            XCTAssertEqual(meeting.stage(), .pending(.transcribe), "\(result)")
            XCTAssertTrue(audioExists(meeting), "\(result)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: roomLabelsMarker(meeting)), "\(result)")
            for document in MeetingDocument.allCases {
                XCTAssertFalse(FileManager.default.fileExists(atPath: meeting.url(for: document).path),
                               "\(result): \(document.rawValue)")
            }
        }
    }
}
