import XCTest
@testable import KuKa

final class RoomVoicesTests: XCTestCase {
    private func turn(_ voice: Int, _ start: TimeInterval, _ end: TimeInterval) -> VoiceTurn {
        VoiceTurn(voice: voice, start: start, end: end)
    }

    private func voice(_ start: TimeInterval, _ end: TimeInterval, in turns: [VoiceTurn]) throws -> Int {
        let voices = try XCTUnwrap(RoomVoices(turns))
        return voices.voice(for: TranscriptSegment(start: start, end: end, text: "Sounds good"))
    }

    func testASegmentGetsTheVoiceWithTheMostOverlappingTime() throws {
        XCTAssertEqual(try voice(3, 9, in: [turn(7, 0, 4), turn(3, 4, 10)]), 3)
    }

    func testASegmentThatSpansTwoVoicesGoesWholeToTheLargerShare() throws {
        XCTAssertEqual(try voice(1, 5, in: [turn(1, 0, 3.2), turn(2, 3.2, 6)]), 1)
    }

    func testTimeIsSummedOverEveryTurnOfOneVoice() throws {
        XCTAssertEqual(try voice(0, 3.6, in: [turn(1, 0, 0.8), turn(1, 1.6, 2.4), turn(2, 2.4, 3.6)]), 1)
    }

    func testEqualTimeGoesToTheVoiceWhoseTurnStartsFirst() throws {
        XCTAssertEqual(try voice(1, 3, in: [turn(2, 2, 4), turn(8, 0, 2)]), 8)
        XCTAssertEqual(try voice(1, 3, in: [turn(8, 2, 4), turn(2, 0, 2)]), 2)
    }

    func testASegmentOutsideEveryTurnGetsTheNearestTurnsVoice() throws {
        let turns = [turn(4, 10, 12), turn(3, 20, 22)]

        XCTAssertEqual(try voice(2, 4, in: turns), 4, "before the first turn")
        XCTAssertEqual(try voice(17, 18, in: turns), 3, "in the gap, nearer the later turn")
        XCTAssertEqual(try voice(30, 31, in: turns), 3, "after the last turn")
        XCTAssertEqual(try voice(14, 18, in: turns), 4, "equal gaps go to the earlier turn")
    }

    func testTurnsInAnyOrderGiveTheSameVoice() throws {
        let inTime = [turn(5, 0, 2), turn(6, 2, 3), turn(5, 3, 3.5), turn(6, 3.5, 6), turn(5, 9, 10), turn(6, 12, 13)]
        let bySpeaker = inTime.filter { $0.voice == 6 } + inTime.filter { $0.voice == 5 }
        let segments: [(TimeInterval, TimeInterval)] = [(0, 2.6), (1.5, 3.5), (2.5, 4), (3, 3.5), (7, 8), (10.5, 11.5), (14, 15)]

        for (start, end) in segments {
            let expected = try voice(start, end, in: inTime)
            XCTAssertEqual(try voice(start, end, in: bySpeaker), expected, "\(start) to \(end) s")
            XCTAssertEqual(try voice(start, end, in: inTime.reversed()), expected, "\(start) to \(end) s")
        }
    }

    func testNoRoomVoicesWithoutATurnLongerThanZero() {
        XCTAssertNil(RoomVoices([]))
        XCTAssertNil(RoomVoices([turn(1, 2, 2)]))
        XCTAssertNil(RoomVoices([turn(1, 3, 2)]))
    }

    /// Times are multiples of 0.25 s, so sums are exact and equal shares and equal gaps really tie.
    func testManyTurnsGiveTheSameVoicesAsCheckingEveryTurn() throws {
        var random = SeededRandom(seed: 42)
        var turns: [VoiceTurn] = []
        var start: TimeInterval = 0
        for _ in 0..<600 {
            start += [0.25, 0.5, 1, 1.5, 3].randomElement(using: &random)!
            let length = [0.25, 0.5, 1, 2, 4, 8].randomElement(using: &random)!
            turns.append(turn(Int.random(in: 0..<4, using: &random), start, start + length))
        }
        let voices = try XCTUnwrap(RoomVoices(turns.shuffled(using: &random)))

        for _ in 0..<2_000 {
            let start = TimeInterval(Int.random(in: -20...(Int(start) + 20) * 4, using: &random)) / 4
            let length = [0, 0.25, 0.5, 1, 3, 6].randomElement(using: &random)!
            let segment = TranscriptSegment(start: start, end: start + length, text: "Sounds good")
            XCTAssertEqual(voices.voice(for: segment), referenceVoice(for: segment, in: turns), "\(start) to \(start + length) s")
        }
    }

    /// The rule written plainly: every turn is checked for every segment.
    private func referenceVoice(for segment: TranscriptSegment, in turns: [VoiceTurn]) -> Int {
        let turns = turns.sorted { $0.start < $1.start }
        var shares: [(voice: Int, time: TimeInterval)] = []
        for turn in turns {
            let shared = min(turn.end, segment.end) - max(turn.start, segment.start)
            guard shared > 0 else { continue }
            if let index = shares.firstIndex(where: { $0.voice == turn.voice }) {
                shares[index].time += shared
            } else {
                shares.append((turn.voice, shared))
            }
        }
        if let most = shares.map(\.time).max() {
            return shares.first { $0.time == most }!.voice
        }
        func gap(_ turn: VoiceTurn) -> TimeInterval { max(turn.start - segment.end, segment.start - turn.end, 0) }
        return turns.min { (gap($0), $0.start) < (gap($1), $1.start) }!.voice
    }
}

/// SplitMix64, so the test draws the same turns on every run.
private struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
