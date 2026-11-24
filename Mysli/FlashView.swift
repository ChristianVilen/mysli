import Cocoa

class FlashView: NSWindow {
    private static let fillColor: NSColor = .white
    private static let initialOpacity: CGFloat = 0.4

    static func flash(on screen: ScreenGeometry) {
        let window = FlashView(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = fillColor
        window.alphaValue = initialOpacity
        window.ignoresMouseEvents = true
        window.orderFront(nil)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.close()
        })
    }
}

#if DEBUG
extension FlashView {
    static func previewOverlay(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = fillColor.cgColor
        view.alphaValue = initialOpacity
        return view
    }
}
#endif
