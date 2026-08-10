import XCTest
@testable import KuKa

final class TilingLayoutEngineTests: XCTestCase {
    private let engine = TilingLayoutEngine()

    // A non-trivial visible frame with origin != (0,0), mimicking a secondary
    // screen positioned to the right of a primary display. Catches bugs that
    // assume minX/minY are zero.
    private let screen = CGRect(x: 1920, y: 25, width: 1600, height: 975)

    private func makeContext(windows: Int, stageManager: Bool, visibleFrame: CGRect? = nil) -> TilingContext {
        TilingContext(
            visibleFrame: visibleFrame ?? screen,
            windowCount: windows,
            stageManagerEnabled: stageManager
        )
    }

    // MARK: - Left / right half math

    func testLeftHalfMath() {
        let context = makeContext(windows: 1, stageManager: false)
        let frame = engine.targetFrame(for: .leftHalf, in: context)
        XCTAssertEqual(frame, CGRect(x: 1920, y: 25, width: 800, height: 975))
    }

    func testRightHalfMath() {
        let context = makeContext(windows: 1, stageManager: false)
        let frame = engine.targetFrame(for: .rightHalf, in: context)
        XCTAssertEqual(frame, CGRect(x: 2720, y: 25, width: 800, height: 975))
    }

    func testHalvesOnOddWidthScreenLandOnHalfPoints() {
        let oddScreen = CGRect(x: 0, y: 0, width: 1511, height: 982)
        let context = makeContext(windows: 1, stageManager: false, visibleFrame: oddScreen)

        let left = engine.targetFrame(for: .leftHalf, in: context)
        let right = engine.targetFrame(for: .rightHalf, in: context)

        XCTAssertEqual(left, CGRect(x: 0, y: 0, width: 755.5, height: 982))
        XCTAssertEqual(right, CGRect(x: 755.5, y: 0, width: 755.5, height: 982))
    }

    func testLeftHalfIgnoresStageManagerAndWindowCount() {
        let smOff = makeContext(windows: 1, stageManager: false)
        let smOn = makeContext(windows: 3, stageManager: true)
        XCTAssertEqual(
            engine.targetFrame(for: .leftHalf, in: smOff),
            engine.targetFrame(for: .leftHalf, in: smOn)
        )
    }

    func testRightHalfIgnoresStageManagerAndWindowCount() {
        let smOff = makeContext(windows: 1, stageManager: false)
        let smOn = makeContext(windows: 3, stageManager: true)
        XCTAssertEqual(
            engine.targetFrame(for: .rightHalf, in: smOff),
            engine.targetFrame(for: .rightHalf, in: smOn)
        )
    }

    // MARK: - Maximize math

    func testMaximizeStageLayoutExactMathWhenStageManagerOnWithMultipleWindows() {
        let context = makeContext(windows: 2, stageManager: true)
        let frame = engine.targetFrame(for: .maximize, in: context)

        // Hand-computed from screen = (x:1920, y:25, w:1600, h:975) and the
        // two insets (left 7% of width; 2% of height at top, bottom, right):
        // leftInset = 0.07*1600 = 112 -> x = 1920 + 112 = 2032
        // edgeInset = 0.02*975 = 19.5
        // width = 1600 - 112 - 19.5 = 1468.5
        // y = 25 + 19.5 = 44.5
        // height = 975 - 2*19.5 = 936
        XCTAssertEqual(frame.origin.x, 2032, accuracy: 0.0001)
        XCTAssertEqual(frame.origin.y, 44.5, accuracy: 0.0001)
        XCTAssertEqual(frame.width, 1468.5, accuracy: 0.0001)
        XCTAssertEqual(frame.height, 936, accuracy: 0.0001)
    }

    func testMaximizeStageLayoutStaysInsideVisibleFrameWithEqualTopBottomAndRightGaps() {
        let context = makeContext(windows: 2, stageManager: true)
        let frame = engine.targetFrame(for: .maximize, in: context)

        XCTAssertGreaterThanOrEqual(frame.minX, screen.minX)
        // Exact maxX is pinned by testMaximizeStageLayoutExactMathWhenStageManagerOnWithMultipleWindows;
        // this test only needs containment.
        XCTAssertLessThanOrEqual(frame.maxX, screen.maxX)
        XCTAssertGreaterThanOrEqual(frame.minY, screen.minY)
        XCTAssertLessThanOrEqual(frame.maxY, screen.maxY)

        let topGap = screen.maxY - frame.maxY
        let bottomGap = frame.minY - screen.minY
        let rightGap = screen.maxX - frame.maxX
        XCTAssertEqual(topGap, bottomGap, accuracy: 0.0001)
        XCTAssertEqual(rightGap, topGap, accuracy: 0.0001)
    }

    func testMaximizeFillsScreenWhenOnlyOneWindowEvenWithStageManagerOn() {
        let context = makeContext(windows: 1, stageManager: true)
        XCTAssertEqual(engine.targetFrame(for: .maximize, in: context), screen)
    }

    func testMaximizeFillsScreenWhenStageManagerOffEvenWithManyWindows() {
        let context = makeContext(windows: 5, stageManager: false)
        XCTAssertEqual(engine.targetFrame(for: .maximize, in: context), screen)
    }

    func testMaximizeFillsScreenWhenWindowCountIsZero() {
        let context = makeContext(windows: 0, stageManager: true)
        XCTAssertEqual(engine.targetFrame(for: .maximize, in: context), screen)
    }

    // MARK: - resolve()

