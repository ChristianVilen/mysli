import Cocoa
import ScreenCaptureKit
import UniformTypeIdentifiers

// MARK: - Protocols

protocol FileManaging {
    var homeDirectoryForCurrentUser: URL { get }
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]?) throws
    func writeImageData(_ data: Data, to url: URL) throws
    func removeItem(at url: URL) throws
}

protocol ClipboardManaging {
    func copyImage(tiffData: Data?, pngData: Data)
    func clearClipboard()
}

protocol ScreenCapturing {
    func captureScreen(rect: CGRect) async -> CGImage?
    func captureWindow(windowID: CGWindowID) async -> CGImage?
}

// MARK: - Real Implementations

extension FileManager: FileManaging {
    func writeImageData(_ data: Data, to url: URL) throws {
        try data.write(to: url)
    }
}

class SystemClipboard: ClipboardManaging {
    func copyImage(tiffData: Data?, pngData: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let tiffData {
            pb.setData(tiffData, forType: .tiff)
        }
        pb.setData(pngData, forType: .png)
    }

    func clearClipboard() {
        NSPasteboard.general.clearContents()
    }
}

// MARK: - MemoryReclaim

enum MemoryReclaim {
    /// Ask libmalloc to return freed pages to the OS. Captures and combines
    /// churn through image-sized buffers (raster, TIFF, PNG); once freed the
    /// allocator keeps those pages as dirty cache, which Activity Monitor
    /// counts as app memory. Scheduled with a delay so it runs after the
    /// buffers are actually released (autorelease pools drained, panels
    /// deallocated).
    static func schedule(afterSeconds delay: TimeInterval = 1.0) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            malloc_zone_pressure_relief(nil, 0)
        }
    }
}

class SystemScreenCapture: ScreenCapturing {
    /// `rect` is in CG global coordinates (top-left origin), same contract as
    /// the old CGWindowListCreateImage-based implementation.
    func captureScreen(rect: CGRect) async -> CGImage? {
        guard let content = await shareableContent() else { return nil }
        guard let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) })
                ?? content.displays.first else {
            NSLog("Ku-Ka: No display found for capture rect")
            return nil
        }

        let sourceRect = CGRect(
            x: rect.origin.x - display.frame.origin.x,
            y: rect.origin.y - display.frame.origin.y,
            width: rect.width,
            height: rect.height
        )
        return await capture(filter: SCContentFilter(display: display, excludingWindows: []),
                             sourceRect: sourceRect,
                             pointSize: sourceRect.size,
                             label: "Screen capture")
    }

    func captureWindow(windowID: CGWindowID) async -> CGImage? {
        guard let content = await shareableContent() else { return nil }
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            NSLog("Ku-Ka: Window \(windowID) not found for capture")
            return nil
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        return await capture(filter: filter,
                             sourceRect: nil,
                             pointSize: filter.contentRect.size,
                             label: "Window capture")
    }

    private func shareableContent() async -> SCShareableContent? {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            NSLog("Ku-Ka: Shareable content lookup failed: \(error)")
            return nil
        }
    }

    /// Shared capture policy: cursor-free, best resolution, pixel size derived
    /// from the filter's point-to-pixel scale.
    private func capture(filter: SCContentFilter, sourceRect: CGRect?, pointSize: CGSize, label: String) async -> CGImage? {
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        if let sourceRect {
            config.sourceRect = sourceRect
        }
        config.width = Int(pointSize.width * scale)
        config.height = Int(pointSize.height * scale)
        config.showsCursor = false
        config.captureResolution = .best

        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            NSLog("Ku-Ka: \(label) failed: \(error)")
            return nil
        }
    }
}

// MARK: - CaptureResult

struct CaptureResult {
    let image: NSImage
    let fileURL: URL
}

// MARK: - CaptureManager

class CaptureManager {
    /// Images above this pixel count go on the pasteboard as PNG only. An
    /// uncompressed TIFF costs ~4 bytes per pixel of transient allocation,
    /// and every modern app reads PNG from the pasteboard.
    static let defaultClipboardTIFFMaxPixels = 30_000_000

    let fileManager: FileManaging
    let clipboard: ClipboardManaging
    let screenCapture: ScreenCapturing
    let clipboardTIFFMaxPixels: Int

    init(fileManager: FileManaging = FileManager.default,
         clipboard: ClipboardManaging = SystemClipboard(),
         screenCapture: ScreenCapturing = SystemScreenCapture(),
         clipboardTIFFMaxPixels: Int = CaptureManager.defaultClipboardTIFFMaxPixels) {
        self.fileManager = fileManager
        self.clipboard = clipboard
        self.screenCapture = screenCapture
        self.clipboardTIFFMaxPixels = clipboardTIFFMaxPixels
    }

