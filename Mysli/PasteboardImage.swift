import Cocoa

/// The one rule for putting a captured or recorded image on a pasteboard:
/// PNG always, and a TIFF representation alongside it only while the image
/// is small enough for the transient uncompressed buffer to be cheap.
///
/// Neutral, feature-free namespace on purpose. Both the screenshot store
/// (`ImageStore`) and the clipboard-history adapter (`SystemPasteboard`)
/// write images to `NSPasteboard.general`, and before this existed each one
/// carried its own copy of the threshold rule — with the clipboard side
/// reaching into `ImageStore` for the number.
enum PasteboardImage {
    /// Images above this pixel count go on the pasteboard as PNG only. An
    /// uncompressed TIFF costs ~4 bytes per pixel of transient allocation,
    /// and every modern app reads PNG from the pasteboard.
    static let defaultTIFFMaxPixels = 30_000_000

    /// The TIFF flavor to write next to the PNG, or nil when the image is
    /// over `maxPixels` and PNG alone should go on the pasteboard.
    ///
    /// The encode is pooled: `representation(using:)` hands back a full
    /// image-sized buffer, and pooling returns those pages promptly rather
    /// than waiting for the run loop's own autorelease pool to drain.
    static func tiffFlavor(for bitmap: NSBitmapImageRep, maxPixels: Int) -> Data? {
        guard bitmap.pixelsWide * bitmap.pixelsHigh <= maxPixels else { return nil }
        return autoreleasepool { bitmap.representation(using: .tiff, properties: [:]) }
    }
}
