import Cocoa
import ImageIO

/// Small, per-session thumbnails for the image rows in the clipboard panel.
/// Decodes at thumbnail size on demand and keeps only the small result: the
/// item's own PNG bytes belong to the controller's history, and nothing
/// full-size is ever built or kept here.
///
/// Keyed by content hash, which is what makes a row's thumbnail stable
/// across reloads. Sized from the history's own item cap: a smaller cache
/// would evict rows the list still shows, and arrowing through a history
/// full of images would re-decode on the main thread all the way down.
final class ClipboardThumbnailCache {
    private let cache = NSCache<NSString, NSImage>()
    private let box: NSSize

    init(box: NSSize = Metrics.thumbnailBox) {
        self.box = box
        cache.countLimit = ClipboardHistory.maxItems
    }

    /// The thumbnail for an image item, or nil for text and for bytes that
    /// fail to decode.
    func thumbnail(for item: ClipboardItem) -> NSImage? {
        guard case .image(let png, _) = item.kind else { return nil }
        let key = item.contentHash as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = Self.decode(png: png, fitting: box) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Thumbnails are per-session: a screenshot deleted between two openings
    /// of the panel must not come back from here.
    func removeAll() {
        cache.removeAllObjects()
    }

    private static func decode(png: Data, fitting box: NSSize) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil) else { return nil }
        // 2× the box keeps the thumbnail crisp on Retina. ImageIO decodes
        // straight to this size, so the full-resolution bitmap is never
        // created in the first place.
        let maxPixelSize = Int(max(box.width, box.height) * 2)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let scale = min(box.width / pixelWidth, box.height / pixelHeight)
        let displaySize = NSSize(
            width: max((pixelWidth * scale).rounded(), 1),
            height: max((pixelHeight * scale).rounded(), 1)
        )
        return NSImage(cgImage: cgImage, size: displaySize)
    }
}
