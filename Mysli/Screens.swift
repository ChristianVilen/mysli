import Cocoa

/// One screen's geometry, detached from AppKit so tests can fabricate
/// multi-display layouts. Frames are in NS coordinates (bottom-left origin,
/// global).
struct ScreenGeometry: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
}

extension ScreenGeometry {
    /// The screen the pointer is on, or nil when the layout is empty or the
    /// point falls in a gap between displays — the caller picks its own
    /// fallback.
    ///
    /// Two rules, not one. A cursor parked in the menu bar sits exactly on
    /// its screen's top edge, and `contains` treats maxY as outside the
    /// frame; without the second rule the answer would jump to the primary
    /// screen every time the pointer is up there.
    static func under(_ point: CGPoint, in layout: [ScreenGeometry]) -> ScreenGeometry? {
        layout.first { $0.frame.contains(point) }
            ?? layout.first {
                point.x >= $0.frame.minX
                    && point.x < $0.frame.maxX
                    && abs(point.y - $0.frame.maxY) < 1
            }
    }
}

/// Test seam for the screen layout. Ambient NSScreen reads live only in
/// system adapters — this one, and the AppKit/CG/AX-facing adapters that are
/// themselves the system edge.
protocol Screens {
    /// All screens, primary first (same order as NSScreen.screens).
    var all: [ScreenGeometry] { get }
    /// Index into `all` of the screen with the key window, if any.
    var mainIndex: Int? { get }
}

extension Screens {
    var main: ScreenGeometry? {
        guard let mainIndex, all.indices.contains(mainIndex) else { return nil }
        return all[mainIndex]
    }

    /// The screen with the key window, falling back to the primary screen.
    /// Nil only when no screens are available — the one shared answer to
    /// "which screen, when the capture didn't say".
    var mainOrPrimary: ScreenGeometry? { main ?? all.first }
}

struct SystemScreens: Screens {
    var all: [ScreenGeometry] {
        NSScreen.screens.map { ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }

    var mainIndex: Int? {
        guard let main = NSScreen.main else { return nil }
        return NSScreen.screens.firstIndex(of: main)
    }
}
