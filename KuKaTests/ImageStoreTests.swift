import XCTest
@testable import KuKa

final class ImageStoreTests: XCTestCase {
    var mockFileManager: MockFileManager!
    var mockClipboard: MockClipboard!
    var sut: ImageStore!

    override func setUp() {
        super.setUp()
        mockFileManager = MockFileManager()
        mockClipboard = MockClipboard()
        sut = ImageStore(fileManager: mockFileManager, clipboard: mockClipboard)
    }

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

    // MARK: - store()

    func testStoreWritesDiskCopiesClipboardAndReturnsResult() {
        let result = sut.store(cgImage: MockScreenCapture.makeImage(width: 8, height: 6))

        XCTAssertEqual(mockFileManager.createdDirectories.count, 1)
        XCTAssertTrue(mockFileManager.createdDirectories[0].path.hasSuffix("Screenshots"))
        XCTAssertEqual(mockFileManager.writtenFiles.count, 1)
        XCTAssertEqual(mockFileManager.writtenFiles[0].url, result.fileURL)
        XCTAssertEqual(mockClipboard.copiedCount, 1)
        XCTAssertEqual(Int(result.image.size.width), 8)
    }

    // MARK: - File naming

    func testStoreTwiceInSameSecondProducesDistinctFileNames() {
        // File names have one-second resolution; a second capture in the
        // same second must not overwrite the first on disk.
        let frozen = Date(timeIntervalSince1970: 1_700_000_000)
        let sut = ImageStore(fileManager: mockFileManager, clipboard: mockClipboard, now: { frozen })

        let first = sut.store(cgImage: MockScreenCapture.make1x1Image())
        let second = sut.store(cgImage: MockScreenCapture.make1x1Image())

        XCTAssertNotEqual(first.fileURL, second.fileURL)
        let firstBase = first.fileURL.deletingPathExtension().lastPathComponent
        XCTAssertEqual(second.fileURL.lastPathComponent, "\(firstBase)-2.png")
    }

    func testThirdStoreInSameSecondCountsUp() {
        let frozen = Date(timeIntervalSince1970: 1_700_000_000)
        let sut = ImageStore(fileManager: mockFileManager, clipboard: mockClipboard, now: { frozen })

        let first = sut.store(cgImage: MockScreenCapture.make1x1Image())
        _ = sut.store(cgImage: MockScreenCapture.make1x1Image())
        let third = sut.store(cgImage: MockScreenCapture.make1x1Image())

        let firstBase = first.fileURL.deletingPathExtension().lastPathComponent
        XCTAssertEqual(third.fileURL.lastPathComponent, "\(firstBase)-3.png")
    }

    func testFileNameFormat() {
        let calendar = Calendar.current
        let components = DateComponents(year: 2026, month: 2, day: 25, hour: 14, minute: 30, second: 0)
        let date = calendar.date(from: components)!
        let name = sut.generateFileName(for: date)
        XCTAssertEqual(name, "Screenshot_2026-02-25_at_14-30-00.png")
    }

    func testCombinedFileNameFormat() {
        let components = DateComponents(year: 2026, month: 2, day: 25, hour: 14, minute: 30, second: 0)
        let date = Calendar.current.date(from: components)!
        XCTAssertEqual(sut.generateCombinedFileName(for: date), "Screenshot_2026-02-25_at_14-30-00_combined.png")
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

    // MARK: - storeCombined()

    func testStoreCombinedDimensionsAddLinearly() {
        let top = makeCaptureImage(width: 100, height: 80)
        let bottom = makeCaptureImage(width: 60, height: 50)

        let result = sut.storeCombined(top: top, bottom: bottom)

        let combined = result?.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        XCTAssertEqual(combined?.width, 100)
        XCTAssertEqual(combined?.height, 130)
    }

    func testRepeatedCombineStaysLinear() {
        // Regression: composing via NSImage.lockFocus re-rendered at the
        // screen's backing scale, doubling pixel dimensions on every combine.
        let firstCombine = sut.storeCombined(top: makeCaptureImage(width: 100, height: 80),
                                             bottom: makeCaptureImage(width: 100, height: 80))!

        let secondCombine = sut.storeCombined(top: firstCombine.image,
                                              bottom: makeCaptureImage(width: 100, height: 40))

        let combined = secondCombine?.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        XCTAssertEqual(combined?.width, 100)
        XCTAssertEqual(combined?.height, 200)
    }

    func testStoreCombinedStacksTopImageAboveBottomImage() {
        let top = makeCaptureImage(width: 10, height: 10, red: 1, green: 0, blue: 0)
        let bottom = makeCaptureImage(width: 10, height: 10, red: 0, green: 0, blue: 1)

        let result = sut.storeCombined(top: top, bottom: bottom)
        guard let combined = result?.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return XCTFail("storeCombined returned no image")
        }

        XCTAssertEqual(pixelRGB(in: combined, x: 5, y: 2), [255, 0, 0])
        XCTAssertEqual(pixelRGB(in: combined, x: 5, y: 17), [0, 0, 255])
    }

