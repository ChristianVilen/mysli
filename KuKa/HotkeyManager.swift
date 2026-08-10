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

    func start() {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )

        NSLog("Ku-Ka: AXIsProcessTrusted = \(trusted)")

        if !trusted {
            promptAccessibility()
            return
        }

        createTap()
    }

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

    private func createTap() {
        stop()

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, refcon in
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
                return manager.handleEvent(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("Ku-Ka: CGEvent tap creation failed. Grant Accessibility permission and relaunch.")
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

        // Tiling shortcuts: Ctrl+Option+Left/Right/Return. Arrow key events
        // also carry .maskSecondaryFn and .maskNumericPad, so this only
        // requires the two modifiers it cares about rather than matching the
        // full flag set, and explicitly rules out Command/Shift so it can't
        // collide with the screenshot shortcuts above.
        if tilingEnabled,
            flags.contains(.maskControl), flags.contains(.maskAlternate),
            !flags.contains(.maskCommand), !flags.contains(.maskShift) {
            if keyCode == 0x7B { return .tile(.leftHalf) }
            if keyCode == 0x7C { return .tile(.rightHalf) }
            if keyCode == 0x24 { return .tile(.maximize) }
        }

        return nil
    }

    private func promptAccessibility() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Ku-Ka needs Accessibility permission to capture the Shift+Command+4 shortcut, and to move windows for the window tiling hotkeys.\n\nPlease enable it in System Settings → Privacy & Security → Accessibility, then relaunch the app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        NSLog("Ku-Ka: Accessibility permission not granted — hotkey disabled")
    }
}
