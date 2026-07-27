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

    func testCaptureFullScreenReturnsResultOnSuccess() async {
        mockScreenCapture.imageToReturn = MockScreenCapture.make1x1Image()
        let result = await sut.captureFullScreen(screen: NSScreen.main!)
        XCTAssertNotNil(result)
    }

    func testCaptureFullScreenReturnsNilOnFailure() async {
        mockScreenCapture.imageToReturn = nil
        let result = await sut.captureFullScreen(screen: NSScreen.main!)
        XCTAssertNil(result)
    }

    func testCaptureFullScreenCopiesClipboard() async {
        mockScreenCapture.imageToReturn = MockScreenCapture.make1x1Image()
        _ = await sut.captureFullScreen(screen: NSScreen.main!)
        XCTAssertEqual(mockClipboard.copiedCount, 1)
    }

    func testCaptureFullScreenCreatesDirectory() async {
        mockScreenCapture.imageToReturn = MockScreenCapture.make1x1Image()
        _ = await sut.captureFullScreen(screen: NSScreen.main!)
        XCTAssertEqual(mockFileManager.createdDirectories.count, 1)
        XCTAssertTrue(mockFileManager.createdDirectories[0].path.hasSuffix("Screenshots"))
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

    func testCaptureWindowSavesFileAndCopiesClipboard() async {
        mockScreenCapture.imageToReturn = MockScreenCapture.make1x1Image()
        _ = await sut.captureWindow(windowID: 42)
        XCTAssertEqual(mockFileManager.createdDirectories.count, 1)
        XCTAssertEqual(mockClipboard.copiedCount, 1)
    }

    // MARK: - capture()

    func testCaptureReturnsNilWhenScreenCaptureReturnsNil() async {
        mockScreenCapture.imageToReturn = nil
        let screen = NSScreen.main!
        let result = await sut.capture(rect: CGRect(x: 0, y: 0, width: 100, height: 100), screen: screen)
        XCTAssertNil(result)
    }

    func testCaptureReturnsResultOnSuccess() async {
        mockScreenCapture.imageToReturn = MockScreenCapture.make1x1Image()
        let screen = NSScreen.main!
        let result = await sut.capture(rect: CGRect(x: 10, y: 20, width: 100, height: 50), screen: screen)
        XCTAssertNotNil(result)
        XCTAssertNotNil(result?.image)
        XCTAssertNotNil(result?.fileURL)
    }

    func testCaptureCreatesScreenshotsDirectory() async {
        mockScreenCapture.imageToReturn = MockScreenCapture.make1x1Image()
        let screen = NSScreen.main!
        _ = await sut.capture(rect: CGRect(x: 0, y: 0, width: 10, height: 10), screen: screen)
        XCTAssertEqual(mockFileManager.createdDirectories.count, 1)
        XCTAssertTrue(mockFileManager.createdDirectories[0].path.hasSuffix("Screenshots"))
    }

    func testCaptureCopiesImageToClipboard() async {
        mockScreenCapture.imageToReturn = MockScreenCapture.make1x1Image()
        let screen = NSScreen.main!
        _ = await sut.capture(rect: CGRect(x: 0, y: 0, width: 10, height: 10), screen: screen)
        XCTAssertEqual(mockClipboard.copiedCount, 1)
    }

    func testCaptureDoesNotCopyToClipboardOnFailure() async {
        mockScreenCapture.imageToReturn = nil
        let screen = NSScreen.main!
        _ = await sut.capture(rect: CGRect(x: 0, y: 0, width: 10, height: 10), screen: screen)
        XCTAssertEqual(mockClipboard.copiedCount, 0)
    }

    // MARK: - Coordinate Conversion

    func testCoordinateConversion() async {
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
            func captureScreen(rect: CGRect) async -> CGImage? {
                onCapture?(rect)
                return MockScreenCapture.make1x1Image()
            }
            func captureWindow(windowID: CGWindowID) async -> CGImage? { nil }
        }
        let spy = SpyScreenCapture()
        spy.onCapture = { capturedRect = $0 }
        let manager = CaptureManager(fileManager: mockFileManager, clipboard: mockClipboard, screenCapture: spy)

        let screen = NSScreen.main!
        _ = await manager.capture(rect: rect, screen: screen)

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

    // MARK: - saveCombined()

    private func makeCaptureImage(width: Int, height: Int, red: CGFloat = 1, green: CGFloat = 0, blue: CGFloat = 0) -> NSImage {
        let cg = MockScreenCapture.makeImage(width: width, height: height, red: red, green: green, blue: blue)
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// Samples one pixel (y measured from the top scanline) by redrawing
    /// into an RGBA8 context, independent of the image's own byte layout.
    private func pixelRGB(in image: CGImage, x: Int, y: Int) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return [data[offset], data[offset + 1], data[offset + 2]]
    }

    func testSaveCombinedDimensionsAddLinearly() {
        let top = makeCaptureImage(width: 100, height: 80)
        let bottom = makeCaptureImage(width: 60, height: 50)

        let result = sut.saveCombined(topImage: top, bottomImage: bottom)

        let combined = result?.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        XCTAssertEqual(combined?.width, 100)
        XCTAssertEqual(combined?.height, 130)
    }

    func testRepeatedCombineStaysLinear() {
        // Regression: composing via NSImage.lockFocus re-rendered at the
        // screen's backing scale, doubling pixel dimensions on every combine.
        let firstCombine = sut.saveCombined(topImage: makeCaptureImage(width: 100, height: 80),
                                            bottomImage: makeCaptureImage(width: 100, height: 80))!

        let secondCombine = sut.saveCombined(topImage: firstCombine.image,
                                             bottomImage: makeCaptureImage(width: 100, height: 40))

        let combined = secondCombine?.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        XCTAssertEqual(combined?.width, 100)
        XCTAssertEqual(combined?.height, 200)
    }

    func testSaveCombinedStacksTopImageAboveBottomImage() {
        let top = makeCaptureImage(width: 10, height: 10, red: 1, green: 0, blue: 0)
        let bottom = makeCaptureImage(width: 10, height: 10, red: 0, green: 0, blue: 1)

        let result = sut.saveCombined(topImage: top, bottomImage: bottom)
        guard let combined = result?.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return XCTFail("saveCombined returned no image")
        }

        XCTAssertEqual(pixelRGB(in: combined, x: 5, y: 2), [255, 0, 0])
        XCTAssertEqual(pixelRGB(in: combined, x: 5, y: 17), [0, 0, 255])
    }

    func testSaveCombinedWritesPNGAtPixelDimensions() {
        _ = sut.saveCombined(topImage: makeCaptureImage(width: 8, height: 6),
                             bottomImage: makeCaptureImage(width: 8, height: 6))

        XCTAssertEqual(mockFileManager.writtenFiles.count, 1)
        let written = NSBitmapImageRep(data: mockFileManager.writtenFiles[0].data)
        XCTAssertEqual(written?.pixelsWide, 8)
        XCTAssertEqual(written?.pixelsHigh, 12)
    }

    func testSaveCombinedUsesCombinedFileNameAndCopiesClipboard() {
        let result = sut.saveCombined(topImage: makeCaptureImage(width: 4, height: 4),
                                      bottomImage: makeCaptureImage(width: 4, height: 4))

        XCTAssertTrue(result!.fileURL.lastPathComponent.hasSuffix("_combined.png"))
        XCTAssertEqual(mockFileManager.writtenFiles[0].url, result!.fileURL)
        XCTAssertEqual(mockClipboard.copiedCount, 1)
    }

    func testCombinedFileNameFormat() {
        let components = DateComponents(year: 2026, month: 2, day: 25, hour: 14, minute: 30, second: 0)
        let date = Calendar.current.date(from: components)!
        XCTAssertEqual(sut.generateCombinedFileName(for: date), "Screenshot_2026-02-25_at_14-30-00_combined.png")
    }

    // MARK: - Clipboard TIFF threshold

    private func makeManager(tiffMaxPixels: Int) -> CaptureManager {
        CaptureManager(fileManager: mockFileManager, clipboard: mockClipboard,
                       screenCapture: mockScreenCapture, clipboardTIFFMaxPixels: tiffMaxPixels)
    }

    func testClipboardIncludesTiffAtOrBelowThreshold() {
        let sut = makeManager(tiffMaxPixels: 100)
        sut.copyToClipboard(cgImage: MockScreenCapture.makeImage(width: 10, height: 10))
        XCTAssertNotNil(mockClipboard.lastTiffData)
        XCTAssertNotNil(mockClipboard.lastPngData)
    }

    func testClipboardSkipsTiffAboveThreshold() {
        let sut = makeManager(tiffMaxPixels: 100)
        sut.copyToClipboard(cgImage: MockScreenCapture.makeImage(width: 11, height: 10))
        XCTAssertEqual(mockClipboard.copiedCount, 1)
        XCTAssertNil(mockClipboard.lastTiffData)
        XCTAssertNotNil(mockClipboard.lastPngData)
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
