import Cocoa

class DrawingView: NSView {
    private let image: NSImage
    private var strokes: [NSBezierPath] = []
    private var currentStroke: NSBezierPath?

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    func undo() {
        if !strokes.isEmpty {
            strokes.removeLast()
            needsDisplay = true
        }
    }

    func compositeImage() -> NSImage {
        let size = image.size
        let result = NSImage(size: size)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))

        let scaleX = size.width / bounds.width
        let scaleY = size.height / bounds.height

        NSColor.red.setStroke()
        for stroke in strokes {
            let scaled = stroke.copy() as! NSBezierPath
            let transform = AffineTransform(scaleByX: scaleX, byY: scaleY)
            scaled.transform(using: transform)
            scaled.lineWidth = 3 * scaleX
            scaled.lineCapStyle = .round
            scaled.lineJoinStyle = .round
            scaled.stroke()
        }
        result.unlockFocus()
        return result
    }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds)

        NSColor.red.setStroke()
        for stroke in strokes {
            stroke.lineWidth = 3
            stroke.lineCapStyle = .round
            stroke.lineJoinStyle = .round
            stroke.stroke()
        }
        if let current = currentStroke {
            current.lineWidth = 3
            current.lineCapStyle = .round
            current.lineJoinStyle = .round
            current.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let path = NSBezierPath()
        path.move(to: point)
        currentStroke = path
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        currentStroke?.line(to: point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let stroke = currentStroke {
            strokes.append(stroke)
            currentStroke = nil
        }
    }
}
