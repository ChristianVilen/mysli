import XCTest
@testable import KuKa

final class TilingAdaptersTests: XCTestCase {

    // MARK: - TilingScreenRules.windowCount(on:windows:)

    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)

    private func window(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, ownerName: String = "SomeApp") -> WindowInfo {
        WindowInfo(windowID: 1, frame: CGRect(x: x, y: y, width: width, height: height), ownerName: ownerName, layer: 0)
    }

    func testWindowFullyOnScreenCounts() {
        let windows = [window(x: 100, y: 100, width: 200, height: 200)]
        XCTAssertEqual(TilingScreenRules.windowCount(on: screen, windows: windows), 1)
    }

    func testWindowMostlyOnThisScreenCounts() {
        // 800x1000 window straddling the right edge: 600 of its 800 width
        // (75%) is on this screen.
        let windows = [window(x: 400, y: 0, width: 800, height: 1000)]
        XCTAssertEqual(TilingScreenRules.windowCount(on: screen, windows: windows), 1)
    }

    func testWindowMostlyOnNeighboringScreenDoesNotCount() {
        // Mirror of the above: only 25% of the window's width is on this screen.
        let windows = [window(x: 800, y: 0, width: 800, height: 1000)]
        XCTAssertEqual(TilingScreenRules.windowCount(on: screen, windows: windows), 0)
    }

    func testWindowAtExactlyFiftyPercentBoundaryCounts() {
        // 200x1000 window: exactly 100 (50%) of its width overlaps this screen.
        let windows = [window(x: 900, y: 0, width: 200, height: 1000)]
        XCTAssertEqual(TilingScreenRules.windowCount(on: screen, windows: windows), 1)
    }

    func testWindowManagerOwnedWindowIsExcluded() {
        let windows = [window(x: 100, y: 100, width: 200, height: 200, ownerName: "WindowManager")]
        XCTAssertEqual(TilingScreenRules.windowCount(on: screen, windows: windows), 0)
    }

    func testZeroSizeWindowIsExcluded() {
        let windows = [window(x: 100, y: 100, width: 0, height: 0)]
        XCTAssertEqual(TilingScreenRules.windowCount(on: screen, windows: windows), 0)
    }

    func testEmptyWindowListReturnsZero() {
        XCTAssertEqual(TilingScreenRules.windowCount(on: screen, windows: []), 0)
    }

    func testMultipleWindowsCountsOnlyThoseQualifying() {
        let windows = [
            window(x: 100, y: 100, width: 200, height: 200),   // fully on screen: counts
            window(x: 800, y: 0, width: 800, height: 1000),    // mostly off screen: doesn't count
            window(x: 100, y: 100, width: 200, height: 200, ownerName: "WindowManager") // excluded by owner
        ]
        XCTAssertEqual(TilingScreenRules.windowCount(on: screen, windows: windows), 1)
    }

    func testWindowNotTouchingScreenAtAllDoesNotCount() {
        // Entirely off to the right: CGRect.intersection returns .null here,
        // a different code path than a low-but-nonzero overlap.
        let windows = [window(x: 2000, y: 0, width: 200, height: 200)]
        XCTAssertEqual(TilingScreenRules.windowCount(on: screen, windows: windows), 0)
    }

    func testWindowWiderThanTwiceTheScreenCountsOnNoScreen() {
        // Accepted v1 limitation: a window more than twice the screen's
        // width, centered over it, never reaches the 50% overlap threshold
        // for that screen (only ~45% of its area overlaps here), so it
        // counts on none of the windows' screens. See the doc comment on
        // TilingScreenRules.windowCount for the same note.
        let windows = [window(x: -1100, y: 0, width: 2200, height: 1000)]
        XCTAssertEqual(TilingScreenRules.windowCount(on: screen, windows: windows), 0)
    }

    func testCountingOnScreenWithNonZeroOrigin() {
        let offsetScreen = CGRect(x: 1920, y: 25, width: 1600, height: 975)
        let windows = [
            window(x: 2000, y: 100, width: 400, height: 400),   // fully on the offset screen
            window(x: 100, y: 100, width: 400, height: 400)     // nowhere near it
        ]
        XCTAssertEqual(TilingScreenRules.windowCount(on: offsetScreen, windows: windows), 1)
    }

    // MARK: - TilingScreenRules.bestScreenIndex(for:screenFrames:)

    private let screenA = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    private let screenB = CGRect(x: 1000, y: 0, width: 1200, height: 1000)

    func testBestScreenIndexPicksScreenWindowIsClearlyOn() {
        let window = CGRect(x: 1100, y: 100, width: 200, height: 200) // fully within screenB
        XCTAssertEqual(TilingScreenRules.bestScreenIndex(for: window, screenFrames: [screenA, screenB]), 1)
    }

    func testBestScreenIndexPicksScreenWithLargerShareWhenStraddling() {
        // Straddles the x=1000 boundary: 700pt of width on screenA, 100pt on screenB.
        let window = CGRect(x: 700, y: 100, width: 400, height: 200)
        XCTAssertEqual(TilingScreenRules.bestScreenIndex(for: window, screenFrames: [screenA, screenB]), 0)
    }

    func testBestScreenIndexReturnsNilWhenNoScreenIntersects() {
        let window = CGRect(x: 5000, y: 5000, width: 100, height: 100)
        XCTAssertNil(TilingScreenRules.bestScreenIndex(for: window, screenFrames: [screenA, screenB]))
    }

    func testBestScreenIndexReturnsNilForEmptyScreenList() {
        let window = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertNil(TilingScreenRules.bestScreenIndex(for: window, screenFrames: []))
    }

    func testBestScreenIndexWithNonZeroOriginScreens() {
        let screens = [
            CGRect(x: -500, y: 25, width: 1000, height: 900),
            CGRect(x: 500, y: 25, width: 1600, height: 975)
        ]
        let window = CGRect(x: 600, y: 100, width: 300, height: 300) // within the second screen
        XCTAssertEqual(TilingScreenRules.bestScreenIndex(for: window, screenFrames: screens), 1)
    }

    func testBestScreenIndexTiesBreakTowardLowestIndex() {
        let screens = [
            CGRect(x: 0, y: 0, width: 200, height: 200),
            CGRect(x: 200, y: 0, width: 200, height: 200)
        ]
        // Straddles exactly in the middle: 100pt of overlap with each screen.
        let window = CGRect(x: 100, y: 0, width: 200, height: 200)
        XCTAssertEqual(TilingScreenRules.bestScreenIndex(for: window, screenFrames: screens), 0)
    }

    // MARK: - TilingScreenRules.adjacentScreenIndex(of:direction:screenFrames:)

    func testAdjacentScreenIndexWithTwoScreensEitherDirectionGivesTheOtherScreen() {
        let screens = [screenA, screenB]
        XCTAssertEqual(TilingScreenRules.adjacentScreenIndex(of: 0, direction: .left, screenFrames: screens), 1)
        XCTAssertEqual(TilingScreenRules.adjacentScreenIndex(of: 0, direction: .right, screenFrames: screens), 1)
        XCTAssertEqual(TilingScreenRules.adjacentScreenIndex(of: 1, direction: .left, screenFrames: screens), 0)
        XCTAssertEqual(TilingScreenRules.adjacentScreenIndex(of: 1, direction: .right, screenFrames: screens), 0)
    }

    func testAdjacentScreenIndexWithThreeScreensStepsByHorizontalPosition() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1000, height: 1000),
            CGRect(x: 1000, y: 0, width: 1000, height: 1000),
            CGRect(x: 2000, y: 0, width: 1000, height: 1000)
        ]
        XCTAssertEqual(TilingScreenRules.adjacentScreenIndex(of: 1, direction: .left, screenFrames: screens), 0)
        XCTAssertEqual(TilingScreenRules.adjacentScreenIndex(of: 1, direction: .right, screenFrames: screens), 2)
    }

    func testAdjacentScreenIndexWrapsAroundAtTheEdges() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1000, height: 1000),
            CGRect(x: 1000, y: 0, width: 1000, height: 1000),
            CGRect(x: 2000, y: 0, width: 1000, height: 1000)
        ]
        XCTAssertEqual(TilingScreenRules.adjacentScreenIndex(of: 0, direction: .left, screenFrames: screens), 2)
        XCTAssertEqual(TilingScreenRules.adjacentScreenIndex(of: 2, direction: .right, screenFrames: screens), 0)
    }

    func testAdjacentScreenIndexOrdersByPositionNotArrayOrder() {
        // The array lists the rightmost screen first — stepping right from
        // the middle screen (index 2) must land on the geometrically next
        // one (index 0), not follow array order.
        let screens = [
            CGRect(x: 2000, y: 0, width: 1000, height: 1000),
            CGRect(x: 0, y: 0, width: 1000, height: 1000),
            CGRect(x: 1000, y: 0, width: 1000, height: 1000)
        ]
        XCTAssertEqual(TilingScreenRules.adjacentScreenIndex(of: 2, direction: .right, screenFrames: screens), 0)
        XCTAssertEqual(TilingScreenRules.adjacentScreenIndex(of: 2, direction: .left, screenFrames: screens), 1)
    }

    func testAdjacentScreenIndexReturnsNilWithSingleScreen() {
        XCTAssertNil(TilingScreenRules.adjacentScreenIndex(of: 0, direction: .left, screenFrames: [screenA]))
    }

    func testAdjacentScreenIndexReturnsNilForOutOfRangeIndex() {
        XCTAssertNil(TilingScreenRules.adjacentScreenIndex(of: 5, direction: .left, screenFrames: [screenA, screenB]))
    }

}
