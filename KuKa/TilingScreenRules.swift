import CoreGraphics

/// Two screen-related rules the tiling feature needs and the layout engine
/// deliberately doesn't own: counting how many windows "belong" to a given
/// screen (for `TilingContext.windowCount`), and picking which screen a
/// window should be tiled against in the first place. Both work purely off
/// `CGRect` geometry, with no AppKit or Accessibility dependency, so they
/// stay easy to unit test.
enum TilingScreenRules {
    /// Owner name of Stage Manager's strip/backdrop process. Its windows
    /// never count toward a screen's window count.
    static let stageManagerOwnerName = "WindowManager"

    /// A window counts for `screenFrame` if the area of its intersection
    /// with the screen is at least half the window's own area. Zero-area
    /// windows never count. `windows` is expected to already be filtered by
    /// the caller to on-screen, layer-0, non-Ku-Ka windows.
    ///
    /// v1 limitation: a window wider (or taller) than twice the screen it's
    /// centered on will never clear the 50% threshold for any screen, so it
    /// counts on none of them. Accepted for now — not a case we expect in
    /// practice.
    static func windowCount(on screenFrame: CGRect, windows: [WindowInfo]) -> Int {
        windows.filter { window in
            guard window.ownerName != stageManagerOwnerName else { return false }
            let windowArea = window.frame.width * window.frame.height
            guard windowArea > 0 else { return false }
            let intersection = window.frame.intersection(screenFrame)
            guard !intersection.isNull else { return false }
            let intersectionArea = intersection.width * intersection.height
            return intersectionArea >= windowArea * 0.5
        }.count
    }

    /// Picks the index of the screen `windowFrame` overlaps the most, for
    /// deciding which screen to tile a window against. Ties break toward the
    /// lowest index. Returns `nil` when `screenFrames` is empty or
    /// `windowFrame` doesn't overlap any of them at all — the caller is
    /// expected to fall back to a default screen (e.g. `NSScreen.main`) in
    /// that case.
    ///
    /// This deliberately does not share `windowCount`'s "at least 50% of the
    /// window's own area" rule. Counting is allowed to answer "this window
    /// doesn't belong to any screen" — a window barely brushing an edge
    /// shouldn't be counted anywhere. Picking a screen to tile against can't
    /// afford that: a window has to move somewhere, so even a one-point
    /// sliver of overlap is still the only candidate screen available, and
    /// the picker has to return it rather than say "nowhere".
    static func bestScreenIndex(for windowFrame: CGRect, screenFrames: [CGRect]) -> Int? {
        var bestIndex: Int?
        var bestArea: CGFloat = 0
        for (index, screenFrame) in screenFrames.enumerated() {
            let intersection = screenFrame.intersection(windowFrame)
            guard !intersection.isNull else { continue }
            let area = intersection.width * intersection.height
            guard area > 0 else { continue }
            if bestIndex == nil || area > bestArea {
                bestIndex = index
                bestArea = area
            }
        }
        return bestIndex
    }
}
