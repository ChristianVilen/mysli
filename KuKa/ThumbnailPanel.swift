import Cocoa

class ThumbnailPanel: NSPanel {
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

    /// Frame-based init for use by ThumbnailStackManager
    init(image: NSImage, frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setupPanel(image: image, size: frame.size)
    }

    private func setupPanel(image: NSImage, size: NSSize) {
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let container = NSView(frame: NSRect(origin: .zero, size: size))

        let imageView = NSImageView(frame: container.bounds)
        imageView.image = image
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

    @objc private func thumbnailClicked() {
        cancelDismissTimer()
        orderOut(nil)
        onEdit?()
    }

    @objc private func dismissThumbnail() {
        cancelDismissTimer()
        orderOut(nil)
        onDismiss?()
    }

    @objc private func deleteThumbnail() {
        cancelDismissTimer()
        orderOut(nil)
        onDelete?()
    }
}
