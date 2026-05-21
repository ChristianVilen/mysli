import Cocoa

struct ScrollTransformSettings {
    var invert: Bool
    var disableAcceleration: Bool
    var linesPerTick: Int
}

enum ScrollTransform {
    static let pixelsPerLine: Int64 = 10

    static func apply(to event: CGEvent, settings: ScrollTransformSettings) -> CGEvent {
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 {
            return event
        }

        let originalLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        if originalLine == 0 {
            return event
        }

        let sign: Int64 = settings.invert ? (originalLine > 0 ? -1 : 1) : (originalLine > 0 ? 1 : -1)

        if settings.disableAcceleration {
            let lines = sign * Int64(settings.linesPerTick)
            let points = lines * pixelsPerLine
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: lines)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: points)
            event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: points << 16)
        } else if settings.invert {
            let line = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let point = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let fixed = event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1)
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -line)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -point)
            event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fixed)
        }

        return event
    }
}

class ScrollWheelManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var watchdogTimer: Timer?

    var settings = ScrollTransformSettings(invert: false, disableAcceleration: false, linesPerTick: 3)
    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        )
        if !trusted {
            NSLog("Ku-Ka: ScrollWheelManager skipped — Accessibility not granted")
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
        isRunning = false
    }

    func reload() {
        if isRunning {
            stop()
            start()
        }
    }

    private func createTap() {
        let mask: CGEventMask = 1 << CGEventType.scrollWheel.rawValue

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, refcon in
                let manager = Unmanaged<ScrollWheelManager>.fromOpaque(refcon!).takeUnretainedValue()
                let transformed = ScrollTransform.apply(to: event, settings: manager.settings)
                return Unmanaged.passUnretained(transformed)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("Ku-Ka: ScrollWheelManager tap creation failed")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true

        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, let tap = self.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                NSLog("Ku-Ka: scroll tap disabled by system, re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
    }
}
