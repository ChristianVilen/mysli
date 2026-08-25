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
/// the OS after each persistence moment. It also tracks content hashes per
/// saved file and reports them on deletion.
final class ImageStore: ImageStoring {
    let fileManager: FileManaging
    let clipboard: ClipboardManaging
    let clipboardTIFFMaxPixels: Int
    private let now: () -> Date
    /// The stored file whose image was last copied to the clipboard. Deleting
    /// any other file leaves the clipboard alone.
    private var lastCopiedURL: URL?
    /// Content hashes (via the shared `ContentHash`) of every PNG
    /// this session copied to the clipboard for a given file URL — a set,
    /// not a single value, because `saveAnnotated` re-saving to an existing
    /// URL adds a hash rather than replacing one: the pre-annotation capture
    /// is almost always already its own clipboard-history row by the time
    /// annotating finishes, so deleting the file must report both hashes or
    /// the original row is orphaned. Session-scoped: an entry accumulates
    /// until its URL is deleted (same accepted trade-off as
    /// `WindowTilingController.savedFrames`).
    private var contentHashes: [URL: Set<String>] = [:]
    /// Fires with a content hash of a deleted file's clipboard bytes, so a
    /// caller (AppDelegate) can drop the matching clipboard-history entry.
    /// Fires once per recorded hash — a file annotated after capture reports
    /// two. Not called when the deleted URL was never stored or re-saved
    /// here.
    ///
    /// Typed `@MainActor` so the rule is checked rather than commented: the
    /// consumer is main-actor state, and `delete(at:)` is only ever reached
    /// from the thumbnail stack and the editor, both on the main thread.
    /// `delete(at:)` states that assumption once, in `assumeIsolated`,
    /// instead of leaving each consumer to make it again.
    var onDeletedHash: (@MainActor (String) -> Void)?

    init(fileManager: FileManaging = FileManager.default,
         clipboard: ClipboardManaging = SystemClipboard(),
         clipboardTIFFMaxPixels: Int = PasteboardImage.defaultTIFFMaxPixels,
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
        writeAndCopy(cgImage: cgImage, to: url)
        lastCopiedURL = url
        MemoryReclaim.schedule()
    }

    func delete(at url: URL) {
        try? fileManager.removeItem(at: url)
        if url == lastCopiedURL {
            clipboard.clearClipboard()
            lastCopiedURL = nil
        }
        if let hashes = contentHashes.removeValue(forKey: url), let onDeletedHash {
            // See `onDeletedHash`: delete(at:) runs on the main thread, but
            // ImageStore isn't @MainActor, so the compiler can't see it.
            MainActor.assumeIsolated {
                hashes.forEach(onDeletedHash)
            }
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
        let fileURL = destinationURL(for: fileName)

        writeAndCopy(cgImage: cgImage, to: fileURL)
        lastCopiedURL = fileURL
        MemoryReclaim.schedule()
        return CaptureResult(image: image, fileURL: fileURL)
    }

    /// Ensures the Screenshots directory exists and picks a free file name
    /// in it.
    private func destinationURL(for fileName: String) -> URL {
        let dir = screenshotsDirectory()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return uniqueURL(for: fileName, in: dir)
    }

    /// Encodes a CGImage to PNG exactly once, writes those bytes to disk,
    /// copies them (plus an optional TIFF rep) to the clipboard, and adds
    /// their content hash to the set recorded against `url`. Two independent NSBitmapImageRep
    /// PNG encodings of the same CGImage are not guaranteed byte-identical,
    /// and the hash that matters is the one for the bytes the clipboard
    /// received — the poller reads those back into clipboard history — so
    /// disk and clipboard must share one encoding rather than each making
    /// their own.
    private func writeAndCopy(cgImage: CGImage, to url: URL) {
        autoreleasepool {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            // Exits the closure, not writeAndCopy itself — harmless today
            // since nothing follows this autoreleasepool call, but keep it
            // that way if you add code after it.
            guard let png = bitmap.representation(using: .png, properties: [:]) else { return }

            try? fileManager.writeImageData(png, to: url)
            contentHashes[url, default: []].insert(ContentHash.of(png))

            let tiff = PasteboardImage.tiffFlavor(for: bitmap, maxPixels: clipboardTIFFMaxPixels)
            clipboard.copyImage(tiffData: tiff, pngData: png)
        }
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
}