    func captureFullScreen(screen: NSScreen) async -> CaptureResult? {
        let screenFrame = screen.frame
        let primaryHeight = NSScreen.screens[0].frame.height
        let cgRect = CGRect(
            x: screenFrame.origin.x,
            y: primaryHeight - screenFrame.origin.y - screenFrame.height,
            width: screenFrame.width,
            height: screenFrame.height
        )

        guard let cgImage = await screenCapture.captureScreen(rect: cgRect) else {
            NSLog("Ku-Ka: Full screen capture returned nil")
            return nil
        }

        return finalize(cgImage: cgImage, fileName: generateFileName())
    }

    func captureWindow(windowID: CGWindowID) async -> CaptureResult? {
        guard let cgImage = await screenCapture.captureWindow(windowID: windowID) else {
            NSLog("Ku-Ka: Window capture returned nil")
            return nil
        }
        return finalize(cgImage: cgImage, fileName: generateFileName())
    }

    func capture(rect: CGRect, screen: NSScreen) async -> CaptureResult? {
        let screenFrame = screen.frame
        let cgRect = CGRect(
            x: screenFrame.origin.x + rect.origin.x,
            y: screenFrame.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        guard let cgImage = await screenCapture.captureScreen(rect: cgRect) else {
            NSLog("Ku-Ka: Screen capture returned nil")
            return nil
        }

        return finalize(cgImage: cgImage, fileName: generateFileName())
    }

    /// Build the NSImage, persist, and copy to clipboard for a freshly captured
    /// CGImage. Clipboard data is generated from the CGImage in an autorelease
    /// pool so the long-lived NSImage never caches an uncompressed TIFF rep.
    private func finalize(cgImage: CGImage, fileName: String) -> CaptureResult {
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let fileURL = saveToDisk(cgImage: cgImage, fileName: fileName)
        copyToClipboard(cgImage: cgImage)
        MemoryReclaim.schedule()
        return CaptureResult(image: image, fileURL: fileURL)
    }

    func saveAnnotated(image: NSImage, to url: URL) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        autoreleasepool {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try? fileManager.writeImageData(png, to: url)
            }
        }
        copyToClipboard(cgImage: cgImage)
        MemoryReclaim.schedule()
    }

    func copyToClipboard(cgImage: CGImage) {
        autoreleasepool {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
            let tiff: Data? = cgImage.width * cgImage.height <= clipboardTIFFMaxPixels
                ? bitmap.representation(using: .tiff, properties: [:])
                : nil
            clipboard.copyImage(tiffData: tiff, pngData: png)
        }
    }

    func screenshotsDirectory() -> URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Screenshots")
    }

    private func dateString(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'_at_'HH-mm-ss"
        return formatter.string(from: date)
    }

    func generateFileName(for date: Date = Date()) -> String {
        "Screenshot_\(dateString(for: date)).png"
    }

    func generateCombinedFileName(for date: Date = Date()) -> String {
        "Screenshot_\(dateString(for: date))_combined.png"
    }

    /// Stack two captures vertically, composited in a CGBitmapContext at the
    /// sources' pixel dimensions. Composing via NSImage.lockFocus would
    /// re-render at the screen's backing scale, doubling the pixel size on
    /// every combine (exponentially for repeated combines).
    func saveCombined(topImage: NSImage, bottomImage: NSImage) -> CaptureResult? {
        guard let topCG = topImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let bottomCG = bottomImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let width = max(topCG.width, bottomCG.width)
        let height = topCG.height + bottomCG.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: topCG.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.draw(bottomCG, in: CGRect(x: 0, y: 0, width: bottomCG.width, height: bottomCG.height))
        context.draw(topCG, in: CGRect(x: 0, y: bottomCG.height, width: topCG.width, height: topCG.height))

        guard let combined = context.makeImage() else { return nil }
        return finalize(cgImage: combined, fileName: generateCombinedFileName())
    }

    func deleteScreenshot(at url: URL) {
        try? fileManager.removeItem(at: url)
        clipboard.clearClipboard()
    }

    private func saveToDisk(cgImage: CGImage, fileName: String) -> URL {
        let dir = screenshotsDirectory()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)

        let url = dir.appendingPathComponent(fileName)

        autoreleasepool {
            let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
            if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                try? fileManager.writeImageData(pngData, to: url)
            }
        }
        return url
    }

}
