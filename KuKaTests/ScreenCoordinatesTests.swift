import XCTest
@testable import KuKa

/// ScreenCoordinates owns the app's NS/CG coordinate conversions — the math
/// shared by CG (window list), AX (window control), and screen capture is
/// pinned here.
final class ScreenCoordinatesTests: XCTestCase {

    // MARK: - flipVertical

    func testFlipVerticalHandComputed() {
        // Top-left origin -> bottom-left origin.
        // For primary screen height 1440, a rect at (100, 200, 800, 600)
        // should become (100, 1440-200-600, 800, 600) = (100, 640, 800, 600)
        let rect = CGRect(x: 100, y: 200, width: 800, height: 600)
        let flipped = ScreenCoordinates.flipVertical(rect, primaryScreenHeight: 1440)
        XCTAssertEqual(flipped, CGRect(x: 100, y: 640, width: 800, height: 600))
    }

    func testFlipVerticalIsItsOwnInverse() {
        let rect = CGRect(x: 123, y: 456, width: 789, height: 321)
        let there = ScreenCoordinates.flipVertical(rect, primaryScreenHeight: 1600)
        let back = ScreenCoordinates.flipVertical(there, primaryScreenHeight: 1600)
        XCTAssertEqual(back, rect)
    }

    // MARK: - cgRect(forSelection:)

    func testSelectionRectOnVerticallyOffsetSecondaryFlipsAgainstPrimaryHeight() {
        // Secondary at NS (1920, 100), 600pt tall, beside a 900pt primary.
        // Selection local (100, 50, 200, 100) → global NS y = 150,
        // CG y = 900 - 150 - 100 = 650. Flipping against the screen's own
        // height (the old bug) would give 450.
        let cg = ScreenCoordinates.cgRect(
            forSelection: CGRect(x: 100, y: 50, width: 200, height: 100),
            inScreenFrame: CGRect(x: 1920, y: 100, width: 1600, height: 600),
            primaryHeight: 900
        )
        XCTAssertEqual(cg, CGRect(x: 2020, y: 650, width: 200, height: 100))
    }

    // MARK: - bestScreenIndex(for:screenFrames:)

    private let screenA = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    private let screenB = CGRect(x: 1000, y: 0, width: 1200, height: 1000)

    func testBestScreenIndexPicksScreenWindowIsClearlyOn() {
        let window = CGRect(x: 1100, y: 100, width: 200, height: 200) // fully within screenB
        XCTAssertEqual(ScreenCoordinates.bestScreenIndex(for: window, screenFrames: [screenA, screenB]), 1)
    }

    func testBestScreenIndexPicksScreenWithLargerShareWhenStraddling() {
        // Straddles the x=1000 boundary: 700pt of width on screenA, 100pt on screenB.
        let window = CGRect(x: 700, y: 100, width: 400, height: 200)
        XCTAssertEqual(ScreenCoordinates.bestScreenIndex(for: window, screenFrames: [screenA, screenB]), 0)
    }

    func testBestScreenIndexReturnsNilWhenNoScreenIntersects() {
        let window = CGRect(x: 5000, y: 5000, width: 100, height: 100)
        XCTAssertNil(ScreenCoordinates.bestScreenIndex(for: window, screenFrames: [screenA, screenB]))
    }

    func testBestScreenIndexTiesBreakTowardLowestIndex() {
        let screens = [
            CGRect(x: 0, y: 0, width: 200, height: 200),
            CGRect(x: 200, y: 0, width: 200, height: 200)
        ]
        // Straddles exactly in the middle: 100pt of overlap with each screen.
        let window = CGRect(x: 100, y: 0, width: 200, height: 200)
        XCTAssertEqual(ScreenCoordinates.bestScreenIndex(for: window, screenFrames: screens), 0)
    }
}
