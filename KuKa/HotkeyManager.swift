import Cocoa

/// A key combo the event tap recognized. The combo-to-action mapping lives
/// entirely in `HotkeyManager.action(for:)`; everyone else deals in actions.
enum HotkeyAction: Equatable {
    case captureArea
    case captureFullScreen
    case tile(TilingAction)
}

class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var watchdogTimer: Timer?
    /// Called on the main queue for every recognized (and swallowed) combo.
    var onAction: ((HotkeyAction) -> Void)?
    /// When false, the tiling key combos pass through to other apps instead
    /// of being swallowed. Screenshot hotkeys are unaffected. Read from the
    /// tap callback and written from the menu — both on the main thread.
    var tilingEnabled = true

    /// True while the event tap is installed. `AppDelegate` uses this to
    /// start the tap exactly once when Accessibility is granted.
    var isRunning: Bool { eventTap != nil }

    func stop() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// Install the event tap. Permission handling lives in
    /// `PermissionsManager` — the caller should only start once Accessibility
    /// is granted; without it tap creation fails and just logs.
    func start() {
        stop()

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
                // The system disables a tap it considers slow or during
                // certain secure-input transitions; re-enable right away
                // instead of waiting for the watchdog's next tick.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    manager.reenableTap()
                    return Unmanaged.passUnretained(event)
                }
                return manager.handleEvent(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("Ku-Ka: CGEvent tap creation failed. Is Accessibility permission granted?")
            return
        }

        NSLog("Ku-Ka: CGEvent tap created successfully")
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkTapState()
        }
    }

    private func checkTapState() {
        guard let tap = eventTap else { return }
        if !CGEvent.tapIsEnabled(tap: tap) {
            NSLog("Ku-Ka: Event tap was disabled by the system, re-enabling")
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func reenableTap() {
        guard let tap = eventTap else { return }
        NSLog("Ku-Ka: Event tap disabled mid-stream, re-enabling")
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // Internal (not private) so tests can feed synthetic events through the
    // same routing the event tap uses.
    func handleEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let action = action(for: event) else {
            return Unmanaged.passUnretained(event)
        }
        DispatchQueue.main.async { [weak self] in self?.onAction?(action) }
        return nil
    }

    /// The single place that knows which key combo means what. Returns nil
    /// for anything Ku-Ka shouldn't swallow.
    private func action(for event: CGEvent) -> HotkeyAction? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Screenshot shortcuts: Shift+Command+3/4.
        if flags.contains(.maskShift), flags.contains(.maskCommand) {
            if keyCode == 0x14 { return .captureFullScreen }
            if keyCode == 0x15 { return .captureArea }
        }

        // Tiling shortcuts: Ctrl+Option+Left/Right/Return/C. Arrow key
        // events also carry .maskSecondaryFn and .maskNumericPad, so this
        // only requires the two modifiers it cares about rather than
        // matching the full flag set, and explicitly rules out Command/Shift
        // so it can't collide with the screenshot shortcuts above.
        if tilingEnabled,
            flags.contains(.maskControl), flags.contains(.maskAlternate),
            !flags.contains(.maskCommand), !flags.contains(.maskShift) {
            if keyCode == 0x7B { return .tile(.leftHalf) }
            if keyCode == 0x7C { return .tile(.rightHalf) }
            if keyCode == 0x24 { return .tile(.maximize) }
            if keyCode == 0x08 { return .tile(.center) }
        }

        return nil
    }
}
