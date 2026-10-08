import Cocoa
import Carbon.HIToolbox

/// Owns registration state, including keys macOS has not yet released.
@MainActor
final class CarbonHotkeyRegistrar {
    private struct Registration {
        enum State { case active, pendingRelease }
        let id: UInt32
        let reference: EventHotKeyRef
        var state = State.active
    }

    private static let signature: OSType = 0x4B754B61 // KuKa
    private let api: CarbonHotkeyAPI
    private var nextID: UInt32 = 0
    private var handler: EventHandlerRef?
    private var registrations: [HotkeyShortcut: Registration] = [:]
    var onAction: ((HotkeyAction) -> Void)?

    init(api: CarbonHotkeyAPI = CarbonHotkeyAPI()) { self.api = api }

    isolated deinit { stop() }

    func reconcile(desired: Set<HotkeyShortcut>) -> [HotkeyRegistrationIssue] {
        var failures = systemIssues(for: desired)
        let available = desired.subtracting(failures.keys)
        for shortcut in HotkeyShortcut.allCases {
            if let registration = registrations[shortcut],
               registration.state == .pendingRelease || !available.contains(shortcut) {
                // Invalidate dispatch before attempting release, even if the OS refuses.
                registrations[shortcut]?.state = .pendingRelease
                let status = api.unregister(registration.reference)
                if status == noErr || status == eventHotKeyInvalidErr {
                    registrations[shortcut] = nil
                } else {
                    failures[shortcut] = .releaseFailed(status)
                }
            }
            if available.contains(shortcut), registrations[shortcut] == nil,
               let failure = register(shortcut) {
                failures[shortcut] = failure
            }
        }
        return HotkeyShortcut.allCases.compactMap { shortcut in
            failures[shortcut].map { .init(shortcut: shortcut, failure: $0) }
        }
    }

    @discardableResult
    func stop() -> [HotkeyRegistrationIssue] {
        let issues = reconcile(desired: [])
        if let handler {
            _ = api.removeHandler(handler)
            self.handler = nil
        }
        return issues
    }

    private func systemIssues(for desired: Set<HotkeyShortcut>) -> [HotkeyShortcut: HotkeyRegistrationFailure] {
        guard !desired.isEmpty else { return [:] }
        var array: Unmanaged<CFArray>?
        let status = api.copySystemHotkeys(&array)
        guard status == noErr, let bindings = array?.takeRetainedValue() as? [[String: Any]] else {
            let error = status == noErr ? OSStatus(paramErr) : status
            return Dictionary(uniqueKeysWithValues: desired.map { ($0, .systemLookupFailed(error)) })
        }
        var issues: [HotkeyShortcut: HotkeyRegistrationFailure] = [:]
        for shortcut in desired {
            if bindings.contains(where: {
                ($0[kHISymbolicHotKeyEnabled] as? Bool) == true &&
                ($0[kHISymbolicHotKeyCode] as? NSNumber)?.uint32Value == shortcut.keyCode &&
                ($0[kHISymbolicHotKeyModifiers] as? NSNumber)?.uint32Value == shortcut.modifiers
            }) {
                issues[shortcut] = .systemConflict
            }
        }
        return issues
    }

    private func register(_ shortcut: HotkeyShortcut) -> HotkeyRegistrationFailure? {
        let handlerStatus = installHandler()
        guard handlerStatus == noErr else { return .registrationFailed(handlerStatus) }
        // Never reuse an ID: an event from a removed registration may still be queued.
        guard nextID < UInt32.max else { return .registrationFailed(OSStatus(eventInternalErr)) }
        nextID += 1
        var reference: EventHotKeyRef?
        let status = api.register(shortcut, EventHotKeyID(signature: Self.signature, id: nextID), &reference)
        guard status == noErr, let reference else {
            return .registrationFailed(status == noErr ? OSStatus(eventInternalErr) : status)
        }
        registrations[shortcut] = Registration(id: nextID, reference: reference)
        return nil
    }

    private func installHandler() -> OSStatus {
        guard handler == nil else { return noErr }
        return api.installHandler({ _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                let registrar = Unmanaged<CarbonHotkeyRegistrar>.fromOpaque(context).takeUnretainedValue()
                return registrar.receive(event)
            }
        }, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    private func receive(_ event: EventRef) -> OSStatus {
        var key = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                       EventParamType(typeEventHotKeyID), nil,
                                       MemoryLayout<EventHotKeyID>.size, nil, &key)
        guard status == noErr, key.signature == Self.signature,
              let shortcut = registrations.first(where: { $0.value.id == key.id && $0.value.state == .active })?.key else {
            return OSStatus(eventNotHandledErr)
        }
        onAction?(shortcut.action)
        return noErr
    }
}