    func testResolveLeftHalfMovesWithoutSaving() {
        let context = makeContext(windows: 2, stageManager: false)
        let current = CGRect(x: 0, y: 0, width: 100, height: 100)

        let result = engine.resolve(action: .leftHalf, currentFrame: current, restoreState: nil, context: context)

        XCTAssertEqual(result, .move(to: CGRect(x: 1920, y: 25, width: 800, height: 975), savePrevious: false))
    }

    func testResolveRightHalfMovesWithoutSaving() {
        let context = makeContext(windows: 2, stageManager: false)
        let current = CGRect(x: 0, y: 0, width: 100, height: 100)

        let result = engine.resolve(
            action: .rightHalf,
            currentFrame: current,
            restoreState: TilingRestoreState(
                previousFrame: CGRect(x: 1, y: 1, width: 1, height: 1),
                achievedFrame: current
            ),
            context: context
        )

        XCTAssertEqual(result, .move(to: CGRect(x: 2720, y: 25, width: 800, height: 975), savePrevious: false))
    }

    func testResolveMaximizeFromRandomFrameMovesAndSaves() {
        let context = makeContext(windows: 1, stageManager: false)
        let current = CGRect(x: 100, y: 100, width: 300, height: 300)

        let result = engine.resolve(action: .maximize, currentFrame: current, restoreState: nil, context: context)

        XCTAssertEqual(result, .move(to: screen, savePrevious: true))
    }

    func testResolveMaximizeWithinToleranceAndSavedFrameRestores() {
        let context = makeContext(windows: 1, stageManager: false)
        let target = screen
        let current = CGRect(
            x: target.minX + 1,
            y: target.minY - 1,
            width: target.width + 1.5,
            height: target.height - 1.5
        )
        let saved = CGRect(x: 500, y: 500, width: 400, height: 400)

        let result = engine.resolve(
            action: .maximize,
            currentFrame: current,
            restoreState: TilingRestoreState(previousFrame: saved, achievedFrame: target),
            context: context
        )

        XCTAssertEqual(result, .restore(to: saved))
    }

    func testResolveMaximizeWithinToleranceButNoRestoreStateReappliesAndSaves() {
        let context = makeContext(windows: 1, stageManager: false)
        let target = screen
        let current = CGRect(x: target.minX + 1, y: target.minY, width: target.width, height: target.height)

        let result = engine.resolve(action: .maximize, currentFrame: current, restoreState: nil, context: context)

        XCTAssertEqual(result, .move(to: target, savePrevious: true))
    }

    func testResolveMaximizeToleranceEdgeExactlyTwoPointsStillRestores() {
        let context = makeContext(windows: 1, stageManager: false)
        let target = screen
        let current = CGRect(x: target.minX + 2.0, y: target.minY, width: target.width, height: target.height)
        let saved = CGRect(x: 10, y: 10, width: 10, height: 10)

        let result = engine.resolve(
            action: .maximize,
            currentFrame: current,
            restoreState: TilingRestoreState(previousFrame: saved, achievedFrame: target),
            context: context
        )

        XCTAssertEqual(result, .restore(to: saved))
    }

    func testResolveMaximizeToleranceEdgeJustOverTwoPointsMovesInstead() {
        let context = makeContext(windows: 1, stageManager: false)
        let target = screen
        let current = CGRect(x: target.minX + 2.1, y: target.minY, width: target.width, height: target.height)
        let saved = CGRect(x: 10, y: 10, width: 10, height: 10)

        let result = engine.resolve(
            action: .maximize,
            currentFrame: current,
            restoreState: TilingRestoreState(previousFrame: saved, achievedFrame: target),
            context: context
        )

        XCTAssertEqual(result, .move(to: target, savePrevious: true))
    }

    // MARK: - resolve() with a snapped achieved frame (apps that snap sizes, e.g. Terminal)

    func testResolveMaximizeWithinToleranceOfAchievedFrameButFarFromIdealTargetRestores() {
        let context = makeContext(windows: 1, stageManager: false)
        let idealTarget = screen
        // Simulate an app that snapped the requested maximize to a
        // meaningfully different frame (a character-cell grid, say) — the
        // achieved frame is nowhere near the ideal target, but it's what's
        // really on screen, and the window hasn't moved since.
        let achieved = CGRect(x: idealTarget.minX + 20, y: idealTarget.minY, width: idealTarget.width - 20, height: idealTarget.height)
        let current = achieved
        let saved = CGRect(x: 500, y: 500, width: 400, height: 400)

        let result = engine.resolve(
            action: .maximize,
            currentFrame: current,
            restoreState: TilingRestoreState(previousFrame: saved, achievedFrame: achieved),
            context: context
        )

        XCTAssertEqual(result, .restore(to: saved))
    }

    func testResolveMaximizeIgnoresIdealTargetWhenAchievedFrameDiffers() {
        let context = makeContext(windows: 1, stageManager: false)
        let idealTarget = screen
        let achieved = CGRect(x: idealTarget.minX + 50, y: idealTarget.minY, width: idealTarget.width - 50, height: idealTarget.height)
        // Current frame matches the IDEAL target exactly, not the achieved
        // frame — with an achieved frame on record, that should no longer
        // read as "already maximized".
        let current = idealTarget
        let saved = CGRect(x: 500, y: 500, width: 400, height: 400)

        let result = engine.resolve(
            action: .maximize,
            currentFrame: current,
            restoreState: TilingRestoreState(previousFrame: saved, achievedFrame: achieved),
            context: context
        )

        XCTAssertEqual(result, .move(to: idealTarget, savePrevious: true))
    }
}
