import Cocoa

/// Sits over the editor's DrawingView and shows the crop box: the area
/// outside the box is dimmed, the box has a border and a size label in
/// output pixels, and while editing it has eight drag handles. When not
/// editing, the view lets mouse events through to the DrawingView below.
class CropOverlayView: NSView {
    static let handleSide: CGFloat = 8

    /// Pixel size of the whole image, for the size label.
    private let imagePixelSize: CGSize
    private var box: CropBox

    /// True while the Crop tool is on: mouse events shape the box and the
    /// handles are drawn. False: the box is only shown.
    var isEditing = false {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    /// The crop box in this view's coordinates; nil when there is none.
    var cropRect: CGRect? {
        get { box.rect }
        set {
            box = CropBox(bounds: bounds, rect: newValue)
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    init(frame: NSRect, imagePixelSize: CGSize) {
        self.imagePixelSize = imagePixelSize
        // The bounds never change: the editor window is not resizable.
        box = CropBox(bounds: NSRect(origin: .zero, size: frame.size))
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Only the Crop tool owns the mouse; otherwise clicks go to the view below.
    override func hitTest(_ point: NSPoint) -> NSView? {
        isEditing ? super.hitTest(point) : nil
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        guard isEditing else { return }
        box.beginDrag(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
        // A draw press drops the old box at once, so the open-hand and edge
        // cursor rects are stale from here until mouseUp rebuilds them.
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEditing else { return }
        box.drag(to: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isEditing else { return }
        box.endDrag()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    // MARK: - Cursors

    override func resetCursorRects() {
        guard isEditing else { return }
        addCursorRect(bounds, cursor: .crosshair)
        guard let rect = box.rect else { return }
        addCursorRect(rect, cursor: .openHand)

        // Edge bands get resize arrows. Corners keep the crosshair: AppKit
        // has no public diagonal resize cursor.
        let radius = CropBox.handleHitRadius
        let vertical = NSSize(width: 2 * radius, height: rect.height - 2 * radius)
        let horizontal = NSSize(width: rect.width - 2 * radius, height: 2 * radius)
        if vertical.height > 0 {
            addCursorRect(NSRect(origin: NSPoint(x: rect.minX - radius, y: rect.minY + radius), size: vertical), cursor: .resizeLeftRight)
            addCursorRect(NSRect(origin: NSPoint(x: rect.maxX - radius, y: rect.minY + radius), size: vertical), cursor: .resizeLeftRight)
        }
        if horizontal.width > 0 {
            addCursorRect(NSRect(origin: NSPoint(x: rect.minX + radius, y: rect.minY - radius), size: horizontal), cursor: .resizeUpDown)
            addCursorRect(NSRect(origin: NSPoint(x: rect.minX + radius, y: rect.maxY - radius), size: horizontal), cursor: .resizeUpDown)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let rect = box.rect else { return }

        // Dim everything outside the box
        let dimPath = NSBezierPath(rect: bounds)
        dimPath.appendRect(rect)
        dimPath.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.4).setFill()
        dimPath.fill()

        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1.5
        border.stroke()

        if isEditing { drawHandles(around: rect) }
        drawSizeLabel(for: rect)
    }

    private func drawHandles(around rect: NSRect) {
        let side = Self.handleSide
        NSColor.white.setFill()
        NSColor.black.withAlphaComponent(0.6).setStroke()
        for x in [rect.minX, rect.midX, rect.maxX] {
            for y in [rect.minY, rect.midY, rect.maxY] where !(x == rect.midX && y == rect.midY) { // no handle in the centre
                let handle = NSRect(x: x - side / 2, y: y - side / 2, width: side, height: side)
                handle.fill()
                let outline = NSBezierPath(rect: handle)
                outline.lineWidth = 1
                outline.stroke()
            }
        }
    }

    /// Output size in pixels, in the shared SizeLabel style.
    private func drawSizeLabel(for rect: NSRect) {
        let pixels = DrawingView.pixelRect(for: rect, in: bounds, imagePixelSize: imagePixelSize)
        let text = "\(Int(pixels.width)) × \(Int(pixels.height))"
        let size = (text as NSString).size(withAttributes: SizeLabel.attributes)
        // Below the box; inside its bottom edge when there is no room below.
        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 6)
        if origin.y < bounds.minY { origin.y = rect.minY + 6 }
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
        (text as NSString).draw(at: origin, withAttributes: SizeLabel.attributes)
    }
}
