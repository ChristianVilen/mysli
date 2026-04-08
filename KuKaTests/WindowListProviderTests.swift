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

    func testCGToNSCoordinateConversion() {
        // CG: origin top-left. NS: origin bottom-left.
        // For primary screen height 1440, a CG rect at (100, 200, 800, 600)
        // should become NS (100, 1440-200-600, 800, 600) = (100, 640, 800, 600)
        let cgRect = CGRect(x: 100, y: 200, width: 800, height: 600)
        let nsRect = CGWindowListProvider.cgToNS(cgRect: cgRect, primaryScreenHeight: 1440)
        XCTAssertEqual(nsRect, CGRect(x: 100, y: 640, width: 800, height: 600))
    }

    func testCGToNSConversionAtTopEdge() {
        // Window at very top of screen in CG coords (y=0)
        let cgRect = CGRect(x: 0, y: 0, width: 400, height: 300)
        let nsRect = CGWindowListProvider.cgToNS(cgRect: cgRect, primaryScreenHeight: 900)
        XCTAssertEqual(nsRect, CGRect(x: 0, y: 600, width: 400, height: 300))
    }

    func testCGToNSConversionAtBottomEdge() {
        // Window at very bottom of screen in CG coords
        let cgRect = CGRect(x: 0, y: 600, width: 400, height: 300)
        let nsRect = CGWindowListProvider.cgToNS(cgRect: cgRect, primaryScreenHeight: 900)
        XCTAssertEqual(nsRect, CGRect(x: 0, y: 0, width: 400, height: 300))
    }
}
