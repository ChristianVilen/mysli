import XCTest
@testable import KuKa

final class TilingLayoutEngineTests: XCTestCase {
    private let engine = TilingLayoutEngine()

    // A non-trivial visible frame with origin != (0,0), mimicking a secondary
    // screen positioned to the right of a primary display. Catches bugs that
    // assume minX/minY are zero.
    private let screen = CGRect(x: 1920, y: 25, width: 1600, height: 975)

    // A second screen's visible frame, sitting to the left of `screen`,
    // mimicking a primary laptop display next to an external monitor.
    private let otherScreen = CGRect(x: 0, y: 0, width: 1920, height: 955)

    private func makeContext(
        windows: Int,
        stageManager: Bool,
        visibleFrame: CGRect? = nil,
        adjacentVisibleFrame: CGRect? = nil
    ) -> TilingContext {
        TilingContext(
            visibleFrame: visibleFrame ?? screen,
            windowCount: windows,
            stageManagerEnabled: stageManager,
            adjacentVisibleFrame: adjacentVisibleFrame
        )
    }

    // MARK: - Left / right half math

    func testLeftHalfMath() {
        let frame = TilingLayoutEngine.halfFrame(.left, of: screen)
        XCTAssertEqual(frame, CGRect(x: 1920, y: 25, width: 800, height: 975))
    }

    func testRightHalfMath() {
        let frame = TilingLayoutEngine.halfFrame(.right, of: screen)
        XCTAssertEqual(frame, CGRect(x: 2720, y: 25, width: 800, height: 975))
    }

    func testHalvesOnOddWidthScreenLandOnHalfPoints() {
        let oddScreen = CGRect(x: 0, y: 0, width: 1511, height: 982)

        let left = TilingLayoutEngine.halfFrame(.left, of: oddScreen)
        let right = TilingLayoutEngine.halfFrame(.right, of: oddScreen)

        XCTAssertEqual(left, CGRect(x: 0, y: 0, width: 755.5, height: 982))
        XCTAssertEqual(right, CGRect(x: 755.5, y: 0, width: 755.5, height: 982))
    }

    // MARK: - Maximize math

    func testMaximizeStageLayoutExactMathWhenStageManagerOnWithMultipleWindows() {
        let context = makeContext(windows: 2, stageManager: true)
        let frame = engine.maximizeFrame(in: context)

        // Hand-computed from screen = (x:1920, y:25, w:1600, h:975) and the
        // two insets (left 7% of width; 1% of height at top, bottom, right):
        // leftInset = 0.07*1600 = 112 -> x = 1920 + 112 = 2032
        // edgeInset = 0.01*975 = 9.75
        // width = 1600 - 112 - 9.75 = 1478.25
        // y = 25 + 9.75 = 34.75
        // height = 975 - 2*9.75 = 955.5
        XCTAssertEqual(frame.origin.x, 2032, accuracy: 0.0001)
        XCTAssertEqual(frame.origin.y, 34.75, accuracy: 0.0001)
        XCTAssertEqual(frame.width, 1478.25, accuracy: 0.0001)
        XCTAssertEqual(frame.height, 955.5, accuracy: 0.0001)
    }

    func testMaximizeStageLayoutStaysInsideVisibleFrameWithEqualTopBottomAndRightGaps() {
        let context = makeContext(windows: 2, stageManager: true)
        let frame = engine.maximizeFrame(in: context)

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
        XCTAssertEqual(engine.maximizeFrame(in: context), screen)
    }

    func testMaximizeFillsScreenWhenStageManagerOffEvenWithManyWindows() {
        let context = makeContext(windows: 5, stageManager: false)
        XCTAssertEqual(engine.maximizeFrame(in: context), screen)
    }

