import CoreGraphics

/// The screen math shared across features, kept as a neutral,
/// dependency-free namespace so window tiling, selection, and the CG/AX
/// adapters can call it without depending on each other. Owns the vertical
/// flip every top-left/bottom-left conversion uses — CG (window server) and
/// AX (Accessibility) have a top-left global origin; NS (AppKit) bottom-left
/// — and the "which screen owns this rect" rule.
enum ScreenCoordinates {
    static func flipVertical(_ frame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.origin.x,
            y: primaryScreenHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    /// CG capture rect for a selection made on the screen with `screenFrame`
    /// (`rect` is view-local, bottom-left origin): offset to global NS
    /// coordinates, then the standard flip against the primary's height.
    /// Replaces a long-standing formula that flipped against the screen's own
    /// height — identical whenever the screen's top edge lines up with the
    /// primary's, wrong for other arrangements.
    static func cgRect(forSelection rect: CGRect, inScreenFrame screenFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        let globalNS = CGRect(
            x: screenFrame.origin.x + rect.origin.x,
            y: screenFrame.origin.y + rect.origin.y,
            width: rect.width,
            height: rect.height
        )
        return flipVertical(globalNS, primaryScreenHeight: primaryHeight)
    }

    /// Index of the screen `rect` overlaps the most; ties break toward the
    /// lowest index. Nil when there's no overlap at all — the caller falls
    /// back to a default screen. Even a sliver of overlap makes that screen
    /// the answer: a window has to be tiled somewhere, and a selected
    /// window's capture has to be attributed to some screen.
    static func bestScreenIndex(for rect: CGRect, screenFrames: [CGRect]) -> Int? {
        var bestIndex: Int?
        var bestArea: CGFloat = 0
        for (index, screenFrame) in screenFrames.enumerated() {
            let intersection = screenFrame.intersection(rect)
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
