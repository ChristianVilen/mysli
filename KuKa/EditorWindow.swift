import Cocoa

class EditorWindow: NSPanel, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let drawingView: DrawingView
    private let fileURL: URL
    private let store: ImageStoring

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
        let contentRect = NSRect(x: 0, y: 0, width: w, height: h + toolbarHeight)

        super.init(contentRect: contentRect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "Annotate Screenshot"
        isReleasedWhenClosed = false
        delegate = self

        let container = NSView(frame: NSRect(origin: .zero, size: contentRect.size))

        // Toolbar at bottom
        let toolbar = NSView(frame: NSRect(x: 0, y: 0, width: w, height: toolbarHeight))

        let undoButton = NSButton(title: "Undo", target: self, action: #selector(undoStroke))
        undoButton.bezelStyle = .rounded
        undoButton.frame = NSRect(x: 12, y: 8, width: 80, height: 28)
        toolbar.addSubview(undoButton)

        let deleteButton = NSButton(frame: NSRect(x: (w - 80) / 2, y: 8, width: 80, height: 28))
        deleteButton.bezelStyle = .rounded
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        toolbar.addSubview(deleteButton)

        let doneButton = NSButton(title: "Done", target: self, action: #selector(doneTapped))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.frame = NSRect(x: w - 92, y: 8, width: 80, height: 28)
        toolbar.addSubview(doneButton)

        container.addSubview(toolbar)

        drawingView.frame = NSRect(x: 0, y: toolbarHeight, width: w, height: h)
        container.addSubview(drawingView)

        contentView = container
        center()
    }

    @objc private func undoStroke() {
        drawingView.undo()
    }

    @objc func doneTapped() {
        store.saveAnnotated(image: drawingView.compositeImage(), to: fileURL)
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
