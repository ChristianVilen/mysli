import CoreGraphics

/// Screen-geometry rules the tiling feature needs and the layout engine
/// deliberately doesn't own. Pure `CGRect` math with no AppKit or
/// Accessibility dependency, so they stay easy to unit test.
enum TilingScreenRules {
    /// Owner name of Stage Manager's strip/backdrop process. Its windows
    /// never count toward a screen's window count.
    static let stageManagerOwnerName = "WindowManager"

    /// A window counts for `screenFrame` if at least half its own area
    /// intersects it; zero-area windows never count. `windows` is expected
    /// to already be filtered to on-screen, layer-0, non-Ku-Ka windows.
    /// Accepted v1 limitation: a window wider than twice the screen never
    /// clears the threshold, so it counts on no screen.
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

    /// Index of the screen `windowFrame` overlaps the most; ties break
    /// toward the lowest index. Nil when there's no overlap at all — the
    /// caller falls back to a default screen. Deliberately not
    /// `windowCount`'s 50% rule: a window has to be tiled somewhere, so even
    /// a sliver of overlap makes that screen the answer.
    /// Index of the screen next to `currentIndex` in `direction`, ordered by
    /// horizontal center with wrap-around — so with two screens, either
    /// direction gives the other one. Returns nil when there is no other
    /// screen to hop to, or `currentIndex` is out of range.
    static func adjacentScreenIndex(of currentIndex: Int, direction: HorizontalDirection, screenFrames: [CGRect]) -> Int? {
        guard screenFrames.count >= 2, screenFrames.indices.contains(currentIndex) else { return nil }
        // Explicit index tie-break: Swift's sort is not guaranteed stable,
        // and the wrap-around math needs one total order.
        let ordered = screenFrames.indices.sorted {
            (screenFrames[$0].midX, $0) < (screenFrames[$1].midX, $1)
        }
        guard let position = ordered.firstIndex(of: currentIndex) else { return nil }
        let step = direction == .left ? -1 : 1
        return ordered[(position + step + ordered.count) % ordered.count]
    }

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
