import XCTest
@testable import KuKa

final class TeamsScanDiagnosticsTests: XCTestCase {
    private let ada = TeamsSpeakerName("Ada")!

    private func scan(_ time: Double, _ result: TeamsScanResult, took duration: Double = 0.01,
                      nodes: Int = 5) -> TeamsSpeakerObservation {
        TeamsSpeakerObservation(began: HostTime(seconds: time), ended: HostTime(seconds: time + duration),
                                sequence: Int(time * 10), sourceID: "call", result: result, nodes: nodes)
    }

    private func summary(_ results: [TeamsScanResult]) -> TeamsScanSummary {
        TeamsScanSummary(results.enumerated().map { scan(Double($0.offset), $0.element) })
    }

    private func lines(remote: Int, named: Int = 0) -> [TranscriptLine] {
        (0..<remote).map { TranscriptLine(speaker: $0 < named ? .teams(ada) : .them, start: Double($0), text: "Hi") }
            + [TranscriptLine(speaker: .me, start: 99, text: "Hello")]
    }

    func testSummaryCountsReasonsTimesAndNodes() {
        let summary = TeamsScanSummary([
            scan(0, .named(ada), took: 0.010, nodes: 40),
            scan(1, .unnamed(.deadline), took: 0.150, nodes: 498),
            scan(2, .unnamed(.noMeetingWindow), took: 0.020, nodes: 12),
            scan(3, .unnamed(.noMeetingWindow), took: 0.030, nodes: 12)
        ])
        XCTAssertEqual(summary.scans, 4)
        XCTAssertEqual(summary.named, 1)
        XCTAssertEqual(summary.reasons, [.deadline: 1, .noMeetingWindow: 2])
        XCTAssertEqual(summary.medianScanTime, 0.025, accuracy: 1e-9)
        XCTAssertEqual(summary.longestScanTime, 0.150, accuracy: 1e-9)
        XCTAssertEqual(summary.largestNodeCount, 498)
        XCTAssertEqual(TeamsScanSummary([]), .empty)
    }

    func testHistoryCountsOnlyTheScansBeforeStop() {
        var history = TeamsSpeakerHistory()
        let run = UUID()
        for sample in [scan(100, .named(ada)), scan(100.3, .unnamed(.noTeamsApp)), scan(130, .named(ada))] {
            _ = history.append(sample, runID: run)
        }
        let evidence = history.finish(clock: RecordingClock(origin: HostTime(seconds: 100)),
                                      endingAt: HostTime(seconds: 120))
        XCTAssertEqual(evidence.scans.scans, 2)
        XCTAssertEqual(evidence.scans.reasons, [.noTeamsApp: 1])
        XCTAssertEqual(TeamsSpeakerEvidence.empty.scans, .empty)
    }

    func testStopLineHasCountsAndTimesButNoName() {
        let summary = TeamsScanSummary([
            scan(0, .named(ada), took: 0.010, nodes: 40),
            scan(1, .unnamed(.axError(-25204)), took: 0.150, nodes: 498),
            scan(2, .unnamed(.noMeetingWindow), took: 0.020, nodes: 12),
            scan(3, .unnamed(.noMeetingWindow), took: 0.030, nodes: 12)
        ])
        XCTAssertEqual(summary.stopLine.text,
                       "Teams speaker names at Stop. Scans: 4, named: 1. Reasons: noMeetingWindow 2, axError(-25204) 1. "
                       + "Scan time: median 0.025 s, longest 0.150 s. Largest node count: 498.")
        XCTAssertEqual(TeamsScanSummary.empty.stopLine.text,
                       "Teams speaker names at Stop. Scans: 0, named: 0. Reasons: none. "
                       + "Scan time: median 0.000 s, longest 0.000 s. Largest node count: 0.")
    }

    func testMergeLineCountsRemoteLinesOnlyWhenTheFeatureScanned() {
        XCTAssertEqual(summary([.named(ada)]).mergeLine(for: lines(remote: 3, named: 1))?.text,
                       "Teams speaker names: 1 of 3 remote lines named.")
        XCTAssertNil(TeamsScanSummary.empty.mergeLine(for: lines(remote: 3)))
    }

    func testChangeLinesGoOutAtMostOnceEveryTwoSeconds() {
        var tally = TeamsScanTally()
        let steps: [(Double, TeamsScanResult, String?)] = [
            (0.0, .unnamed(.noMeetingWindow), "Teams scan result: noMeetingWindow (first scan)."),
            (0.3, .unnamed(.noMeetingWindow), nil),
            (2.5, .named(ada), "Teams scan result: noMeetingWindow → named."),
            (2.8, .unnamed(.noHighlightedTile), nil),
            (3.1, .named(ada), nil),
            (3.4, .unnamed(.noHighlightedTile), nil),
            (4.5, .unnamed(.noHighlightedTile), "Teams scan result: noHighlightedTile, after 3 changes since the last line."),
            (4.8, .unnamed(.noHighlightedTile), nil),
            (5.0, .named(ada), nil),
            (7.0, .named(ada), "Teams scan result: noHighlightedTile → named.")
        ]
        for (time, result, expected) in steps {
            XCTAssertEqual(tally.line(for: scan(time, result))?.text, expected, "at \(time) s")
        }
    }

