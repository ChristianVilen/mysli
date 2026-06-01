import Cocoa

class ThumbnailPanel: FloatingPanel {
    var onEdit: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onDelete: (() -> Void)?
    private var dismissTimer: Timer?

    static let thumbWidth: CGFloat = 200
    static let padding: CGFloat = 16
    static let gap: CGFloat = 36

    static func thumbSize(for image: NSImage) -> NSSize {
        let aspect = image.size.height / image.size.width
        return NSSize(width: thumbWidth, height: thumbWidth * aspect)
    }

    /// Produce a small bitmap-backed copy of `image` at `size` (rendered at 2×
    /// for Retina crispness) so the panel doesn't hold the full capture.
    static func downscaled(_ image: NSImage, to size: NSSize) -> NSImage {
        let scale: CGFloat = 2
        let pixelsWide = Int((size.width * scale).rounded())
        let pixelsHigh = Int((size.height * scale).rounded())
        guard pixelsWide > 0, pixelsHigh > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            return image
        }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        let thumb = NSImage(size: size)
        thumb.addRepresentation(rep)
        return thumb
    }

    /// Frame-based init for use by ThumbnailStackManager
    init(image: NSImage, frame: NSRect) {
        super.init(contentRect: frame)
        setupPanel(image: image, size: frame.size)
    }

    private func setupPanel(image: NSImage, size: NSSize) {
        let container = NSView(frame: NSRect(origin: .zero, size: size))

        let imageView = NSImageView(frame: container.bounds)
        // Render a small bitmap for display so the panel doesn't retain the
        // full-resolution capture (those are kept by the thumbnail stack only).
        imageView.image = Self.downscaled(image, to: size)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 8
        imageView.layer?.masksToBounds = true
        container.addSubview(imageView)

        let closeSize: CGFloat = 20
        let closeButton = NSButton(frame: NSRect(x: size.width - closeSize - 4, y: size.height - closeSize - 4, width: closeSize, height: closeSize))
        closeButton.bezelStyle = .circular
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(dismissThumbnail)
        container.addSubview(closeButton)

        let deleteButton = NSButton(frame: NSRect(x: 4, y: size.height - closeSize - 4, width: closeSize, height: closeSize))
        deleteButton.bezelStyle = .circular
        deleteButton.image = NSImage(systemSymbolName: "trash.circle.fill", accessibilityDescription: "Delete")
        deleteButton.isBordered = false
        deleteButton.target = self
        deleteButton.action = #selector(deleteThumbnail)
        container.addSubview(deleteButton)

        contentView = container

        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(thumbnailClicked))
        imageView.addGestureRecognizer(clickGesture)
    }

    func startDismissTimer(duration: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.dismissThumbnail()
        }
    }

    func cancelDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }

    // Notify only — ThumbnailStackManager.remove(panel:) owns timer cancellation,
    // closing, and removal from the stack.
    @objc private func thumbnailClicked() { onEdit?() }
    @objc private func dismissThumbnail() { onDismiss?() }
    @objc private func deleteThumbnail() { onDelete?() }
}
