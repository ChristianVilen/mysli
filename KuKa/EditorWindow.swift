import Cocoa

class EditorWindow: NSPanel, NSWindowDelegate {
    /// Narrower content can't fit the four toolbar buttons with 8 pt gaps
    /// (Undo 12–92, Crop 100–180, trash centred at 190–270, Done 368–448);
    /// smaller images are centered in a window of this width.
    static let minimumContentWidth: CGFloat = 460

    var onClose: (() -> Void)?
    private let drawingView: DrawingView
    private let cropOverlay: CropOverlayView
    private let fileURL: URL
    private let store: ImageStoring

    /// The crop box in image-view coordinates; nil when there is none.
    var cropRect: CGRect? {
        get { cropOverlay.cropRect }
        set { cropOverlay.cropRect = newValue }
    }

    init(image: NSImage, fileURL: URL, store: ImageStoring, screens: Screens = SystemScreens()) {
        drawingView = DrawingView(image: image)
        self.fileURL = fileURL
        self.store = store

        // Size to fit image, capped at 80% of screen (uncapped without screens)
        var w = image.size.width
        var h = image.size.height
        if let visible = screens.mainOrPrimary?.visibleFrame {
            let maxW = visible.width * 0.8
            let maxH = visible.height * 0.8
            let aspect = image.size.width / image.size.height
            w = min(image.size.width, maxW)
            h = w / aspect
            if h > maxH {
                h = maxH
                w = h * aspect
            }
        }

        let toolbarHeight: CGFloat = 44
        let contentWidth = max(w, Self.minimumContentWidth)
        let imageFrame = NSRect(x: (contentWidth - w) / 2, y: toolbarHeight, width: w, height: h)
        cropOverlay = CropOverlayView(frame: imageFrame, imagePixelSize: drawingView.imagePixelSize)
        let contentRect = NSRect(x: 0, y: 0, width: contentWidth, height: h + toolbarHeight)

        super.init(contentRect: contentRect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "Edit Screenshot"
        isReleasedWhenClosed = false
        delegate = self

        let container = NSView(frame: NSRect(origin: .zero, size: contentRect.size))

        // Toolbar at bottom
        let toolbar = NSView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: toolbarHeight))

        let undoButton = NSButton(title: "Undo", target: self, action: #selector(undoStroke))
        undoButton.bezelStyle = .rounded
        undoButton.frame = NSRect(x: 12, y: 8, width: 80, height: 28)
        toolbar.addSubview(undoButton)

        let cropButton = NSButton(title: "Crop", target: self, action: #selector(cropTapped(_:)))
        cropButton.setButtonType(.pushOnPushOff)
        cropButton.bezelStyle = .rounded
        cropButton.frame = NSRect(x: 100, y: 8, width: 80, height: 28)
        toolbar.addSubview(cropButton)

        let deleteButton = NSButton(frame: NSRect(x: (contentWidth - 80) / 2, y: 8, width: 80, height: 28))
        deleteButton.bezelStyle = .rounded
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        toolbar.addSubview(deleteButton)

        let doneButton = NSButton(title: "Done", target: self, action: #selector(doneTapped))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.frame = NSRect(x: contentWidth - 92, y: 8, width: 80, height: 28)
        toolbar.addSubview(doneButton)

        container.addSubview(toolbar)

        drawingView.frame = imageFrame
        container.addSubview(drawingView)
        // Above the drawing view; it passes clicks through while Crop is off.
        container.addSubview(cropOverlay)

        contentView = container
        center()
    }

    @objc private func undoStroke() {
        drawingView.undo()
    }

    @objc private func cropTapped(_ sender: NSButton) {
        cropOverlay.isEditing = sender.state == .on
    }

    @objc func doneTapped() {
        store.saveAnnotated(image: drawingView.compositeImage(croppedTo: cropRect), to: fileURL)
        close()
    }

    @objc func deleteTapped() {
        store.delete(at: fileURL)
        close()
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    func windowWillClose(_ notification: Notification) {
        // Fires for Done/Delete, the title-bar close button, and Escape —
        // the single place the owner drops its reference so the window
        // (and its full-resolution image) can deallocate.
        onClose?()
    }
}
