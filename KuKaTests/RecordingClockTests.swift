import XCTest
@testable import KuKa

final class RecordingClockTests: XCTestCase {
    func testRecordedTimeGrowsFromTheOriginAndLeavesOutAClosedPause() {
        var clock = RecordingClock(origin: HostTime(seconds: 100))
        XCTAssertEqual(clock.recordedTime(at: HostTime(seconds: 130)), 30)

        clock.pause(at: HostTime(seconds: 160))
        clock.resume(at: HostTime(seconds: 190))

        XCTAssertEqual(clock.recordedTime(at: HostTime(seconds: 200)), 70)
    }

    func testRecordedTimeDoesNotMoveWhilePaused() {
        var clock = RecordingClock(origin: HostTime(seconds: 100))
        clock.pause(at: HostTime(seconds: 160))

        XCTAssertEqual(clock.recordedTime(at: HostTime(seconds: 170)), 60)
        XCTAssertEqual(clock.recordedTime(at: HostTime(seconds: 500)), 60)
    }

    func testABoundaryInTheWrongPhaseOrOutOfOrderChangesNothing() {
        var clock = RecordingClock(origin: HostTime(seconds: 100))
        XCTAssertFalse(clock.resume(at: HostTime(seconds: 110)), "resume while recording")
        XCTAssertFalse(clock.pause(at: HostTime(seconds: 100)), "pause at the origin")
        XCTAssertFalse(clock.pause(at: HostTime(seconds: 90)), "pause before the origin")
        XCTAssertEqual(clock, RecordingClock(origin: HostTime(seconds: 100)))

        XCTAssertTrue(clock.pause(at: HostTime(seconds: 160)))
        let paused = clock
        XCTAssertTrue(clock.isPaused)
        XCTAssertFalse(clock.pause(at: HostTime(seconds: 170)), "pause while paused")
        XCTAssertFalse(clock.resume(at: HostTime(seconds: 160)), "resume at the pause")
        XCTAssertFalse(clock.resume(at: HostTime(seconds: 150)), "resume before the pause")
        XCTAssertEqual(clock, paused)

        XCTAssertTrue(clock.resume(at: HostTime(seconds: 190)))
        let resumed = clock
        XCTAssertFalse(clock.isPaused)
        XCTAssertFalse(clock.resume(at: HostTime(seconds: 200)), "resume while recording")
        XCTAssertFalse(clock.pause(at: HostTime(seconds: 180)), "pause before the resume")
        XCTAssertEqual(clock, resumed)
    }

    func testABufferBeforeAnyPauseIsKeptWholeInTheFirstRun() {
        let clock = RecordingClock(origin: HostTime(seconds: 100))

        let cut = clock.cut(start: HostTime(seconds: 110), frameCount: 960, sampleRate: 48_000)

        XCTAssertEqual(cut.pieces.map(\.frames), [0..<960])
        XCTAssertEqual(cut.pieces.map(\.run), [0])
        XCTAssertEqual(cut.pieces.map(\.filePosition), [10])
        XCTAssertFalse(cut.endsInPause)
    }

    func testABufferThatCrossesThePauseKeepsTheFramesBeforeThePauseFrame() {
        var clock = RecordingClock(origin: HostTime(seconds: 100))
        clock.pause(at: HostTime(seconds: 160))

        let cut = clock.cut(start: HostTime(seconds: 159.99), frameCount: 960, sampleRate: 48_000)

        XCTAssertEqual(cut.pieces.map(\.frames), [0..<480])
        XCTAssertEqual(cut.pieces.map(\.run), [0])
        assertFilePositions(cut, [59.99])
        XCTAssertTrue(cut.endsInPause)
    }

    func testABufferInsideAPauseKeepsNothing() {
        var clock = RecordingClock(origin: HostTime(seconds: 100))
        clock.pause(at: HostTime(seconds: 160))
        XCTAssertTrue(clock.cut(start: HostTime(seconds: 170), frameCount: 960, sampleRate: 48_000).pieces.isEmpty)
        XCTAssertTrue(clock.cut(start: HostTime(seconds: 170), frameCount: 960, sampleRate: 48_000).endsInPause)

        clock.resume(at: HostTime(seconds: 190))
        let cut = clock.cut(start: HostTime(seconds: 170), frameCount: 960, sampleRate: 48_000)

        XCTAssertTrue(cut.pieces.isEmpty)
        XCTAssertTrue(cut.endsInPause)
    }

    func testABufferThatCrossesTheResumeKeepsTheFramesFromTheResumeFrame() {
        var clock = RecordingClock(origin: HostTime(seconds: 100))
        clock.pause(at: HostTime(seconds: 160))
        clock.resume(at: HostTime(seconds: 190))

        let cut = clock.cut(start: HostTime(seconds: 189.99), frameCount: 960, sampleRate: 48_000)

        XCTAssertEqual(cut.pieces.map(\.frames), [480..<960])
        XCTAssertEqual(cut.pieces.map(\.run), [1])
        assertFilePositions(cut, [63])
        XCTAssertFalse(cut.endsInPause)
    }

