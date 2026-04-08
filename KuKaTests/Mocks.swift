import XCTest
@testable import KuKa

// MARK: - Mock FileManager

class MockFileManager: FileManaging {
    var homeDirectoryForCurrentUser: URL = URL(fileURLWithPath: "/tmp/kuka-test")
    var createdDirectories: [URL] = []
    var writtenFiles: [(data: Data, url: URL)] = []
    var removedItems: [URL] = []

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]?) throws {
        createdDirectories.append(url)
    }

    func writeImageData(_ data: Data, to url: URL) throws {
        writtenFiles.append((data, url))
    }

    func removeItem(at url: URL) throws {
        removedItems.append(url)
    }
}

// MARK: - Mock Clipboard

class MockClipboard: ClipboardManaging {
    var copiedCount = 0
    var clearedCount = 0
    var lastTiffData: Data?
    var lastPngData: Data?

    func copyImage(tiffData: Data, pngData: Data) {
        copiedCount += 1
        lastTiffData = tiffData
        lastPngData = pngData
    }

    func clearClipboard() {
        clearedCount += 1
    }
}

// MARK: - Mock Screen Capture

class MockScreenCapture: ScreenCapturing {
    var imageToReturn: CGImage?
    var windowImageToReturn: CGImage?

    func captureScreen(rect: CGRect) -> CGImage? {
        imageToReturn
    }

    func captureWindow(windowID: CGWindowID) -> CGImage? {
        windowImageToReturn ?? imageToReturn
    }

    /// Creates a 1x1 red CGImage for testing
    static func make1x1Image() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage()!
    }
}

// MARK: - Mock WindowListProvider

class MockWindowListProvider: WindowListProvider {
    var windows: [WindowInfo] = []

    func windowsOnScreen() -> [WindowInfo] {
        windows
    }
}