    func testStoreCombinedWritesPNGAtPixelDimensions() {
        _ = sut.storeCombined(top: makeCaptureImage(width: 8, height: 6),
                              bottom: makeCaptureImage(width: 8, height: 6))

        XCTAssertEqual(mockFileManager.writtenFiles.count, 1)
        let written = NSBitmapImageRep(data: mockFileManager.writtenFiles[0].data)
        XCTAssertEqual(written?.pixelsWide, 8)
        XCTAssertEqual(written?.pixelsHigh, 12)
    }

    func testStoreCombinedUsesCombinedFileNameAndCopiesClipboard() {
        let result = sut.storeCombined(top: makeCaptureImage(width: 4, height: 4),
                                       bottom: makeCaptureImage(width: 4, height: 4))

        XCTAssertTrue(result!.fileURL.lastPathComponent.hasSuffix("_combined.png"))
        XCTAssertEqual(mockFileManager.writtenFiles[0].url, result!.fileURL)
        XCTAssertEqual(mockClipboard.copiedCount, 1)
    }

    // MARK: - Clipboard TIFF threshold

    private func makeStore(tiffMaxPixels: Int) -> ImageStore {
        ImageStore(fileManager: mockFileManager, clipboard: mockClipboard, clipboardTIFFMaxPixels: tiffMaxPixels)
    }

    func testClipboardIncludesTiffAtOrBelowThreshold() {
        let sut = makeStore(tiffMaxPixels: 100)
        sut.copyToClipboard(cgImage: MockScreenCapture.makeImage(width: 10, height: 10))
        XCTAssertNotNil(mockClipboard.lastTiffData)
        XCTAssertNotNil(mockClipboard.lastPngData)
    }

    func testClipboardSkipsTiffAboveThreshold() {
        let sut = makeStore(tiffMaxPixels: 100)
        sut.copyToClipboard(cgImage: MockScreenCapture.makeImage(width: 11, height: 10))
        XCTAssertEqual(mockClipboard.copiedCount, 1)
        XCTAssertNil(mockClipboard.lastTiffData)
        XCTAssertNotNil(mockClipboard.lastPngData)
    }

    // MARK: - delete()

    func testDeleteRemovesFile() {
        let url = URL(fileURLWithPath: "/tmp/kuka-test/Screenshots/test.png")
        sut.delete(at: url)
        XCTAssertEqual(mockFileManager.removedItems, [url])
    }

    func testDeleteOfLastCopiedCaptureClearsClipboard() {
        let result = sut.store(cgImage: MockScreenCapture.make1x1Image())
        sut.delete(at: result.fileURL)
        XCTAssertEqual(mockClipboard.clearedCount, 1)
    }

    func testDeleteOfOtherFileKeepsClipboard() {
        // The clipboard holds the most recent capture; deleting an older
        // screenshot must not wipe it.
        _ = sut.store(cgImage: MockScreenCapture.make1x1Image())
        sut.delete(at: URL(fileURLWithPath: "/tmp/kuka-test/Screenshots/older.png"))
        XCTAssertEqual(mockClipboard.clearedCount, 0)
    }

    func testDeleteAfterSaveAnnotatedToSameURLClearsClipboard() {
        // saveAnnotated re-copies the annotated image, so its URL becomes
        // the one the clipboard tracks.
        let url = URL(fileURLWithPath: "/tmp/kuka-test/Screenshots/annotated.png")
        sut.saveAnnotated(image: makeCaptureImage(width: 4, height: 4), to: url)
        sut.delete(at: url)
        XCTAssertEqual(mockClipboard.clearedCount, 1)
    }
}
