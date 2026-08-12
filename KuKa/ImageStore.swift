import Cocoa

// MARK: - Protocols

protocol FileManaging {
    var homeDirectoryForCurrentUser: URL { get }
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]?) throws
    func writeImageData(_ data: Data, to url: URL) throws
    func removeItem(at url: URL) throws
    func fileExists(at url: URL) -> Bool
}

protocol ClipboardManaging {
    func copyImage(tiffData: Data?, pngData: Data)
    func clearClipboard()
}

// MARK: - Real Implementations

extension FileManager: FileManaging {
    func writeImageData(_ data: Data, to url: URL) throws {
        try data.write(to: url)
    }

    func fileExists(at url: URL) -> Bool {
        fileExists(atPath: url.path)
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

// MARK: - ImageStore

/// Test seam for modules that persist or remove stored screenshots.
protocol ImageStoring {
    func store(cgImage: CGImage) -> CaptureResult
    func storeCombined(top: NSImage, bottom: NSImage) -> CaptureResult?
    func saveAnnotated(image: NSImage, to url: URL)
    func delete(at url: URL)
}

/// Owns everything that happens to a produced image: disk writes, clipboard,
/// file naming, the Screenshots directory, and handing freed memory back to
/// the OS after each persistence moment.
final class ImageStore: ImageStoring {
    /// Images above this pixel count go on the pasteboard as PNG only. An
    /// uncompressed TIFF costs ~4 bytes per pixel of transient allocation,
    /// and every modern app reads PNG from the pasteboard.
    static let defaultClipboardTIFFMaxPixels = 30_000_000

    let fileManager: FileManaging
    let clipboard: ClipboardManaging
    let clipboardTIFFMaxPixels: Int
    private let now: () -> Date
    /// The stored file whose image was last copied to the clipboard. Deleting
    /// any other file leaves the clipboard alone.
    private var lastCopiedURL: URL?

    init(fileManager: FileManaging = FileManager.default,
         clipboard: ClipboardManaging = SystemClipboard(),
         clipboardTIFFMaxPixels: Int = ImageStore.defaultClipboardTIFFMaxPixels,
         now: @escaping () -> Date = { Date() }) {
        self.fileManager = fileManager
        self.clipboard = clipboard
        self.clipboardTIFFMaxPixels = clipboardTIFFMaxPixels
        self.now = now
    }

    /// Persist a freshly captured CGImage: build the NSImage, write to disk,
    /// copy to clipboard. Clipboard data is generated from the CGImage in an
    /// autorelease pool so the long-lived NSImage never caches an
    /// uncompressed TIFF rep.
    func store(cgImage: CGImage) -> CaptureResult {
        store(cgImage: cgImage, fileName: generateFileName(for: now()))
    }

    /// Stack two captures vertically, composited in a CGBitmapContext at the
    /// sources' pixel dimensions. Composing via NSImage.lockFocus would
    /// re-render at the screen's backing scale, doubling the pixel size on
    /// every combine (exponentially for repeated combines).
    func storeCombined(top: NSImage, bottom: NSImage) -> CaptureResult? {
        guard let topCG = top.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let bottomCG = bottom.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

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
        return store(cgImage: combined, fileName: generateCombinedFileName(for: now()))
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
        lastCopiedURL = url
        MemoryReclaim.schedule()
    }

    func delete(at url: URL) {
        try? fileManager.removeItem(at: url)
        if url == lastCopiedURL {
            clipboard.clearClipboard()
            lastCopiedURL = nil
        }
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

    func generateFileName(for date: Date = Date()) -> String {
        "Screenshot_\(dateString(for: date)).png"
    }

    func generateCombinedFileName(for date: Date = Date()) -> String {
        "Screenshot_\(dateString(for: date))_combined.png"
    }

    // MARK: - Private

    private func store(cgImage: CGImage, fileName: String) -> CaptureResult {
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let fileURL = saveToDisk(cgImage: cgImage, fileName: fileName)
        copyToClipboard(cgImage: cgImage)
        lastCopiedURL = fileURL
        MemoryReclaim.schedule()
        return CaptureResult(image: image, fileURL: fileURL)
    }

    /// File names have one-second resolution, so rapid captures can collide;
    /// append -2, -3, … until the name is free instead of overwriting.
    private func uniqueURL(for fileName: String, in dir: URL) -> URL {
        var url = dir.appendingPathComponent(fileName)
        guard fileManager.fileExists(at: url) else { return url }

        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var counter = 2
        repeat {
            url = dir.appendingPathComponent("\(base)-\(counter).\(ext)")
            counter += 1
        } while fileManager.fileExists(at: url)
        return url
    }

    private func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'_at_'HH-mm-ss"
        return formatter.string(from: date)
    }

    private func saveToDisk(cgImage: CGImage, fileName: String) -> URL {
        let dir = screenshotsDirectory()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)

        let url = uniqueURL(for: fileName, in: dir)

        autoreleasepool {
            let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
            if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                try? fileManager.writeImageData(pngData, to: url)
            }
        }
        return url
    }
}
