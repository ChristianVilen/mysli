import XCTest
import ApplicationServices
@testable import KuKa

@MainActor
final class WindowTilingControllerTests: XCTestCase {

    // A stable AXUIElement identity so the controller's saved-frame map sees
    // the "same window" across calls in a test, the same way it would for a
    // single real window being tiled repeatedly.
    private let handleElement = AXUIElementCreateApplication(424_242)

    override func setUpWithError() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "No screen available in this environment")
    }

    private var mainScreen: NSScreen {
        NSScreen.main ?? NSScreen.screens[0]
    }

    private func focusedWindow(frame: CGRect) -> FocusedWindow {
        FocusedWindow(element: handleElement, frame: frame)
    }

    private func makeController(_ windowControl: MockWindowControlling) -> WindowTilingController {
        WindowTilingController(
            windowControl: windowControl,
            stageManager: MockStageManagerDetecting(),
            windowList: MockWindowListProvider(),
            engine: TilingLayoutEngine()
        )
    }

    // MARK: - Save on success, restore on second press

    func testMaximizeThenSecondPressRestoresRecordedPreviousFrame() {
        let mock = MockWindowControlling()
        let controller = makeController(mock)
        let screen = mainScreen
        let idealTarget = screen.visibleFrame
        let originalFrame = CGRect(x: screen.frame.minX + 10, y: screen.frame.minY + 10, width: 300, height: 300)
        // Simulates an app that snaps the requested maximize frame to
        // something else (a character-cell grid, say) rather than landing
        // exactly on the ideal target.
        let achievedFrame = CGRect(x: screen.frame.minX + 5, y: screen.frame.minY + 5, width: 400, height: 400)

        mock.focusedWindowToReturn = focusedWindow(frame: originalFrame)
        mock.achievedFrameToReturn = achievedFrame
        controller.tile(.maximize)

        XCTAssertEqual(mock.setFrameCalls.count, 1)
        XCTAssertEqual(mock.setFrameCalls[0].frame, idealTarget)

        // Second press: the window is sitting at the achieved frame, not the
        // ideal target — exactly the case the achieved-frame comparison
        // exists for. It should read as "already maximized" and restore to
        // the ORIGINAL frame, proving both previousFrame and achievedFrame
        // were recorded correctly on the first press.
        mock.focusedWindowToReturn = focusedWindow(frame: achievedFrame)
        controller.tile(.maximize)

        XCTAssertEqual(mock.setFrameCalls.count, 2)
        XCTAssertEqual(mock.setFrameCalls[1].frame, originalFrame)
    }

    // MARK: - Failed move saves nothing

    func testFailedSetFrameDuringMaximizeSavesNothing() {
        let mock = MockWindowControlling()
        let controller = makeController(mock)
        let screen = mainScreen
        let idealTarget = screen.visibleFrame
        let originalFrame = CGRect(x: screen.frame.minX + 10, y: screen.frame.minY + 10, width: 300, height: 300)

        // setFrame fails (returns nil, as AccessibilityWindowControl does
        // when the AX call or the re-read fails).
        mock.focusedWindowToReturn = focusedWindow(frame: originalFrame)
        mock.achievedFrameToReturn = nil
        controller.tile(.maximize)

        XCTAssertEqual(mock.setFrameCalls.count, 1)

        // Second press: the window now happens to be sitting exactly at the
        // ideal target (maybe the AX move actually landed but the re-read
        // that reports the achieved frame failed, so setFrame still
        // returned nil — a plausible partial failure). This specific
        // follow-up is what discriminates the fix from the bug it replaced:
        // the pre-fix controller stored `previousFrame` unconditionally
        // whenever `savePrevious` was true, regardless of whether setFrame
        // succeeded, so it would have `originalFrame` on record here, and
        // its resolve() compared currentFrame only against the ideal
        // target (no achieved-frame concept yet) — so with currentFrame
        // now reading as "at the ideal target", the pre-fix code would
        // resolve this as a RESTORE back to `originalFrame`
        // (setFrameCalls[1].frame == originalFrame). The fix only records
        // state when setFrame actually returns an achieved frame, so
        // nothing was saved from the failed first press, and this reads as
        // a fresh maximize instead (setFrameCalls[1].frame == idealTarget).
        mock.focusedWindowToReturn = focusedWindow(frame: idealTarget)
        controller.tile(.maximize)

        XCTAssertEqual(mock.setFrameCalls.count, 2)
        XCTAssertEqual(mock.setFrameCalls[1].frame, idealTarget)
    }

    // MARK: - Restore clears the entry

    func testEntryIsRemovedAfterRestoreSoThirdPressMaximizesAgain() {
        let mock = MockWindowControlling()
        let controller = makeController(mock)
        let screen = mainScreen
        let idealTarget = screen.visibleFrame
        let originalFrame = CGRect(x: screen.frame.minX + 10, y: screen.frame.minY + 10, width: 300, height: 300)
        let achievedFrame = CGRect(x: screen.frame.minX + 5, y: screen.frame.minY + 5, width: 400, height: 400)

        mock.focusedWindowToReturn = focusedWindow(frame: originalFrame)
        mock.achievedFrameToReturn = achievedFrame
        controller.tile(.maximize) // move + save

        mock.focusedWindowToReturn = focusedWindow(frame: achievedFrame)
        controller.tile(.maximize) // restore, entry removed

        XCTAssertEqual(mock.setFrameCalls.count, 2)
        XCTAssertEqual(mock.setFrameCalls[1].frame, originalFrame)

        // Third press: the window is still sitting at achievedFrame (nothing
        // else moved it), but the entry was removed by the restore above, so
        // this has to be judged against the ideal target again, not the
        // stale achieved frame, and treated as a fresh maximize.
        mock.focusedWindowToReturn = focusedWindow(frame: achievedFrame)
        controller.tile(.maximize)

        XCTAssertEqual(mock.setFrameCalls.count, 3)
        XCTAssertEqual(mock.setFrameCalls[2].frame, idealTarget)
    }

    // MARK: - Failed restore keeps the entry

    func testFailedRestoreKeepsEntrySoSecondAttemptStillRestores() {
        let mock = MockWindowControlling()
        let controller = makeController(mock)
        let screen = mainScreen
        let originalFrame = CGRect(x: screen.frame.minX + 10, y: screen.frame.minY + 10, width: 300, height: 300)
        let achievedFrame = CGRect(x: screen.frame.minX + 5, y: screen.frame.minY + 5, width: 400, height: 400)

        mock.focusedWindowToReturn = focusedWindow(frame: originalFrame)
        mock.achievedFrameToReturn = achievedFrame
        controller.tile(.maximize) // move + save

        // Restore attempt fails (setFrame returns nil, e.g. the AX re-read
        // failed) — the window is still sitting at achievedFrame, unmoved.
        mock.focusedWindowToReturn = focusedWindow(frame: achievedFrame)
        mock.achievedFrameToReturn = nil
        controller.tile(.maximize)

        XCTAssertEqual(mock.setFrameCalls.count, 2)
        XCTAssertEqual(mock.setFrameCalls[1].frame, originalFrame)

        // A second restore attempt, with the window still unmoved and the
        // entry still intact, should try to restore to the same original
        // frame again — not fall back to a fresh maximize, which is what
        // would happen if the failed attempt above had dropped the entry.
        mock.focusedWindowToReturn = focusedWindow(frame: achievedFrame)
        mock.achievedFrameToReturn = originalFrame
        controller.tile(.maximize)

        XCTAssertEqual(mock.setFrameCalls.count, 3)
        XCTAssertEqual(mock.setFrameCalls[2].frame, originalFrame)
    }

    // MARK: - Halves never touch the map

    func testHalfTilingNeverTouchesSavedFrameMap() {
        let mock = MockWindowControlling()
        let controller = makeController(mock)
        let screen = mainScreen
        let idealTarget = screen.visibleFrame
        let leftHalfTarget = CGRect(
            x: screen.visibleFrame.minX,
            y: screen.visibleFrame.minY,
            width: screen.visibleFrame.width / 2,
            height: screen.visibleFrame.height
        )

        mock.focusedWindowToReturn = focusedWindow(
            frame: CGRect(x: screen.frame.minX + 10, y: screen.frame.minY + 10, width: 300, height: 300)
        )
        mock.achievedFrameToReturn = leftHalfTarget
        controller.tile(.leftHalf)

        XCTAssertEqual(mock.setFrameCalls.count, 1)
        XCTAssertEqual(mock.setFrameCalls[0].frame, leftHalfTarget)

        // The window is now sitting exactly at what left-half asked for. If
        // leftHalf had written to the saved-frame map the way maximize does,
        // a maximize press now could misread this as "already maximized"
        // and restore instead of moving. It shouldn't have written anything.
        mock.focusedWindowToReturn = focusedWindow(frame: leftHalfTarget)
        controller.tile(.maximize)

        XCTAssertEqual(mock.setFrameCalls.count, 2)
        XCTAssertEqual(mock.setFrameCalls[1].frame, idealTarget)
    }
}
