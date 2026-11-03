import XCTest
@testable import KuKa

final class TranscriptTeamsTests: XCTestCase {
    private let aino = TeamsSpeakerName("Aino")!
    private let bo = TeamsSpeakerName("Bo")!

    private func evidence() -> TeamsSpeakerEvidence {
        var history = TeamsSpeakerHistory()
        let run = UUID()
        for index in 0...10 {
            let time = 100 + Double(index) * 0.3
            _ = history.append(TeamsSpeakerObservation(began: HostTime(seconds: time),
                ended: HostTime(seconds: time + 0.01), sequence: index, sourceID: "synthetic",
                speaker: index < 5 ? aino : bo), runID: run)
        }
        return history.finish(clock: RecordingClock(origin: HostTime(seconds: 100)), endingAt: HostTime(seconds: 104))
    }

    private var system: [TranscriptSegment] {
        [TranscriptSegment(start: 0.02, end: 0.59, text: "Ship Convio."),
         TranscriptSegment(start: 0.62, end: 0.89, text: "On Friday."),
         TranscriptSegment(start: 1.52, end: 2.39, text: "That sounds good.")]
    }

    private func markdown(_ lines: [TranscriptLine], rooms: RoomLabels = .notDiarized) -> String {
        Transcript.markdown(lines, title: "Synthetic meeting", duration: 4, by: "Fake transcriber", after: [], rooms: rooms,
                            teams: .empty)
    }

    func testNamesAreAssignedBeforeJoiningAndUseTheSystemTrack() {
        let lines = Transcript.merge([.system: system], rooms: .notDiarized, speakers: evidence())
        XCTAssertEqual(lines, [TranscriptLine(speaker: .teams(aino), start: 0.02, text: "Ship Convio. On Friday."),
                               TranscriptLine(speaker: .teams(bo), start: 1.52, text: "That sounds good.")])
        XCTAssertEqual(lines.map(\.speaker.track), [.system, .system])
        XCTAssertEqual(lines.map(\.speaker.label), ["Aino (Teams)", "Bo (Teams)"])
    }

    func testEmptyEvidencePreservesExistingOutputByteForByte() {
        let lines = Transcript.merge([.system: system], rooms: .notDiarized, speakers: .empty)
        XCTAssertEqual(lines, [TranscriptLine(speaker: .them, start: 0.02, text: "Ship Convio. On Friday. That sounds good.")])
    }

    func testNamedLabelsSurviveCorrectionQuotePlacementAndSummaryExtraction() {
        let text = markdown(Transcript.merge([.system: system], rooms: .notDiarized, speakers: evidence()))
        let corrector = KnownWordsList(markdown: "- Convio → **Konvio** ✓\n- Aino → **Other** ✓\n").corrector
        let corrected = Transcript.corrected(text, by: corrector)
        XCTAssertTrue(corrected.body.contains("Aino (Teams):** Ship Konvio. On Friday."))
        XCTAssertEqual(Transcript.place(of: "Ship Konvio", in: corrected.body), "Aino (Teams) at 00:00:00")
        XCTAssertEqual(Transcript.contentForSummary(corrected.body), """
        **[00:00:00] Aino (Teams):** Ship Konvio. On Friday.

        **[00:00:01] Bo (Teams):** That sounds good.

        """)
        XCTAssertTrue(text.contains("best-effort Teams meeting UI observations"))
    }

    func testUnnamedTranscriptSaysWhyAfterTheFailureLinesAndBeforeTheLegend() throws {
        let lines = Transcript.merge([.system: system], rooms: .notDiarized, speakers: .empty)
        let scans = TeamsScanSummary((0..<4).map { index in
            TeamsSpeakerObservation(began: HostTime(seconds: Double(index)), ended: HostTime(seconds: Double(index) + 0.01),
                                    sequence: index, sourceID: nil, result: .unnamed(.noMeetingWindow), nodes: 3)
        })
        let text = Transcript.markdown(lines, title: "Synthetic meeting", duration: 4, by: "Fake transcriber", after: [],
                                       rooms: .failed(.noVoices), teams: scans)
        let roomLine = "There are no room labels. \(RoomLabelFailure.noVoices)"
        let teamsNote = try XCTUnwrap(scans.transcriptNote(for: lines))
        let legend = "\"Me\" is the microphone"
        let positions = try [roomLine, teamsNote, legend].map { try XCTUnwrap(text.range(of: $0)).lowerBound }
        XCTAssertEqual(positions, positions.sorted())
        let summary = Transcript.contentForSummary(text)
        for part in [roomLine, teamsNote, legend] { XCTAssertFalse(summary.contains(part), part) }
        XCTAssertTrue(summary.contains("Them:** Ship Convio. On Friday. That sounds good."))
    }

    func testOverlappingSystemSegmentsKeepThem() {
        let overlapping = [TranscriptSegment(start: 0.02, end: 0.59, text: "One"),
                           TranscriptSegment(start: 0.3, end: 0.89, text: "Two")]
        let lines = Transcript.merge([.system: overlapping], rooms: .notDiarized, joinGap: nil, speakers: evidence())
        XCTAssertEqual(lines.map(\.speaker), [.them, .them])
    }

    func testRoomLabelsAndMicrophoneEchoFilteringArePreserved() {
        let remote = TranscriptSegment(start: 0.02, end: 0.89, text: "We should ship this on Friday.")
        let microphone = [TranscriptSegment(start: 0.02, end: 0.89, text: remote.text),
                          TranscriptSegment(start: 4, end: 5, text: "I can check the release now."),
                          TranscriptSegment(start: 6, end: 7, text: "I will read the release notes.")]
        let rooms = RoomLabels.voices(RoomVoices([VoiceTurn(voice: 1, start: 4, end: 5),
                                                  VoiceTurn(voice: 2, start: 6, end: 7)])!)
        let lines = Transcript.merge([.microphone: microphone, .system: [remote]], rooms: rooms, speakers: evidence())
        XCTAssertEqual(lines.map(\.speaker), [.teams(aino), .room(1), .room(2)])
        let text = markdown(lines, rooms: rooms)
        XCTAssertTrue(text.contains("best-effort Teams meeting UI observations"))
        XCTAssertTrue(Transcript.contentForSummary(text).hasPrefix("**[00:00:00] Aino (Teams):**"))
    }
}
