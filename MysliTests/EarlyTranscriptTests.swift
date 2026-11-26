import XCTest
@testable import Mysli

final class EarlyTranscriptTests: XCTestCase {
    private let whisper = EarlyTranscriptSource(transcriber: "Whisper large-v3-v20240930_turbo", language: "en")

    func testTheFileFormat() throws {
        let early = EarlyTranscript(source: whisper, covered: 3_360_000, segments: [
            TranscriptSegment(start: 10, end: 20.5, text: " Thank you."),
            TranscriptSegment(start: 200, end: 209.25, text: " Let's ship"),
        ])
        let json = """
        {"coveredFrames":3360000,"language":"en","segments":[{"end":20.5,"start":10,"text":" Thank you."},\
        {"end":209.25,"start":200,"text":" Let's ship"}],"transcriber":"Whisper large-v3-v20240930_turbo","version":1}
        """

        XCTAssertEqual(String(decoding: try early.encoded(), as: UTF8.self), json)
        XCTAssertEqual(EarlyTranscript(json: Data(json.utf8)), early)
        XCTAssertNil(EarlyTranscript(json: Data(json.replacingOccurrences(of: "\"version\":1", with: "\"version\":2").utf8)))
        XCTAssertNil(EarlyTranscript(json: Data("{}".utf8)))
    }

    func testEarlyTranscriptsNeverChangeTheStageAndGoAwayTogether() throws {
        let meeting = try MeetingFolder.create(in: try makeTemporaryDirectory(), startingAt: localDate(2026, 10, 23, 14, 2))
        let early = EarlyTranscript(source: whisper, covered: 960_000,
                                    segments: [TranscriptSegment(start: 1, end: 2, text: " Hello")])
        for track in MeetingTrack.allCases { try meeting.saveEarlyTranscript(early, for: track) }
        XCTAssertNil(meeting.stage())
        FileManager.default.createFile(atPath: meeting.audioURL(.system).path, contents: Data())
        XCTAssertEqual(meeting.stage(), .pending(.transcribe))
        try meeting.write("speech", to: .transcript)
        XCTAssertEqual(meeting.stage(), .pending(.summarize))
        XCTAssertEqual(meeting.earlyTranscript(.microphone), early)

        try meeting.removeEarlyTranscripts()
        try meeting.removeEarlyTranscripts()

        XCTAssertNil(meeting.earlyTranscript(.microphone))
        XCTAssertNil(meeting.earlyTranscript(.system))
        XCTAssertEqual(meeting.stage(), .pending(.summarize))
    }
}
