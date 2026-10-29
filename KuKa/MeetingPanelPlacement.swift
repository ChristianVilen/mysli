import CoreGraphics

/// Pure geometry for the pill and its drawer, in NS coordinates (bottom-left origin).
enum MeetingPanelPlacement {
    static let inset: CGFloat = 16
    static let drawerHeights: ClosedRange<CGFloat> = 140...460
    static let defaultDrawerHeight: CGFloat = 280

    /// The pill's top-right corner: the saved corner, moved so the whole pill lies in the
    /// visible frame of the screen it is on. With no saved corner, or one on no screen (a
    /// display was unplugged), the top-right of the primary screen's visible frame, `inset` in.
    /// Anchored top-right, so the pill grows to the left when a state makes it wider.
    static func pillTopRight(saved: CGPoint?, pillSize: CGSize, screens: [ScreenGeometry]) -> CGPoint? {
        if let saved, let screen = screen(of: pillRect(topRight: saved, size: pillSize), in: screens) {
            let visible = screen.visibleFrame
            return CGPoint(x: min(max(saved.x, visible.minX + pillSize.width), visible.maxX),
                           y: min(max(saved.y, visible.minY + pillSize.height), visible.maxY))
        }
        guard let primary = screens.first?.visibleFrame else { return nil }
        return CGPoint(x: primary.maxX - inset, y: primary.maxY - inset)
    }

    /// The window frame for the pill plus, when open, the drawer. The drawer opens below the
    /// pill, or above it when it would not fit below on the pill's screen.
    static func frame(pillTopRight: CGPoint, pillSize: CGSize, drawerHeight: CGFloat?,
                      screens: [ScreenGeometry]) -> (frame: CGRect, drawerAbove: Bool) {
        let pill = pillRect(topRight: pillTopRight, size: pillSize)
        guard let drawerHeight else { return (pill, false) }
        let bottom = screen(of: pill, in: screens)?.visibleFrame.minY ?? -.infinity
        let drawerAbove = pill.minY - drawerHeight < bottom
        let frame = CGRect(x: pill.minX, y: drawerAbove ? pill.minY : pill.minY - drawerHeight,
                           width: pill.width, height: pill.height + drawerHeight)
        return (frame, drawerAbove)
    }

    static func clampedDrawerHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, drawerHeights.lowerBound), drawerHeights.upperBound)
    }

    private static func pillRect(topRight: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: topRight.x - size.width, y: topRight.y - size.height, width: size.width, height: size.height)
    }

    private static func screen(of rect: CGRect, in screens: [ScreenGeometry]) -> ScreenGeometry? {
        let overlaps = screens.map { (screen: $0, area: area($0.frame.intersection(rect))) }
        return overlaps.filter { $0.area > 0 }.max { $0.area < $1.area }?.screen
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}

struct TranscriptFollow: Equatable {
    private(set) var isFollowing = true
    private(set) var unseenRows = 0

    mutating func scrolled(lastRowVisible: Bool) {
        isFollowing = lastRowVisible
        if lastRowVisible { unseenRows = 0 }
    }

    mutating func rowsChanged(from old: Int, to new: Int) {
        guard !isFollowing else { return }
        unseenRows += max(0, new - old)
    }

    mutating func returnToLive() {
        isFollowing = true
        unseenRows = 0
    }

    var returnToLiveTitle: String? {
        isFollowing ? nil : MeetingPanelCopy.returnToLive(newRows: unseenRows)
    }
}
