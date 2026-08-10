import XCTest
@testable import KuKa

final class WindowListProviderTests: XCTestCase {

    func testMockWindowListProviderReturnsExpectedWindows() {
        let mock = MockWindowListProvider()
        let window = WindowInfo(windowID: 42, frame: CGRect(x: 100, y: 200, width: 800, height: 600), ownerName: "TestApp", layer: 0)
        mock.windows = [window]

        let result = mock.windowsOnScreen()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].windowID, 42)
        XCTAssertEqual(result[0].ownerName, "TestApp")
        XCTAssertEqual(result[0].frame, CGRect(x: 100, y: 200, width: 800, height: 600))
    }

    // ScreenCoordinates.flipVertical is the one flip shared by CG (window
    // list), AX (window control), and NS coordinate conversion — its math is
    // pinned here.

    func testFlipVerticalHandComputed() {
        // Top-left origin -> bottom-left origin.
        // For primary screen height 1440, a rect at (100, 200, 800, 600)
        // should become (100, 1440-200-600, 800, 600) = (100, 640, 800, 600)
        let rect = CGRect(x: 100, y: 200, width: 800, height: 600)
        let flipped = ScreenCoordinates.flipVertical(rect, primaryScreenHeight: 1440)
        XCTAssertEqual(flipped, CGRect(x: 100, y: 640, width: 800, height: 600))
    }

    func testFlipVerticalAtTopEdge() {
        // Window at the very top of the screen in top-left coords (y=0)
        let rect = CGRect(x: 0, y: 0, width: 400, height: 300)
        let flipped = ScreenCoordinates.flipVertical(rect, primaryScreenHeight: 900)
        XCTAssertEqual(flipped, CGRect(x: 0, y: 600, width: 400, height: 300))
    }

    func testFlipVerticalAtBottomEdge() {
        // Window at the very bottom of the screen in top-left coords
        let rect = CGRect(x: 0, y: 600, width: 400, height: 300)
        let flipped = ScreenCoordinates.flipVertical(rect, primaryScreenHeight: 900)
        XCTAssertEqual(flipped, CGRect(x: 0, y: 0, width: 400, height: 300))
    }

    func testFlipVerticalIsItsOwnInverse() {
        let rect = CGRect(x: 123, y: 456, width: 789, height: 321)
        let there = ScreenCoordinates.flipVertical(rect, primaryScreenHeight: 1600)
        let back = ScreenCoordinates.flipVertical(there, primaryScreenHeight: 1600)
        XCTAssertEqual(back, rect)
    }
}
