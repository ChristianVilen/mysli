import Cocoa
import ApplicationServices

/// Stable identity for an `AXUIElement`, for use as a dictionary key (e.g. the
/// controller's saved-frame map). AXUIElement is a CFTypeRef without value
/// semantics, so identity/equality go through `CFHash`/`CFEqual` rather than
/// Swift's default `Hashable` synthesis.
struct WindowHandle: Hashable {
    let element: AXUIElement

    static func == (lhs: WindowHandle, rhs: WindowHandle) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}

struct FocusedWindow {
    let element: AXUIElement
    let frame: CGRect // NS screen coordinates (bottom-left origin)

    var handle: WindowHandle { WindowHandle(element: element) }
}

@MainActor
protocol WindowControlling {
    func focusedWindow() -> FocusedWindow?
    /// Moves/resizes `handle` to `frame` (NS space), then re-reads the
    /// window's actual resulting frame and returns it (also NS space) — some
    /// apps snap to a cell grid or otherwise adjust what was asked for, and
    /// callers may want to compare against what actually happened. A failed
    /// set is logged but doesn't stop the re-read, so the caller still gets
    /// back whatever frame the window actually ended up at. Returns nil only
    /// if the re-read (or the NS/AX conversion) itself fails.
    @discardableResult
    func setFrame(_ frame: CGRect, of handle: WindowHandle) -> CGRect?
}

/// Accessibility-API glue for reading and moving the frontmost window.
/// All coordinates crossing this boundary are NS space (bottom-left origin);
/// conversion to/from AX's top-left-origin global space happens internally.
@MainActor
struct AccessibilityWindowControl: WindowControlling {
    /// Caps how long a single AX round trip can block the main thread. A
    /// hung target app can otherwise stall an AX call for several seconds
    /// per attribute read/write.
    private static let messagingTimeout: Float = 0.5