    func testMaximizeFillsScreenWhenWindowCountIsZero() {
        let context = makeContext(windows: 0, stageManager: true)
        XCTAssertEqual(engine.maximizeFrame(in: context), screen)
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

    // MARK: - resolve() screen hop (second half-press moves to the adjacent screen)

    func testResolveLeftHalfWhenAlreadyAtLeftHalfMovesToLeftHalfOfAdjacentScreen() {
        let context = makeContext(windows: 2, stageManager: false, adjacentVisibleFrame: otherScreen)
        // The window is already sitting at this screen's left-half target.
        let current = CGRect(x: 1920, y: 25, width: 800, height: 975)

        let result = engine.resolve(action: .leftHalf, currentFrame: current, restoreState: nil, context: context)

        XCTAssertEqual(result, .move(to: CGRect(x: 0, y: 0, width: 960, height: 955), savePrevious: false))
    }

    func testResolveRightHalfWhenAlreadyAtRightHalfMovesToRightHalfOfAdjacentScreen() {
        let context = makeContext(windows: 2, stageManager: false, adjacentVisibleFrame: otherScreen)
        let current = CGRect(x: 2720, y: 25, width: 800, height: 975)

        let result = engine.resolve(action: .rightHalf, currentFrame: current, restoreState: nil, context: context)

        XCTAssertEqual(result, .move(to: CGRect(x: 960, y: 0, width: 960, height: 955), savePrevious: false))
    }

    func testResolveLeftHalfWithinToleranceOfTargetStillHops() {
        let context = makeContext(windows: 2, stageManager: false, adjacentVisibleFrame: otherScreen)
        // Off the exact target by up to 2pt on every component — the same
        // tolerance the maximize toggle uses, for apps that don't land
        // exactly where asked.
        let current = CGRect(x: 1921, y: 24, width: 802, height: 973)

        let result = engine.resolve(action: .leftHalf, currentFrame: current, restoreState: nil, context: context)

        XCTAssertEqual(result, .move(to: CGRect(x: 0, y: 0, width: 960, height: 955), savePrevious: false))
    }

    func testResolveLeftHalfJustOverToleranceTilesOnThisScreenEvenWithAdjacentScreen() {
        let context = makeContext(windows: 2, stageManager: false, adjacentVisibleFrame: otherScreen)
        let current = CGRect(x: 1920 + 2.1, y: 25, width: 800, height: 975)

        let result = engine.resolve(action: .leftHalf, currentFrame: current, restoreState: nil, context: context)

        XCTAssertEqual(result, .move(to: CGRect(x: 1920, y: 25, width: 800, height: 975), savePrevious: false))
    }

    func testResolveLeftHalfWhenAlreadyAtLeftHalfWithoutAdjacentScreenReappliesSameTarget() {
        // Single-screen setup: no adjacent screen to hop to, so the second
        // press just re-applies the same half.
        let context = makeContext(windows: 2, stageManager: false)
        let current = CGRect(x: 1920, y: 25, width: 800, height: 975)

        let result = engine.resolve(action: .leftHalf, currentFrame: current, restoreState: nil, context: context)

        XCTAssertEqual(result, .move(to: current, savePrevious: false))
    }

    // MARK: - resolve() center

    func testResolveCenterCentersWindowKeepingItsSize() {
        let context = makeContext(windows: 1, stageManager: false)
        let current = CGRect(x: 2000, y: 100, width: 400, height: 300)

        let result = engine.resolve(action: .center, currentFrame: current, restoreState: nil, context: context)

        // screen = (x:1920, y:25, w:1600, h:975) -> midX 2720, midY 512.5
        XCTAssertEqual(result, .move(to: CGRect(x: 2520, y: 362.5, width: 400, height: 300), savePrevious: false))
    }

    func testResolveCenterAtMaximizeSizeDoesNothing() {
        let context = makeContext(windows: 1, stageManager: false)
        // Max size but sitting off-center: the size check alone decides.
        let current = CGRect(x: 100, y: 100, width: screen.width, height: screen.height)

        let result = engine.resolve(action: .center, currentFrame: current, restoreState: nil, context: context)

        XCTAssertNil(result)
    }

    func testResolveCenterWithinToleranceOfMaximizeSizeDoesNothing() {
        let context = makeContext(windows: 1, stageManager: false)
        let current = CGRect(x: 2000, y: 100, width: screen.width - 2, height: screen.height + 1.5)

        let result = engine.resolve(action: .center, currentFrame: current, restoreState: nil, context: context)

        XCTAssertNil(result)
    }

    func testResolveCenterJustOverToleranceFromMaximizeSizeStillCenters() {
        let context = makeContext(windows: 1, stageManager: false)
        let current = CGRect(x: 2000, y: 100, width: screen.width - 2.1, height: screen.height - 2.1)

        let result = engine.resolve(action: .center, currentFrame: current, restoreState: nil, context: context)

        XCTAssertEqual(
            result,
            .move(
                to: CGRect(
                    x: screen.midX - current.width / 2,
                    y: screen.midY - current.height / 2,
                    width: current.width,
                    height: current.height
                ),
                savePrevious: false
            )
        )
    }

    func testResolveCenterComparesAgainstStageManagerMaximizeSizeWhenStageStripTakesSpace() {
        let context = makeContext(windows: 2, stageManager: true)
        // The Stage Manager maximize target is inset, so "max size" is the
        // inset size, not the full visible frame. A window at that inset
        // size should read as maximized and stay put.
        let stageMax = engine.maximizeFrame(in: context)
        let current = CGRect(x: 100, y: 100, width: stageMax.width, height: stageMax.height)

        let result = engine.resolve(action: .center, currentFrame: current, restoreState: nil, context: context)

        XCTAssertNil(result)
    }

    func testResolveCenterAtFullVisibleFrameSizeCentersWhenStageStripTakesSpace() {
        let context = makeContext(windows: 2, stageManager: true)
        // With the strip taking space, the full visible frame is NOT the
        // maximize size, so a window that big still gets centered.
        let current = CGRect(x: 100, y: 100, width: screen.width, height: screen.height)

        let result = engine.resolve(action: .center, currentFrame: current, restoreState: nil, context: context)

        XCTAssertEqual(
            result,
            .move(
                to: CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: screen.height),
                savePrevious: false
            )
        )
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
