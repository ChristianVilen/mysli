import Cocoa

struct WindowInfo {
    let windowID: CGWindowID
    let frame: CGRect // NS screen coordinates (bottom-left origin)
    let ownerName: String
    let layer: Int
}

protocol WindowListProvider {
    func windowsOnScreen() -> [WindowInfo]
}

class CGWindowListProvider: WindowListProvider {
    func windowsOnScreen() -> [WindowInfo] {
        let myPID = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[CFString: Any]] else { return [] }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

        return list.compactMap { dict -> WindowInfo? in
            guard let pid = dict[kCGWindowOwnerPID] as? Int32, pid != myPID,
                  let id = dict[kCGWindowNumber] as? CGWindowID,
                  let layer = dict[kCGWindowLayer] as? Int, layer == 0,
                  let bounds = dict[kCGWindowBounds] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"] else { return nil }

            // Convert CG (top-left) to NS (bottom-left)
            let nsFrame = ScreenCoordinates.flipVertical(
                CGRect(x: x, y: y, width: w, height: h),
                primaryScreenHeight: primaryHeight
            )
            return WindowInfo(windowID: id, frame: nsFrame, ownerName: dict[kCGWindowOwnerName as CFString] as? String ?? "", layer: layer)
        }
    }
}
