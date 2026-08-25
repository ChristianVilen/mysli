import CoreGraphics

/// Pure geometry of an adjustable crop rectangle inside fixed bounds. Points
/// are in the host view's coordinate space (origin bottom-left, y up), so
/// `top` means the maxY side. No AppKit, so every rule is unit-testable.
struct CropBox {
    enum Handle: Equatable {
        case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight
    }

    /// What a drag that starts at a point does.
    enum Action: Equatable {
        case draw
        case move
        case resize(Handle)
    }

    /// Distance in points around a handle that still counts as hitting it.
    static let handleHitRadius: CGFloat = 8

    let bounds: CGRect
    private(set) var rect: CGRect?

    private enum Drag {
        case draw(origin: CGPoint)
        case move(offset: CGPoint)
        case resize(Handle, anchor: CGRect)
    }
    private var drag: Drag?

    init(bounds: CGRect, rect: CGRect? = nil) {
        self.bounds = bounds
        self.rect = rect.flatMap {
            let cut = $0.intersection(bounds)
            return cut.isNull || cut.isEmpty ? nil : cut
        }
    }

    func action(at point: CGPoint) -> Action {
        guard let rect else { return .draw }
        if let handle = handle(at: point, of: rect) { return .resize(handle) }
        return rect.contains(point) ? .move : .draw
    }

    mutating func beginDrag(at point: CGPoint) {
        switch action(at: point) {
        case .draw:
            rect = nil
            drag = .draw(origin: clamp(point))
        case .move:
            guard let rect else { return }
            drag = .move(offset: CGPoint(x: point.x - rect.minX, y: point.y - rect.minY))
        case .resize(let handle):
            guard let rect else { return }
            drag = .resize(handle, anchor: rect)
        }
    }

    mutating func drag(to point: CGPoint) {
        guard let drag else { return }
        let clamped = clamp(point)
        switch drag {
        case .draw(let origin):
            rect = CGRect(x: min(origin.x, clamped.x), y: min(origin.y, clamped.y),
                          width: abs(clamped.x - origin.x), height: abs(clamped.y - origin.y))

        case .move(let offset):
            guard let size = rect?.size else { return }
            // The cursor may leave the bounds; the box stops at the edge.
            var moved = CGRect(origin: CGPoint(x: point.x - offset.x, y: point.y - offset.y), size: size)
            moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - size.width)
            moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - size.height)
            rect = moved

        case .resize(let handle, let anchor):
            var minX = anchor.minX, maxX = anchor.maxX
            var minY = anchor.minY, maxY = anchor.maxY
            switch handle {
            case .topLeft: minX = clamped.x; maxY = clamped.y
            case .top: maxY = clamped.y
            case .topRight: maxX = clamped.x; maxY = clamped.y
            case .left: minX = clamped.x
            case .right: maxX = clamped.x
            case .bottomLeft: minX = clamped.x; minY = clamped.y
            case .bottom: minY = clamped.y
            case .bottomRight: maxX = clamped.x; minY = clamped.y
            }
            // min/abs standardize the rect, which is what makes the box flip
            // when a handle is dragged past the opposite side.
            rect = CGRect(x: min(minX, maxX), y: min(minY, maxY),
                          width: abs(maxX - minX), height: abs(maxY - minY))
        }
    }

    mutating func endDrag() {
        drag = nil
        // A box thinner than a point is no box. This is also how a click
        // outside the box (a draw that never moved) clears it.
        if let rect, rect.width < 1 || rect.height < 1 {
            self.rect = nil
        }
    }

    // MARK: - Private

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    /// The handle under `point`, if any. Corners win over edges. On a box
    /// thinner than two radii, a point near both opposite sides only counts
    /// as near the nearer one.
    private func handle(at point: CGPoint, of rect: CGRect) -> Handle? {
        let radius = Self.handleHitRadius
        let toLeft = abs(point.x - rect.minX), toRight = abs(point.x - rect.maxX)
        let toBottom = abs(point.y - rect.minY), toTop = abs(point.y - rect.maxY)
        let nearLeft = toLeft <= radius && toLeft <= toRight
        let nearRight = toRight <= radius && toRight < toLeft
        let nearBottom = toBottom <= radius && toBottom <= toTop
        let nearTop = toTop <= radius && toTop < toBottom
        let alongX = point.x >= rect.minX - radius && point.x <= rect.maxX + radius
        let alongY = point.y >= rect.minY - radius && point.y <= rect.maxY + radius

        if nearLeft && nearTop { return .topLeft }
        if nearRight && nearTop { return .topRight }
        if nearLeft && nearBottom { return .bottomLeft }
        if nearRight && nearBottom { return .bottomRight }
        if nearTop && alongX { return .top }
        if nearBottom && alongX { return .bottom }
        if nearLeft && alongY { return .left }
        if nearRight && alongY { return .right }
        return nil
    }
}
