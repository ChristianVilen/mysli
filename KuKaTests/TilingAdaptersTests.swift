import XCTest
@testable import KuKa

final class TilingAdaptersTests: XCTestCase {

    // MARK: - TilingScreenRules.windowCount(on:windows:)

    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)

    private func window(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, ownerName: String = "SomeApp") -> WindowInfo {
        WindowInfo(windowID: 1, frame: CGRect(x: x, y: y, width: width, height: height), ownerName: ownerName, layer: 0)
    }

    func testWindowMostlyOnNeighboringScreenDoesNotCount() {
        // Only 25% of the window's width is on this screen.
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

    private let screenA = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    private let screenB = CGRect(x: 1000, y: 0, width: 1200, height: 1000)

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
