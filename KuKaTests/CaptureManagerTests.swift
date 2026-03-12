import XCTest
@testable import KuKa

final class CaptureManagerTests: XCTestCase {
    var mockFileManager: MockFileManager!
    var mockClipboard: MockClipboard!
    var mockScreenCapture: MockScreenCapture!
    var sut: CaptureManager!

    override func setUp() {
        super.setUp()
        mockFileManager = MockFileManager()
        mockClipboard = MockClipboard()
        mockScreenCapture = MockScreenCapture()
        sut = CaptureManager(fileManager: mockFileManager, clipboard: mockClipboard, screenCapture: mockScreenCapture)
    }

    // MARK: - captureFullScreen()

    func testCaptureFullScreenReturnsResultOnSuccess() {
        mockScreenCapture.imageToReturn = MockScreenCapture.make1x1Image()
        let result = sut.captureFullScreen(screen: NSScreen.main!)
        XCTAssertNotNil(result)
    }

    func testCaptureFullScreenReturnsNilOnFailure() {
        mockScreenCapture.imageToReturn = nil
        let result = sut.captureFullScreen(screen: NSScreen.main!)
        XCTAssertNil(result)
    }

    func testCaptureFullScreenCopiesClipboard() {
        mockScreenCapture.imageToReturn = MockScreenCapture.make1x1Image()
        _ = sut.captureFullScreen(screen: NSScreen.main!)
        XCTAssertEqual(mockClipboard.copiedCount, 1)
    }

    func testCaptureFullScreenCreatesDirectory() {
        mockScreenCapture.imageToReturn = MockScreenCapture.make1x1Image()
        _ = sut.captureFullScreen(screen: NSScreen.main!)
        XCTAssertEqual(mockFileManager.createdDirectories.count, 1)
        XCTAssertTrue(mockFileManager.createdDirectories[0].path.hasSuffix("Screenshots"))
    }

    // MARK: - capture()

    func testCaptureReturnsNilWhenScreenCaptureReturnsNil() {
        mockScreenCapture.imageToReturn = nil
        let screen = NSScreen.main!
        let result = sut.capture(rect: CGRect(x: 0, y: 0, width: 100, height: 100), screen: screen)
        XCTAssertNil(result)
    }

    func testCaptureReturnsResultOnSuccess() {
        mockScreenCapture.imageToReturn = MockScreenCapture.make1x1Image()
        let screen = NSScreen.main!
        let result = sut.capture(rect: CGRect(x: 10, y: 20, width: 100, height: 50), screen: screen)
        XCTAssertNotNil(result)
        XCTAssertNotNil(result?.image)
        XCTAssertNotNil(result?.fileURL)
    }

    func testCaptureCreatesScreenshotsDirectory() {
        mockScreenCapture.imageToReturn = MockScreenCapture.make1x1Image()
        let screen = NSScreen.main!
        _ = sut.capture(rect: CGRect(x: 0, y: 0, width: 10, height: 10), screen: screen)
        XCTAssertEqual(mockFileManager.createdDirectories.count, 1)
        XCTAssertTrue(mockFileManager.createdDirectories[0].path.hasSuffix("Screenshots"))
    }

    func testCaptureCopiesImageToClipboard() {
        mockScreenCapture.imageToReturn = MockScreenCapture.make1x1Image()
        let screen = NSScreen.main!
        _ = sut.capture(rect: CGRect(x: 0, y: 0, width: 10, height: 10), screen: screen)
        XCTAssertEqual(mockClipboard.copiedCount, 1)
    }

    func testCaptureDoesNotCopyToClipboardOnFailure() {
        mockScreenCapture.imageToReturn = nil
        let screen = NSScreen.main!
        _ = sut.capture(rect: CGRect(x: 0, y: 0, width: 10, height: 10), screen: screen)
        XCTAssertEqual(mockClipboard.copiedCount, 0)
    }

    // MARK: - Coordinate Conversion

    func testCoordinateConversion() {
        // The capture method converts from NSView (bottom-left origin) to CG (top-left origin)
        // For a screen of height 1000, a rect at y=200 with height=100 should become y=700 in CG coords
        // y_cg = screenHeight - rect.y - rect.height = 1000 - 200 - 100 = 700
        let screenFrame = NSScreen.main!.frame
        let rect = CGRect(x: 50, y: 200, width: 100, height: 100)
        let expectedY = screenFrame.height - rect.origin.y - rect.height

        // We can verify by checking what rect the screen capture receives
        var capturedRect: CGRect?
        class SpyScreenCapture: ScreenCapturing {
            var onCapture: ((CGRect) -> Void)?
            func captureScreen(rect: CGRect) -> CGImage? {
                onCapture?(rect)
                return MockScreenCapture.make1x1Image()
            }
        }
        let spy = SpyScreenCapture()
        spy.onCapture = { capturedRect = $0 }
        let manager = CaptureManager(fileManager: mockFileManager, clipboard: mockClipboard, screenCapture: spy)

        let screen = NSScreen.main!
        _ = manager.capture(rect: rect, screen: screen)

        XCTAssertNotNil(capturedRect)
        XCTAssertEqual(capturedRect!.origin.x, screenFrame.origin.x + 50, accuracy: 0.01)
        XCTAssertEqual(capturedRect!.origin.y, expectedY, accuracy: 0.01)
        XCTAssertEqual(capturedRect!.width, 100, accuracy: 0.01)
        XCTAssertEqual(capturedRect!.height, 100, accuracy: 0.01)
    }

    // MARK: - File Naming

    func testFileNameFormat() {
        let calendar = Calendar.current
        let components = DateComponents(year: 2026, month: 2, day: 25, hour: 14, minute: 30, second: 0)
        let date = calendar.date(from: components)!
        let name = sut.generateFileName(for: date)
        XCTAssertEqual(name, "Screenshot_2026-02-25_at_14-30-00.png")
    }

    func testScreenshotsDirectoryPath() {
        let dir = sut.screenshotsDirectory()
        XCTAssertTrue(dir.path.hasSuffix("Screenshots"))
        XCTAssertTrue(dir.path.hasPrefix(mockFileManager.homeDirectoryForCurrentUser.path))
    }

    // MARK: - saveAnnotated()

    func testSaveAnnotatedWritesFileAndCopiesToClipboard() {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()

        let url = URL(fileURLWithPath: "/tmp/kuka-test/annotated.png")
        sut.saveAnnotated(image: image, to: url)

        XCTAssertEqual(mockFileManager.writtenFiles.count, 1)
        XCTAssertEqual(mockFileManager.writtenFiles[0].url, url)
        XCTAssertEqual(mockClipboard.copiedCount, 1)
    }

    // MARK: - deleteScreenshot()

    func testDeleteScreenshotRemovesFile() {
        let url = URL(fileURLWithPath: "/tmp/kuka-test/Screenshots/test.png")
        sut.deleteScreenshot(at: url)
        XCTAssertEqual(mockFileManager.removedItems, [url])
    }

    func testDeleteScreenshotClearsClipboard() {
        let url = URL(fileURLWithPath: "/tmp/kuka-test/Screenshots/test.png")
        sut.deleteScreenshot(at: url)
        XCTAssertEqual(mockClipboard.clearedCount, 1)
    }
}
