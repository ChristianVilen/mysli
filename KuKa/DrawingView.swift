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

    /// Flatten the strokes onto the screenshot in a CGBitmapContext at the
    /// source's pixel dimensions. Compositing via NSImage.lockFocus would
    /// re-render at the screen's backing scale, doubling the pixel size.
    func compositeImage() -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                data: nil,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return image }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        let scaleX = CGFloat(cgImage.width) / bounds.width
        let scaleY = CGFloat(cgImage.height) / bounds.height

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor.red.setStroke()
        for stroke in strokes {
            let scaled = stroke.copy() as! NSBezierPath
            scaled.transform(using: AffineTransform(scaleByX: scaleX, byY: scaleY))
            scaled.lineWidth = 3 * scaleX
            scaled.lineCapStyle = .round
            scaled.lineJoinStyle = .round
            scaled.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let composited = context.makeImage() else { return image }
        return NSImage(cgImage: composited, size: NSSize(width: composited.width, height: composited.height))
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
