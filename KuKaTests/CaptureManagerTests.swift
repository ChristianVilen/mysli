import XCTest
@testable import KuKa

final class SpyScreenCapture: ScreenCapturing {
    var onCapture: ((CGRect) -> Void)?

    func captureScreen(rect: CGRect) async -> CGImage? {
        onCapture?(rect)
        return MockScreenCapture.make1x1Image()
    }

    func captureWindow(windowID: CGWindowID) async -> CGImage? { nil }
}

final class CaptureManagerTests: XCTestCase {
    var mockScreenCapture: MockScreenCapture!
    var fakeStore: FakeImageStore!
    var sut: CaptureManager!

    override func setUp() {
        super.setUp()
        mockScreenCapture = MockScreenCapture()
        fakeStore = FakeImageStore()
        sut = CaptureManager(screenCapture: mockScreenCapture, store: fakeStore)
    }

    private let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    // MARK: - captureFullScreen()

    func testCaptureFullScreenReturnsResultOnSuccess() async {
        mockScreenCapture.imageToReturn = MockScreenCapture.make1x1Image()
        let result = await sut.captureFullScreen(screenFrame: screenFrame, primaryHeight: 900)
        XCTAssertNotNil(result)
    }

    func testCaptureFullScreenReturnsNilOnFailure() async {
        mockScreenCapture.imageToReturn = nil
        let result = await sut.captureFullScreen(screenFrame: screenFrame, primaryHeight: 900)
        XCTAssertNil(result)
    }

    func testCaptureFullScreenStoresCapturedImage() async {
        mockScreenCapture.imageToReturn = MockScreenCapture.make1x1Image()
        _ = await sut.captureFullScreen(screenFrame: screenFrame, primaryHeight: 900)
        XCTAssertEqual(fakeStore.storedImages.count, 1)
    }

    // MARK: - captureWindow()

    func testCaptureWindowReturnsResultOnSuccess() async {
        mockScreenCapture.imageToReturn = MockScreenCapture.make1x1Image()
        let result = await sut.captureWindow(windowID: 42)
        XCTAssertNotNil(result)
    }

    func testCaptureWindowReturnsNilOnFailure() async {
        mockScreenCapture.imageToReturn = nil
        let result = await sut.captureWindow(windowID: 42)
        XCTAssertNil(result)
    }

    func testCaptureWindowStoresCapturedImage() async {
        mockScreenCapture.imageToReturn = MockScreenCapture.make1x1Image()
        _ = await sut.captureWindow(windowID: 42)
        XCTAssertEqual(fakeStore.storedImages.count, 1)
    }

    // MARK: - capture()

    func testCaptureReturnsNilWhenScreenCaptureReturnsNil() async {
        mockScreenCapture.imageToReturn = nil
        let result = await sut.capture(rect: CGRect(x: 0, y: 0, width: 100, height: 100), screenFrame: screenFrame, primaryHeight: 900)
        XCTAssertNil(result)
    }

    func testCaptureReturnsResultOnSuccess() async {
        mockScreenCapture.imageToReturn = MockScreenCapture.make1x1Image()
        let result = await sut.capture(rect: CGRect(x: 10, y: 20, width: 100, height: 50), screenFrame: screenFrame, primaryHeight: 900)
        XCTAssertNotNil(result)
        XCTAssertNotNil(result?.image)
        XCTAssertNotNil(result?.fileURL)
    }

    func testCaptureDoesNotStoreOnFailure() async {
        mockScreenCapture.imageToReturn = nil
        _ = await sut.capture(rect: CGRect(x: 0, y: 0, width: 10, height: 10), screenFrame: screenFrame, primaryHeight: 900)
        XCTAssertTrue(fakeStore.storedImages.isEmpty)
    }

    // MARK: - Coordinate Conversion

    func testCaptureFullScreenFlipsAgainstPrimaryHeight() async {
        // A 1000x800 secondary at NS (2000, 0) beside a 2000pt-tall primary:
        // CG y = 2000 - 0 - 800 = 1200, x unchanged.
        var capturedRect: CGRect?
        let spy = SpyScreenCapture()
        spy.onCapture = { capturedRect = $0 }
        let manager = CaptureManager(screenCapture: spy, store: fakeStore)

        _ = await manager.captureFullScreen(screenFrame: CGRect(x: 2000, y: 0, width: 1000, height: 800),
                                            primaryHeight: 2000)

        XCTAssertNotNil(capturedRect)
        XCTAssertEqual(capturedRect!.origin.x, 2000, accuracy: 0.01)
        XCTAssertEqual(capturedRect!.origin.y, 1200, accuracy: 0.01)
    }

    func testCoordinateConversion() async {
        // The capture method converts from NSView (bottom-left origin) to CG (top-left origin)
        // For a screen of height 1000, a rect at y=200 with height=100 should become y=700 in CG coords
        // y_cg = screenHeight - rect.y - rect.height = 1000 - 200 - 100 = 700
        let frame = CGRect(x: 100, y: 0, width: 1440, height: 1000)
        let rect = CGRect(x: 50, y: 200, width: 100, height: 100)

        // We can verify by checking what rect the screen capture receives
        var capturedRect: CGRect?
        let spy = SpyScreenCapture()
        spy.onCapture = { capturedRect = $0 }
        let manager = CaptureManager(screenCapture: spy, store: fakeStore)

        _ = await manager.capture(rect: rect, screenFrame: frame, primaryHeight: 1000)

        XCTAssertNotNil(capturedRect)
        XCTAssertEqual(capturedRect!.origin.x, 150, accuracy: 0.01)
        XCTAssertEqual(capturedRect!.origin.y, 700, accuracy: 0.01)
        XCTAssertEqual(capturedRect!.width, 100, accuracy: 0.01)
        XCTAssertEqual(capturedRect!.height, 100, accuracy: 0.01)
    }
}
