import Cocoa

class SelectionView: NSView {
    enum Mode { case selection, windowCapture }

    var onSelection: ((CGRect) -> Void)?
    var onWindowSelection: ((CGWindowID) -> Void)?
    var onCancel: (() -> Void)?
    var windowListProvider: WindowListProvider = CGWindowListProvider()

    private(set) var mode: Mode = .selection
    private var origin: NSPoint = .zero
    private var selectionRect: NSRect = .zero
    private var isDragging = false
    private var windows: [WindowInfo] = []
    private var highlightedWindow: WindowInfo?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: mode == .selection ? .crosshair : Self.cameraCursor)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { NSCursor.crosshair.push() }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        } else if event.keyCode == 49 { // Space
            toggleMode()
        }
    }

    private func toggleMode() {
        if mode == .selection {
            mode = .windowCapture
            isDragging = false
            selectionRect = .zero
            windows = windowListProvider.windowsOnScreen()
            setupTrackingArea()
            NSCursor.pop()
            Self.cameraCursor.push()
        } else {
            mode = .selection
            highlightedWindow = nil
            windows = []
            removeTrackingArea()
            NSCursor.pop()
            NSCursor.crosshair.push()
        }
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    // MARK: - Tracking Area

    private func setupTrackingArea() {
        removeTrackingArea()
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    private func removeTrackingArea() {
        if let area = trackingArea { removeTrackingArea(area); trackingArea = nil }
    }

    // MARK: - Mouse (selection mode)

    override func mouseDown(with event: NSEvent) {
        guard mode == .selection else { return }
        origin = convert(event.locationInWindow, from: nil)
        selectionRect = .zero
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .selection else { return }
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
        if mode == .windowCapture {
            if let win = highlightedWindow { onWindowSelection?(win.windowID) }
            return
        }
        isDragging = false
        guard selectionRect.width > 1, selectionRect.height > 1 else {
            onCancel?()
            return
        }
        onSelection?(selectionRect)
    }

    // MARK: - Mouse (window mode)

    override func mouseMoved(with event: NSEvent) {
        guard mode == .windowCapture else { return }
        let screenPoint = NSEvent.mouseLocation
        highlightedWindow = windows.first { $0.frame.contains(screenPoint) }
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        if mode == .windowCapture {
            drawWindowHighlight()
            return
        }

        guard isDragging, selectionRect.width > 0 else { return }

        NSColor.clear.setFill()
        selectionRect.fill(using: .copy)

        NSColor.white.withAlphaComponent(0.8).setStroke()
        let path = NSBezierPath(rect: selectionRect)
        path.lineWidth = 1.5
        path.stroke()

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

    private func drawWindowHighlight() {
        guard let win = highlightedWindow, let screen = window?.screen else { return }
        // Convert NS screen coords to view coords
        let viewRect = NSRect(
            x: win.frame.origin.x - screen.frame.origin.x,
            y: win.frame.origin.y - screen.frame.origin.y,
            width: win.frame.width,
            height: win.frame.height
        )
        NSColor.systemBlue.withAlphaComponent(0.2).setFill()
        viewRect.fill()
        NSColor.systemBlue.withAlphaComponent(0.5).setStroke()
        let path = NSBezierPath(rect: viewRect)
        path.lineWidth = 2
        path.stroke()
    }

    // MARK: - Camera Cursor

    private static let cameraCursor: NSCursor = {
        if let img = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "Window capture") {
            let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .regular)
            let configured = img.withSymbolConfiguration(config) ?? img
            return NSCursor(image: configured, hotSpot: NSPoint(x: 12, y: 12))
        }
        return .crosshair
    }()
}
