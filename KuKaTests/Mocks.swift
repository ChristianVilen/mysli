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

    func copyImage(tiffData: Data?, pngData: Data) {
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

    func captureScreen(rect: CGRect) async -> CGImage? {
        imageToReturn
    }

    func captureWindow(windowID: CGWindowID) async -> CGImage? {
        windowImageToReturn ?? imageToReturn
    }

    /// Creates a 1x1 red CGImage for testing
    static func make1x1Image() -> CGImage {
        makeImage(width: 1, height: 1)
    }

    /// Creates a solid-color CGImage of the given pixel size (red by default)
    static func makeImage(width: Int, height: Int, red: CGFloat = 1, green: CGFloat = 0, blue: CGFloat = 0) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
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

// MARK: - Fake Sleep Preventer

class FakeSleepPreventer: SleepPreventing {
    private(set) var beginCount = 0
    private(set) var endCount = 0
    private(set) var lastReason: String?
    private(set) var lastKeepDisplayAwake: Bool?
    private(set) var isPreventing = false
    /// One-shot failure switch for exercising assertion-creation failure.
    var failNextBegin = false

    func begin(reason: String, keepDisplayAwake: Bool) -> Bool {
        guard !isPreventing else { return true }
        if failNextBegin {
            failNextBegin = false
            return false
        }
        isPreventing = true
        beginCount += 1
        lastReason = reason
        lastKeepDisplayAwake = keepDisplayAwake
        return true
    }

    func end() {
        guard isPreventing else { return }
        isPreventing = false
        endCount += 1
    }
}