    func testABufferThatHoldsAWholeShortPauseGivesOnePiecePerRun() {
        var clock = RecordingClock(origin: HostTime(seconds: 100))
        clock.pause(at: HostTime(seconds: 160.005))
        clock.resume(at: HostTime(seconds: 160.01))

        let cut = clock.cut(start: HostTime(seconds: 160), frameCount: 960, sampleRate: 48_000)

        XCTAssertEqual(cut.pieces.map(\.frames), [0..<240, 480..<960])
        XCTAssertEqual(cut.pieces.map(\.run), [0, 1])
        assertFilePositions(cut, [60, 63.005])
        XCTAssertFalse(cut.endsInPause)
    }

    func testTracksAtDifferentSampleRatesAreCutAtTheSameHostTime() throws {
        let pause = HostTime(seconds: 160.00123)
        var clock = RecordingClock(origin: HostTime(seconds: 100))
        clock.pause(at: pause)
        let start = HostTime(seconds: 159.99)

        for (frameCount, sampleRate) in [(960, 48_000.0), (480, 24_000.0)] {
            let cut = clock.cut(start: start, frameCount: frameCount, sampleRate: sampleRate)
            let keptFrames = try XCTUnwrap(cut.pieces.first).frames
            XCTAssertEqual(keptFrames.lowerBound, 0)
            let cutTime = start + Double(keptFrames.upperBound) / sampleRate
            XCTAssertEqual(cutTime.seconds, pause.seconds, accuracy: 0.5 / sampleRate, "\(sampleRate) Hz")
        }
    }

    func testFramesBeforeTheOriginAreNotKept() {
        let clock = RecordingClock(origin: HostTime(seconds: 100))

        let crossing = clock.cut(start: HostTime(seconds: 99.99), frameCount: 960, sampleRate: 48_000)
        let before = clock.cut(start: HostTime(seconds: 99), frameCount: 960, sampleRate: 48_000)

        XCTAssertEqual(crossing.pieces.map(\.frames), [480..<960])
        XCTAssertEqual(crossing.pieces.map(\.run), [0])
        assertFilePositions(crossing, [0])
        XCTAssertTrue(before.pieces.isEmpty)
    }

    func testEachResumeAddsTheGapToTheFilePositionAndMapsBack() throws {
        var clock = RecordingClock(origin: HostTime(seconds: 100))
        clock.pause(at: HostTime(seconds: 160))
        clock.resume(at: HostTime(seconds: 190))
        clock.pause(at: HostTime(seconds: 200))
        clock.resume(at: HostTime(seconds: 300))

        XCTAssertEqual(clock.filePosition(at: HostTime(seconds: 150)), 50)
        XCTAssertNil(clock.filePosition(at: HostTime(seconds: 170)), "inside the first pause")
        XCTAssertEqual(clock.filePosition(at: HostTime(seconds: 195)), 68)
        XCTAssertNil(clock.filePosition(at: HostTime(seconds: 99)), "before the origin")
        let afterTwoResumes = try XCTUnwrap(clock.filePosition(at: HostTime(seconds: 310)))
        XCTAssertEqual(afterTwoResumes, clock.recordedTime(at: HostTime(seconds: 310)) + 6)

        XCTAssertEqual(clock.recordedTime(atFilePosition: 50), 50)
        XCTAssertEqual(clock.recordedTime(atFilePosition: 68), 65)
        XCTAssertEqual(clock.recordedTime(atFilePosition: afterTwoResumes), 80)
        XCTAssertEqual(clock.recordedTime(atFilePosition: 61.5), 60, "inside the first gap")
        XCTAssertEqual(clock.recordedTime(atFilePosition: 73), 70, "the first gap ends at 63, the second starts at 73")
        XCTAssertEqual(clock.recordedTime(atFilePosition: 75.9), 70, "inside the second gap")
        XCTAssertEqual(clock.recordedTime(atFilePosition: 76), 70, "the end of the second gap is the resume")
    }

    func testPausesListEachPauseAtItsRecordedTimeWithNoDurationWhileItLasts() {
        var clock = RecordingClock(origin: HostTime(seconds: 100))
        XCTAssertTrue(clock.pauses.isEmpty)

        clock.pause(at: HostTime(seconds: 160))
        clock.resume(at: HostTime(seconds: 190))
        clock.pause(at: HostTime(seconds: 200))

        XCTAssertEqual(clock.pauses.map(\.at), [60, 70])
        XCTAssertEqual(clock.pauses.map(\.duration), [30, nil])

        clock.resume(at: HostTime(seconds: 245))
        XCTAssertEqual(clock.pauses.map(\.duration), [30, 45])
    }

    func testRecordedTimeShowsHoursOnlyWhenNeeded() {
        XCTAssertEqual(RecordedTime.format(0), "0:00")
        XCTAssertEqual(RecordedTime.format(245), "4:05")
        XCTAssertEqual(RecordedTime.format(3729), "1:02:09")
    }

    private func assertFilePositions(_ cut: BufferCut, _ expected: [TimeInterval],
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(cut.pieces.count, expected.count, "pieces", file: file, line: line)
        for (piece, position) in zip(cut.pieces, expected) {
            XCTAssertEqual(piece.filePosition, position, accuracy: 1e-9, file: file, line: line)
        }
    }
}
