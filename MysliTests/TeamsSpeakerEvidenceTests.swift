import XCTest
@testable import Mysli

final class TeamsSpeakerEvidenceTests: XCTestCase {
    private let run = UUID()
    private let clock = RecordingClock(origin: HostTime(seconds: 100))

    private func sample(_ start: Double, _ end: Double, _ sequence: Int,
                        _ name: String? = "Aino", source: String? = "call") -> TeamsSpeakerObservation {
        TeamsSpeakerObservation(began: HostTime(seconds: start), ended: HostTime(seconds: end),
                                sequence: sequence, sourceID: source, speaker: name.flatMap(TeamsSpeakerName.init))
    }

    private func evidence(_ samples: [TeamsSpeakerObservation], clock: RecordingClock? = nil,
                          stop: Double = 120) -> TeamsSpeakerEvidence {
        var history = TeamsSpeakerHistory()
        for sample in samples { _ = history.append(sample, runID: run) }
        return history.finish(clock: clock ?? self.clock, endingAt: HostTime(seconds: stop))
    }

    private func name(_ evidence: TeamsSpeakerEvidence, _ start: Double = 0.02, _ end: Double = 0.89) -> String? {
        evidence.name(for: TranscriptSegment(start: start, end: end, text: "Synthetic speech"))?.value
    }

    private var matching: [TeamsSpeakerObservation] {
        [sample(100, 100.01, 0), sample(100.30, 100.31, 1),
         sample(100.60, 100.61, 2), sample(100.90, 100.91, 3)]
    }

    private let aino = TeamsScanResult.named(TeamsSpeakerName("Aino")!)
    private let bo = TeamsScanResult.named(TeamsSpeakerName("Bo")!)
    private let silence = TeamsScanResult.unnamed(.noHighlightedTile)
    private let unknown = TeamsScanResult.unnamed(.multipleHighlightedTiles)

    /// Scans every 0.4 s that take 0.085 s each, as in a real call, from 100 s on. In the 10 s
    /// segment of `tenSeconds`, one scan claims about 0.4 s, which is 4 %.
    private func steady(_ count: Int = 27, _ result: (Int) -> TeamsScanResult) -> [TeamsSpeakerObservation] {
        (0..<count).map { index in
            let start = 100 + Double(index) * 0.4
            return TeamsSpeakerObservation(began: HostTime(seconds: start), ended: HostTime(seconds: start + 0.085),
                                           sequence: index, sourceID: "call", result: result(index), nodes: 5)
        }
    }

    private func tenSeconds(_ samples: [TeamsSpeakerObservation]) -> String? {
        name(evidence(samples), 0.2, 10.2)
    }

    func testSilenceDoesNotCountAgainstAName() {
        XCTAssertEqual(tenSeconds(steady { $0 == 13 ? silence : aino }), "Aino")
        XCTAssertEqual(tenSeconds(steady { $0 < 13 ? aino : silence }), "Aino")
    }

    func testTooMuchUnknownTimeKeepsThem() {
        XCTAssertEqual(tenSeconds(steady { $0 == 13 ? unknown : aino }), "Aino")
        XCTAssertNil(tenSeconds(steady { $0 < 13 ? aino : unknown }))
        XCTAssertNil(tenSeconds(steady(13) { _ in aino }), "Time that no scan claims is unknown")
    }

    func testTwoCompetingNamesKeepThem() {
        XCTAssertNil(tenSeconds(steady { $0 < 13 ? aino : bo }))
    }

    func testOneScanWithAnotherNameDoesNotVetoAClearMajority() {
        XCTAssertEqual(tenSeconds(steady { $0 == 13 ? bo : aino }), "Aino")
    }

    func testASecondNameOverItsLimitKeepsThem() {
        XCTAssertEqual(tenSeconds(steady { (12..<15).contains($0) ? bo : aino }), "Aino")
        // Aino keeps 80 %, so only the limit for the second name can reject this.
        XCTAssertNil(tenSeconds(steady { (12..<17).contains($0) ? bo : aino }))
    }

    func testAMostlySilentSegmentNeedsEnoughNamedTime() {
        XCTAssertNil(tenSeconds(steady { (12...13).contains($0) ? aino : silence }))
    }

    func testALongNamedScanSuppliesEvidence() {
        XCTAssertEqual(name(evidence([sample(100, 100.25, 0)]), 0.01, 0.24), "Aino")
    }

    func testNameRejectsReservedMarkupControlsAndOversizedValues() {
        for raw in ["", "   ", "Me", "them", "Room 1", "room 123", "A\nB", "A\tB", "A\u{0}B",
                    "A\u{2028}B", "A\u{2029}B",
                    "A*B", "A[B", "A]B", "A\\B", "A`B", "A<B", "A>B",
                    String(repeating: "a", count: 81), String(repeating: "😀", count: 65)] {
            XCTAssertNil(TeamsSpeakerName(raw), raw)
        }
        XCTAssertEqual(TeamsSpeakerName("  Aino O’Neil-Smith (客)  ")?.value, "Aino O’Neil-Smith (客)")
        XCTAssertEqual(TeamsSpeakerName(String(repeating: "a", count: 80))?.value.count, 80)
        XCTAssertEqual(TeamsSpeakerName(String(repeating: "😀", count: 64))?.value.utf8.count, 256)
    }

    func testExactGapLimitRemainsUsable() {
        let result = evidence([sample(100, 100.125, 0), sample(100.875, 100.9, 1)])
        XCTAssertEqual(name(result, 0.13, 0.87), "Aino")
    }

