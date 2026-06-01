import Cocoa

/// Base class for the app's borderless, floating overlay panels (thumbnails,
/// combine button). Centralizes the shared appearance and — importantly — the
/// `isReleasedWhenClosed = false` lifecycle invariant so callers can safely
/// `close()` these panels and let ARC deallocate them.
class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }
}
