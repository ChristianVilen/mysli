import Cocoa

class ThumbnailPanel: NSPanel {
    var onEdit: (() -> Void)?
    var onDismiss: (() -> Void)?
    private var dismissTimer: Timer?

    init(image: NSImage, screen: NSScreen, duration: TimeInterval = 5.0) {
        let thumbWidth: CGFloat = 200
        let aspect = image.size.height / image.size.width
        let thumbHeight = thumbWidth * aspect
        let padding: CGFloat = 16

        let frame = NSRect(
            x: screen.visibleFrame.maxX - thumbWidth - padding,
            y: screen.visibleFrame.minY + padding,
            width: thumbWidth,
            height: thumbHeight
        )

        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))

        let imageView = NSImageView(frame: container.bounds)
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 8
        imageView.layer?.masksToBounds = true
        container.addSubview(imageView)

        let closeSize: CGFloat = 20
        let closeButton = NSButton(frame: NSRect(x: frame.width - closeSize - 4, y: frame.height - closeSize - 4, width: closeSize, height: closeSize))
        closeButton.bezelStyle = .circular
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(dismissThumbnail)
        container.addSubview(closeButton)

        contentView = container

        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(thumbnailClicked))
        imageView.addGestureRecognizer(clickGesture)

        if duration > 0 {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.dismissThumbnail()
            }
        }
    }

    @objc private func thumbnailClicked() {
        dismissTimer?.invalidate()
        orderOut(nil)
        onEdit?()
    }

    @objc private func dismissThumbnail() {
        dismissTimer?.invalidate()
        orderOut(nil)
        onDismiss?()
    }
}
