import XCTest
@testable import KuKa

final class TranscriptTests: XCTestCase {
    private func segment(_ start: TimeInterval, _ end: TimeInterval, _ text: String) -> TranscriptSegment {
        TranscriptSegment(start: start, end: end, text: text)
    }

    private func merge(me: [TranscriptSegment] = [], them: [TranscriptSegment] = []) -> [TranscriptLine] {
        Transcript.merge([
            .microphone: TrackTranscript(segments: me, duration: 60),
            .system: TrackTranscript(segments: them, duration: 60),
        ])
    }

    func testMergeInterleavesTheTracksByStartTime() {
        let lines = merge(me: [segment(4, 5, "Sounds good")],
                          them: [segment(1, 3, "Let's ship on Friday"), segment(8, 9, "Great, thanks")])

        XCTAssertEqual(lines, [
            TranscriptLine(speaker: .them, start: 1, text: "Let's ship on Friday"),
            TranscriptLine(speaker: .me, start: 4, text: "Sounds good"),
            TranscriptLine(speaker: .them, start: 8, text: "Great, thanks"),
        ])
    }

    func testMergeJoinsASpeakersSegmentsWhileTheGapIsShort() {
        let lines = merge(them: [segment(1, 3, "Hello"), segment(4, 6, "everyone."), segment(9, 10, "Next topic.")])

        XCTAssertEqual(lines, [
            TranscriptLine(speaker: .them, start: 1, text: "Hello everyone."),
            TranscriptLine(speaker: .them, start: 9, text: "Next topic."),
        ])
    }

    func testMergeDoesNotJoinAcrossTheOtherSpeaker() {
        let lines = merge(me: [segment(3.2, 3.6, "Yes")], them: [segment(1, 3, "Ready?"), segment(4, 5, "Good.")])

        XCTAssertEqual(lines.map(\.text), ["Ready?", "Yes", "Good."])
    }

    func testMergePutsThemFirstWhenBothStartTogether() {
        let lines = merge(me: [segment(2, 3, "Right on time")], them: [segment(2, 4, "Starting now team")])

        XCTAssertEqual(lines.map(\.speaker), [.them, .me])
    }

    func testMergeDropsMicrophoneEchoesOfTheSystemTrack() {
        let lines = merge(me: [segment(10.5, 14.2, "We should move the launch to Friday."), segment(20, 21, "Agreed.")],
                          them: [segment(10, 14, "we should move the launch to friday")])

        XCTAssertEqual(lines, [
            TranscriptLine(speaker: .them, start: 10, text: "we should move the launch to friday"),
            TranscriptLine(speaker: .me, start: 20, text: "Agreed."),
        ])
    }

    func testMergeDropsAMeasuredSpeakerEchoSplitInTwo() {
        let them = segment(4.98, 10.56, "The quick brown fox jumps over the lazy dog, released 2.4 ships on Tuesday.")
        let lines = merge(me: [segment(6.0, 8.64, "The quick brown fox jumps over the lazy dog."),
                               segment(8.64, 11.64, "Release 2.4 ships on Tuesday.")],
                          them: [them])

        XCTAssertEqual(lines, [TranscriptLine(speaker: .them, start: 4.98, text: them.text)])
    }

    func testMergeSkipsSegmentsWithoutText() {
        XCTAssertEqual(merge(me: [segment(1, 2, "  ")], them: [segment(3, 4, "Hi")]).map(\.text), ["Hi"])
    }

    func testEchoNeedsSixtyPercentOfTheMicrophoneWords() {
        let system = segment(10, 14, "We should move the launch to Friday")

        XCTAssertTrue(Transcript.isEcho(segment(11, 13, "we should move it later"), of: system))
        XCTAssertFalse(Transcript.isEcho(segment(11, 13, "we should go somewhere else"), of: system))
    }

    func testEchoNeedsTheSegmentsToOverlapWithinOneSecond() {
        let system = segment(10, 14, "We should move the launch to Friday")

        XCTAssertTrue(Transcript.isEcho(segment(14.8, 16, "move the launch"), of: system))
        XCTAssertFalse(Transcript.isEcho(segment(15.5, 16, "move the launch"), of: system))
    }

    func testShortMicrophoneRepliesAreNeverEchoes() {
        XCTAssertFalse(Transcript.isEcho(segment(11, 12, "to Friday"), of: segment(10, 14, "move the launch to Friday")))
        XCTAssertTrue(Transcript.isEcho(segment(11, 12, "launch to Friday"), of: segment(10, 14, "move the launch to Friday")))
    }

    func testMarkdownListsOneTimestampedParagraphPerLine() {
        let markdown = Transcript.markdown([
            TranscriptLine(speaker: .them, start: 1.7, text: "Let's ship on Friday"),
            TranscriptLine(speaker: .me, start: 3604, text: "Sounds good"),
        ], title: "Meeting on 2026-10-23 at 14:02", duration: 3729, by: "Whisper large-v3-v20240930_turbo", after: [])

        XCTAssertEqual(markdown, """
        # Meeting on 2026-10-23 at 14:02

        Duration: 01:02:09

        Transcript by Whisper large-v3-v20240930_turbo.

        "Me" is the person who recorded the meeting. "Them" is everyone else on the call.

        **[00:00:01] Them:** Let's ship on Friday

        **[01:00:04] Me:** Sounds good

        """)
    }

    func testMarkdownListsWhatFailedBeforeTheTranscriberThatWroteIt() {
        let markdown = Transcript.markdown(
            [TranscriptLine(speaker: .them, start: 1, text: "Let's ship on Friday")],
            title: "Meeting on 2026-10-23 at 14:02", duration: 60, by: "Apple speech recognition",
            after: [TranscriberFailure(transcriber: "Whisper large-v3-v20240930_turbo", stage: .download,
                                       message: "The Internet connection appears to be offline.")])

        XCTAssertEqual(markdown, """
        # Meeting on 2026-10-23 at 14:02

        Duration: 00:01:00

        Transcript by Apple speech recognition. Tried first:

        - Whisper large-v3-v20240930_turbo could not download its model: The Internet connection appears to be offline.

        "Me" is the person who recorded the meeting. "Them" is everyone else on the call.

        **[00:00:01] Them:** Let's ship on Friday

        """)
    }
}
