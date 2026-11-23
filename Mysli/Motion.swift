import Cocoa

/// Entrances and exits ease out. Movement on screen eases in and out.
enum Motion {
    static let easeOut = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    static let easeInOut = CAMediaTimingFunction(controlPoints: 0.77, 0, 0.175, 1)
}

extension CALayer {
    private static let motionKey = "motion."

    /// Animates `keyPath` from `value` to the model value, which the caller sets first, so nothing stays on the
    /// layer when the animation ends. A delayed animation shows `value` while it waits.
    func animate(_ keyPath: String, from value: Any, duration: CFTimeInterval, delay: CFTimeInterval = 0,
                 timing: CAMediaTimingFunction = Motion.easeOut) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = value
        animation.duration = duration
        animation.timingFunction = timing
        if delay > 0 {
            animation.beginTime = convertTime(CACurrentMediaTime(), from: nil) + delay
            animation.fillMode = .backwards
        }
        add(animation, forKey: Self.motionKey + keyPath)
    }

    func removeMotion() {
        for key in animationKeys() ?? [] where key.hasPrefix(Self.motionKey) { removeAnimation(forKey: key) }
    }

    /// AppKit puts the anchor point of a view's layer at its origin, so a plain scale pulls the layer to its corner.
    func scaledAboutCenter(_ scale: CGFloat, size: CGSize) -> NSValue {
        let x = size.width * (0.5 - anchorPoint.x)
        let y = size.height * (0.5 - anchorPoint.y)
        return NSValue(caTransform3D: CATransform3DTranslate(
            CATransform3DScale(CATransform3DMakeTranslation(x, y, 0), scale, scale, 1), -x, -y, 0))
    }

    /// Fades the layer out while it moves `dx` points, and then removes it.
    func fadeAway(duration: CFTimeInterval, dx: CGFloat = 0) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in self?.removeFromSuperlayer() }
        opacity = 0
        animate("opacity", from: 1, duration: duration)
        if dx != 0 {
            transform = CATransform3DMakeTranslation(dx, 0, 0)
            animate("transform.translation.x", from: 0, duration: duration)
        }
        CATransaction.commit()
    }
}

extension NSView {
    /// Puts a picture of the view over it, in the layer of its superview. The view can then change or hide at once
    /// while the picture animates away.
    func coveringPicture() -> CALayer? {
        guard !isHiddenOrHasHiddenAncestor, let host = superview?.layer,
              let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        effectiveAppearance.performAsCurrentDrawingAppearance { cacheDisplay(in: bounds, to: bitmap) }
        let picture = CALayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.contents = bitmap.cgImage
        // AppKit gives the layer of a superview the coordinates of that view, flipped or not.
        picture.frame = frame
        host.addSublayer(picture)
        CATransaction.commit()
        return picture
    }
}