    func testCombiningMarksCannotHideForbiddenNameDelimiters() {
        for delimiter in ["*", "[", "]", "\\", "`", "<", ">"] {
            let raw = "A" + delimiter + "\u{301}B"
            XCTAssertNil(TeamsSpeakerName(raw), raw)
        }
        XCTAssertEqual(TeamsSpeakerName("A\u{301}ino O’Neil-Smith (客)")?.value, "A\u{301}ino O’Neil-Smith (客)")
    }

    func testConsecutiveMatchingScansNameTheCoveredSegment() {
        XCTAssertEqual(name(evidence(matching)), "Aino")
        XCTAssertNil(name(evidence(matching), -0.1, 0.05))
        XCTAssertNil(name(evidence(matching), 0.91, 0.95))
    }

    func testTheTimeBetweenScansWithDifferentResultsIsSplitInTheMiddle() {
        let result = evidence([sample(100, 100.01, 0), sample(100.3, 100.31, 1, "Bo")])
        XCTAssertEqual(name(result, 0.02, 0.15), "Aino")
        XCTAssertEqual(name(result, 0.16, 0.29), "Bo")
    }

    func testNegativeSequenceNumbersCannotSupplyCoverage() {
        let result = evidence([sample(100, 100.01, -2), sample(100.3, 100.31, -1)])
        XCTAssertNil(name(result, 0.02, 0.29))
        XCTAssertEqual(name(evidence(matching)), "Aino")
    }

    func testSequenceSourceAndRunChangesBreakContinuity() {
        for second in [sample(100.3, 100.31, 2), sample(100.3, 100.31, 1, source: "other")] {
            XCTAssertNil(name(evidence([matching[0], second]), 0.02, 0.29))
        }
        var history = TeamsSpeakerHistory()
        _ = history.append(matching[0], runID: run)
        _ = history.append(matching[1], runID: UUID())
        XCTAssertNil(name(history.finish(clock: clock, endingAt: HostTime(seconds: 101)), 0.02, 0.29))
        XCTAssertEqual(name(evidence(matching)), "Aino")
    }

    func testLargeGapAndBadTimesCannotSupplyEvidence() {
        for samples in [
            [sample(100, 100.01, 0), sample(100.761, 100.77, 1)],
            [sample(100.01, 100, 0), sample(100.3, 100.31, 1)],
            [sample(.nan, 100.01, 0), sample(100.3, 100.31, 1)],
            [sample(100, .infinity, 0), sample(100.3, 100.31, 1)],
            [sample(100.3, 100.31, 0), sample(100, 100.01, 1)],
            [sample(100, 100.1, 0), sample(100.05, 100.15, 1)],
        ] { XCTAssertNil(name(evidence(samples), 0.16, 0.29)) }
        XCTAssertEqual(name(evidence(matching)), "Aino")
    }

    func testStopDropsLateScansWithoutForwardExtrapolation() {
        XCTAssertNil(name(evidence(matching, stop: 100.5), 0.32, 0.59))
        XCTAssertEqual(name(evidence(matching, stop: 100.5), 0.02, 0.29), "Aino")
    }

    func testPauseAndResumeLeaveNoEvidenceInTheFileGap() {
        var clock = self.clock
        clock.pause(at: HostTime(seconds: 101))
        clock.resume(at: HostTime(seconds: 111))
        let after = [sample(111, 111.01, 4), sample(111.3, 111.31, 5)]
        let result = evidence(matching + after, clock: clock)
        XCTAssertEqual(name(result, 4.02, 4.29), "Aino")
        XCTAssertNil(name(result, 1.2, 3.9))
        XCTAssertNil(name(result, 0.89, 4.02))
        XCTAssertEqual(name(result), "Aino")
    }

    func testShortPauseStrictlyBetweenMappableEndpointsBreaksTheInterval() {
        var clock = self.clock
        clock.pause(at: HostTime(seconds: 100.1))
        clock.resume(at: HostTime(seconds: 100.2))
        let result = evidence([sample(100, 100.01, 0), sample(100.3, 100.31, 1)], clock: clock)
        XCTAssertNil(name(result, 0.02, 0.09))
        XCTAssertNil(name(result, 3.11, 3.19))
        XCTAssertEqual(name(evidence(matching)), "Aino")
    }

    func testInvalidScanCrossingAPauseClaimsUnknownTimeInTheRecordedPart() {
        var clock = self.clock
        clock.pause(at: HostTime(seconds: 100.8))
        clock.resume(at: HostTime(seconds: 100.9))
        let samples = Array(matching.prefix(3)) + [sample(100.2, 100.85, 3, nil)]
        XCTAssertNil(name(evidence(samples, clock: clock), 0.02, 0.59))
        XCTAssertEqual(name(evidence(Array(matching.prefix(3)), clock: clock), 0.02, 0.59), "Aino")
    }

    func testUnknownZeroReversedAndOverlappingSegmentsKeepThem() {
        let result = evidence(matching)
        for (start, end) in [(0.2, 0.2), (0.8, 0.2), (Double.nan, 0.5), (0.1, Double.infinity)] {
            XCTAssertNil(name(result, start, end))
        }
        XCTAssertEqual(name(result), "Aino")
    }

    func testCapStopsCollectionAndRetainsEarlierEvidence() {
        var history = TeamsSpeakerHistory(capacity: 4)
        for (index, sample) in matching.enumerated() {
            XCTAssertEqual(history.append(sample, runID: run), index < 3)
        }
        XCTAssertFalse(history.append(sample(101.2, 101.21, 4), runID: run))
        let result = history.finish(clock: clock, endingAt: HostTime(seconds: 120))
        XCTAssertEqual(name(result), "Aino")
        XCTAssertNil(name(result, 0.92, 1.19))
    }
}
