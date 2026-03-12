import Cocoa

class FlashView: NSWindow {
    static func flash(on screen: NSScreen) {
        let window = FlashView(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .white
        window.alphaValue = 0.4
        window.ignoresMouseEvents = true
        window.orderFront(nil)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }
}
