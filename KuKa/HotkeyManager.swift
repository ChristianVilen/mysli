import Cocoa

class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    var onHotkey: (() -> Void)?

    func start() {
        // This both checks AND prompts the system dialog if not trusted
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )

        NSLog("Ku-Ka: AXIsProcessTrusted = \(trusted)")

        if !trusted {
            promptAccessibility()
            return
        }

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
    }

    private func handleEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // keyCode 0x15 = "4", check Shift+Command
        if keyCode == 0x15,
           flags.contains(.maskShift),
           flags.contains(.maskCommand) {
            DispatchQueue.main.async { self.onHotkey?() }
            return nil // suppress the event
        }
        return Unmanaged.passUnretained(event)
    }

    private func promptAccessibility() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Ku-Ka needs Accessibility permission to capture the Shift+Command+4 shortcut.\n\nPlease enable it in System Settings → Privacy & Security → Accessibility, then relaunch the app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        NSLog("Ku-Ka: Accessibility permission not granted — hotkey disabled")
    }
}