    func focusedWindow() -> FocusedWindow? {
        guard let primaryScreenHeight = Self.primaryScreenHeight() else {
            NSLog("Ku-Ka: No screens available; cannot resolve focused window")
            return nil
        }

        // Resolve the frontmost app through NSWorkspace, not the system-wide
        // AX focused-application attribute. That attribute read has to
        // round-trip through the focused app's accessibility server, and
        // Electron/WebView2 apps (Microsoft Teams) leave theirs unresponsive
        // until first contact, so the read fails with kAXErrorCannotComplete
        // and tiling silently does nothing. NSWorkspace answers locally.
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            NSLog("Ku-Ka: No frontmost application; cannot resolve focused window")
            return nil
        }
        guard frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            // Never tile Ku-Ka's own panels.
            return nil
        }

        let app = AXUIElementCreateApplication(frontmost.processIdentifier)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)

        guard let window = Self.axElement(kAXFocusedWindowAttribute as CFString, from: app, label: "focused window") else {
            return nil
        }
        guard let position = Self.axPoint(kAXPositionAttribute as CFString, from: window, label: "window position") else {
            return nil
        }
        guard let size = Self.axSize(kAXSizeAttribute as CFString, from: window, label: "window size") else {
            return nil
        }

        // AX (top-left origin) -> NS (bottom-left origin)
        let axFrame = CGRect(origin: position, size: size)
        let nsFrame = ScreenCoordinates.flipVertical(axFrame, primaryScreenHeight: primaryScreenHeight)
        return FocusedWindow(element: window, frame: nsFrame)
    }

    @discardableResult
    func setFrame(_ frame: CGRect, of handle: WindowHandle) -> CGRect? {
        guard let primaryScreenHeight = Self.primaryScreenHeight() else {
            NSLog("Ku-Ka: No screens available; cannot set window frame")
            return nil
        }

        let element = handle.element
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)

        var positionSettable: DarwinBoolean = false
        let positionSettableError = AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &positionSettable)
        var sizeSettable: DarwinBoolean = false
        let sizeSettableError = AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &sizeSettable)
        guard positionSettableError == .success, positionSettable.boolValue,
              sizeSettableError == .success, sizeSettable.boolValue else {
            NSLog("Ku-Ka: Window position/size not settable; leaving window untouched")
            return nil
        }

        // NS (bottom-left origin) -> AX (top-left origin); the flip is its
        // own inverse, so both directions are the same transform.
        let axFrame = ScreenCoordinates.flipVertical(frame, primaryScreenHeight: primaryScreenHeight)
        var position = axFrame.origin
        var size = axFrame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            NSLog("Ku-Ka: Failed to create AXValue for target position/size")
            return nil
        }

        // Position, then size, then position again: setting the size can
        // shift a window that's near a screen edge, so re-asserting the
        // position afterward is a common window-manager reliability trick.
        let setPosition1Error = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        if setPosition1Error != .success {
            NSLog("Ku-Ka: Failed to set window position (AXError \(setPosition1Error.rawValue))")
        }
        let setSizeError = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        if setSizeError != .success {
            NSLog("Ku-Ka: Failed to set window size (AXError \(setSizeError.rawValue))")
        }
        let setPosition2Error = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        if setPosition2Error != .success {
            NSLog("Ku-Ka: Failed to re-set window position (AXError \(setPosition2Error.rawValue))")
        }

        guard let achievedPosition = Self.axPoint(kAXPositionAttribute as CFString, from: element, label: "window position after set") else {
            return nil
        }
        guard let achievedSize = Self.axSize(kAXSizeAttribute as CFString, from: element, label: "window size after set") else {
            return nil
        }

        let achievedAXFrame = CGRect(origin: achievedPosition, size: achievedSize)
        return ScreenCoordinates.flipVertical(achievedAXFrame, primaryScreenHeight: primaryScreenHeight)
    }

    // MARK: - AX read helpers

    /// Reads an attribute expected to hold another `AXUIElement` (e.g. the
    /// focused application, the focused window), logging the attribute name
    /// and `AXError` on failure.
    private static func axElement(_ attribute: CFString, from element: AXUIElement, label: String) -> AXUIElement? {
        var ref: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &ref)
        guard error == .success else {
            NSLog("Ku-Ka: Failed to read \(label) (AXError \(error.rawValue))")
            return nil
        }
        guard let value = ref, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            NSLog("Ku-Ka: \(label) attribute was not an AXUIElement")
            return nil
        }
        return (value as! AXUIElement)
    }

    /// Reads an attribute expected to hold an `AXValue` (position/size),
    /// logging the attribute name and `AXError` on failure. Shared by
    /// `axPoint`/`axSize`, which unpack the concrete type.
    private static func axValue(_ attribute: CFString, from element: AXUIElement, label: String) -> AXValue? {
        var ref: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &ref)
        guard error == .success else {
            NSLog("Ku-Ka: Failed to read \(label) (AXError \(error.rawValue))")
            return nil
        }
        guard let value = ref, CFGetTypeID(value) == AXValueGetTypeID() else {
            NSLog("Ku-Ka: \(label) attribute was not an AXValue")
            return nil
        }
        return (value as! AXValue)
    }

    /// Reads and unpacks an `AXValue` attribute expected to hold a `CGPoint`
    /// (e.g. `kAXPositionAttribute`), logging on failure.
    private static func axPoint(_ attribute: CFString, from element: AXUIElement, label: String) -> CGPoint? {
        guard let value = axValue(attribute, from: element, label: label) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else {
            NSLog("Ku-Ka: Failed to unpack \(label) as CGPoint")
            return nil
        }
        return point
    }

    /// Reads and unpacks an `AXValue` attribute expected to hold a `CGSize`
    /// (e.g. `kAXSizeAttribute`), logging on failure.
    private static func axSize(_ attribute: CFString, from element: AXUIElement, label: String) -> CGSize? {
        guard let value = axValue(attribute, from: element, label: label) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else {
            NSLog("Ku-Ka: Failed to unpack \(label) as CGSize")
            return nil
        }
        return size
    }

    /// The primary screen's height, or nil if no screens are available (so
    /// callers bail out instead of silently flipping coordinates around 0).
    private static func primaryScreenHeight() -> CGFloat? {
        NSScreen.screens.first?.frame.height
    }
}