    func testNoteIsWrittenOnlyWhenScansRanRemoteLinesExistAndNoneIsNamed() {
        let scanned = summary([.unnamed(.noMeetingWindow)])
        XCTAssertNotNil(scanned.transcriptNote(for: lines(remote: 2)))
        XCTAssertNil(TeamsScanSummary.empty.transcriptNote(for: lines(remote: 2)))
        XCTAssertNil(scanned.transcriptNote(for: lines(remote: 0)))
        XCTAssertNil(scanned.transcriptNote(for: lines(remote: 2, named: 1)))
    }

    func testNoteSaysHowOftenTeamsShowedANameWhenNoLineGotOne() {
        let note = summary([.named(ada), .unnamed(.noMeetingWindow), .unnamed(.noMeetingWindow), .unnamed(.deadline)])
            .transcriptNote(for: lines(remote: 2))
        XCTAssertEqual(note, "Teams speaker names were on, but no remote line got a name. "
                       + "In 1 of 4 scans, Teams showed a name, but no remote line had enough matching evidence.")
    }

    func testNoteNamesTheMostCommonReasonBeforeTheNormalSilentResult() {
        let note = summary([.unnamed(.noHighlightedTile), .unnamed(.noHighlightedTile), .unnamed(.noMeetingWindow)])
            .transcriptNote(for: lines(remote: 1))
        XCTAssertEqual(note, "Teams speaker names were on, but no remote line got a name. "
                       + "In 1 of 3 scans, no Teams window showed meeting controls with Hang up or Leave.")
        XCTAssertEqual(summary([.unnamed(.noHighlightedTile)]).transcriptNote(for: lines(remote: 1)),
                       "Teams speaker names were on, but no remote line got a name. "
                       + "In 1 of 1 scans, no video tile had a speaking border.")
    }

    func testEqualCountsGoToTheReasonThatComesFirstInTheTable() {
        let note = summary([.unnamed(.deadline), .unnamed(.scanLimit), .unnamed(.deadline), .unnamed(.scanLimit)])
            .transcriptNote(for: lines(remote: 1))
        XCTAssertEqual(note, "Teams speaker names were on, but no remote line got a name. "
                       + "In 2 of 4 scans, the Teams windows had more elements or text than one scan reads.")
    }

    /// A dictionary's hash seed comes from its storage address, so the summaries all stay alive
    /// to give each one its own iteration order.
    func testEqualCountsOfTwoAXErrorsGiveTheSameTextEveryTime() {
        let summaries = (0..<20).map { _ in summary([.unnamed(.axError(-25204)), .unnamed(.axError(-25200))]) }
        for summary in summaries {
            XCTAssertEqual(summary.stopLine.text,
                           "Teams speaker names at Stop. Scans: 2, named: 0. "
                           + "Reasons: axError(-25200) 1, axError(-25204) 1. "
                           + "Scan time: median 0.010 s, longest 0.010 s. Largest node count: 5.")
            XCTAssertEqual(summary.transcriptNote(for: lines(remote: 1)),
                           "Teams speaker names were on, but no remote line got a name. "
                           + "In 1 of 2 scans, an Accessibility call failed with error -25200.")
        }
    }

    func testEveryReasonHasACodeAndAClause() {
        let clauses: [(TeamsScanReason, String, String)] = [
            (.notTrusted, "notTrusted", "Ku-Ka had no Accessibility permission"),
            (.noTeamsApp, "noTeamsApp", "the Teams app was not running"),
            (.noMeetingWindow, "noMeetingWindow", "no Teams window showed meeting controls with Hang up or Leave"),
            (.multipleMeetingWindows, "multipleMeetingWindows", "more than one Teams window showed meeting controls"),
            (.noHighlightedTile, "noHighlightedTile", "no video tile had a speaking border"),
            (.multipleHighlightedTiles, "multipleHighlightedTiles", "more than one video tile had a speaking border"),
            (.unsupportedTile, "unsupportedTile", "the highlighted tile did not have the supported structure"),
            (.selfTile, "selfTile", "the highlighted tile was your own video"),
            (.nameRejected, "nameRejected", "the name text of the tile was not a usable name"),
            (.scanLimit, "scanLimit", "the Teams windows had more elements or text than one scan reads"),
            (.deadline, "deadline", "the scan took longer than 150 ms"),
            (.axError(-25204), "axError(-25204)", "an Accessibility call failed with error -25204"),
            (.unexpectedAXValue, "unexpectedAXValue", "Teams returned unexpected Accessibility data")
        ]
        for (reason, code, clause) in clauses {
            XCTAssertEqual(reason.code, code)
            XCTAssertEqual(reason.clause, clause)
        }
        XCTAssertEqual(TeamsScanResult.named(ada).code, "named")
    }
}
