import Cocoa

class SelectionView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var origin: NSPoint = .zero
    private var selectionRect: NSRect = .zero
    private var isDragging = false

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { NSCursor.crosshair.push() }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } // Escape
    }

    override func mouseDown(with event: NSEvent) {
        origin = convert(event.locationInWindow, from: nil)
        selectionRect = .zero
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)
        selectionRect = NSRect(
            x: min(origin.x, current.x),
            y: min(origin.y, current.y),
            width: abs(current.x - origin.x),
            height: abs(current.y - origin.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        guard selectionRect.width > 1, selectionRect.height > 1 else {
            onCancel?()
            return
        }
        onSelection?(selectionRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dimmed background
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        guard isDragging, selectionRect.width > 0 else { return }

        // Clear the selected area
        NSColor.clear.setFill()
        selectionRect.fill(using: .copy)

        // Selection border
        NSColor.white.withAlphaComponent(0.8).setStroke()
        let path = NSBezierPath(rect: selectionRect)
        path.lineWidth = 1.5
        path.stroke()

        // Dimensions label
        let text = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.7)
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let labelOrigin = NSPoint(
            x: selectionRect.midX - size.width / 2,
            y: selectionRect.minY - size.height - 6
        )
        (text as NSString).draw(at: labelOrigin, withAttributes: attrs)
    }
}
