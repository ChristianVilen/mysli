import XCTest
import Carbon.HIToolbox
@testable import KuKa

@MainActor
final class HotkeyManagerTests: XCTestCase {
    func testSystemLookupFailureBlocksRegistrationUntilTheCheckRecovers() {
        let system = FakeHotkeySystem()
        system.lookupFailure = OSStatus(memFullErr)
        let manager = HotkeyManager(registrar: CarbonHotkeyRegistrar(api: system.api))
        manager.tilingEnabled = false
        defer { manager.stop() }
        var actions: [HotkeyAction] = []
        manager.onAction = { actions.append($0) }

        manager.start()
        XCTAssertEqual(manager.issues, [
            .init(shortcut: .captureFullScreen, failure: .systemLookupFailed(-108)),
            .init(shortcut: .captureArea, failure: .systemLookupFailed(-108))
        ])
        XCTAssertTrue(system.reservedShortcuts.isEmpty)
        system.press(.captureArea)
        XCTAssertTrue(actions.isEmpty)

        system.lookupFailure = nil
        manager.refresh()
        XCTAssertTrue(manager.issues.isEmpty)
        system.press(.captureArea)
        XCTAssertEqual(actions, [.captureArea])
    }

    func testHandlerInstallationFailureIsReportedAndRecoveredByRefresh() {
        let system = FakeHotkeySystem()
        system.handlerFailure = OSStatus(memFullErr)
        let manager = HotkeyManager(registrar: CarbonHotkeyRegistrar(api: system.api))
        manager.tilingEnabled = false
        defer { manager.stop() }
        var actions: [HotkeyAction] = []
        manager.onAction = { actions.append($0) }

        manager.start()
        XCTAssertEqual(manager.issues, [
            .init(shortcut: .captureFullScreen, failure: .registrationFailed(-108)),
            .init(shortcut: .captureArea, failure: .registrationFailed(-108))
        ])
        XCTAssertTrue(system.reservedShortcuts.isEmpty)

        system.handlerFailure = nil
        manager.refresh()
        XCTAssertTrue(manager.issues.isEmpty)
        system.press(.captureFullScreen)
        XCTAssertEqual(actions, [.captureFullScreen])
    }

    func testEventsWithAnotherAppsSignatureDoNotDeliverActions() {
        let system = FakeHotkeySystem()
        let manager = HotkeyManager(registrar: CarbonHotkeyRegistrar(api: system.api))
        defer { manager.stop() }
        var actions: [HotkeyAction] = []
        manager.onAction = { actions.append($0) }
        manager.start()

        system.eventSignature = 0x4F746872 // Othr
        system.press(.captureArea)
        XCTAssertTrue(actions.isEmpty)

        system.eventSignature = nil
        system.press(.captureArea)
        XCTAssertEqual(actions, [.captureArea])
    }

    func testFailedReleaseStaysVisibleWhenFeatureIsDisabled() {
        let system = FakeHotkeySystem()
        let manager = HotkeyManager(registrar: CarbonHotkeyRegistrar(api: system.api))
        defer { manager.stop() }
        var actions: [HotkeyAction] = []
        manager.onAction = { actions.append($0) }
        manager.start()
        let oldPress = system.callbacks[.tileLeft]!
        system.releaseFailures.insert(.tileLeft)
        manager.tilingEnabled = false
        XCTAssertEqual(manager.issues, [.init(shortcut: .tileLeft, failure: .releaseFailed(-50))])
        XCTAssertNotNil(system.callbacks[.tileLeft])
        oldPress()
        XCTAssertTrue(actions.isEmpty)

        manager.tilingEnabled = true
        XCTAssertEqual(system.attempts[.tileLeft], 1, "do not register over a pending release")
        XCTAssertEqual(manager.issues, [.init(shortcut: .tileLeft, failure: .releaseFailed(-50))])
        system.releaseFailures = []
        manager.refresh()
        XCTAssertTrue(manager.issues.isEmpty)
        oldPress()
        system.press(.tileLeft)
        XCTAssertEqual(actions, [.tile(.leftHalf)])
        XCTAssertEqual(system.attempts[.tileLeft], 2)
    }

    func testStopReportsPendingReleaseAndRepeatedStopCanCompleteIt() {
        let system = FakeHotkeySystem()
        let manager = HotkeyManager(registrar: CarbonHotkeyRegistrar(api: system.api))
        manager.start()
        system.releaseFailures.insert(.tileRight)
        manager.stop()
        XCTAssertFalse(manager.isRunning)
        XCTAssertEqual(manager.issues, [.init(shortcut: .tileRight, failure: .releaseFailed(-50))])
        XCTAssertEqual(system.reservedShortcuts, [.tileRight])
        system.releaseFailures = []
        manager.stop()
        XCTAssertTrue(manager.issues.isEmpty)
        XCTAssertTrue(system.reservedShortcuts.isEmpty)
    }

    func testReleasingManagerReleasesItsShortcuts() {
        let system = FakeHotkeySystem()
        var manager: HotkeyManager? = HotkeyManager(registrar: CarbonHotkeyRegistrar(api: system.api))
        manager?.start()
        manager = nil
        XCTAssertTrue(system.callbacks.isEmpty)
    }

    func testPollingRecoversAndWakeRenewsWithoutLeavingObserversAfterStop() async {
        let system = FakeHotkeySystem()
        system.failures[.tileLeft] = -9878
        let notifications = NotificationCenter()
        let manager = HotkeyManager(registrar: CarbonHotkeyRegistrar(api: system.api), pollInterval: 0.01, workspaceNotifications: notifications)
        defer { manager.stop() }
        manager.start()
        let recovered = expectation(description: "failed shortcut recovered")
        manager.onChange = { if manager.issues.isEmpty { recovered.fulfill() } }
        system.failures = [:]
        await fulfillment(of: [recovered], timeout: 1)
        manager.onChange = nil
        let oldPress = system.callbacks[.tileLeft]!
        var actions: [HotkeyAction] = []
        manager.onAction = { actions.append($0) }
        notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        oldPress()
        system.press(.tileLeft)
        XCTAssertEqual(actions, [.tile(.leftHalf)])
        XCTAssertEqual(system.attempts[.tileRight], 2)
        manager.stop()
        notifications.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        XCTAssertEqual(system.attempts[.tileRight], 2)
        XCTAssertTrue(system.callbacks.isEmpty)
    }

    func testSystemConflictsAreNeverRegisteredAndSettingsChangesAreReconciled() {
        let system = FakeHotkeySystem()
        system.conflicts.insert(.captureArea)
        let manager = HotkeyManager(registrar: CarbonHotkeyRegistrar(api: system.api))
        defer { manager.stop() }
        var changes = 0
        manager.onChange = { changes += 1 }
        manager.start()
        XCTAssertNil(system.attempts[.captureArea])
        XCTAssertEqual(manager.issues, [.init(shortcut: .captureArea, failure: .systemConflict)])
        manager.refresh()
        XCTAssertEqual(changes, 1)

        system.conflicts.insert(.tileLeft)
        manager.refresh()
        XCTAssertNil(system.callbacks[.tileLeft])
        XCTAssertNotNil(system.callbacks[.tileRight])
        system.conflicts = []
        manager.refresh()
        XCTAssertNotNil(system.callbacks[.captureArea])
        XCTAssertNotNil(system.callbacks[.tileLeft])
        XCTAssertTrue(manager.issues.isEmpty)
        XCTAssertEqual(changes, 3)
    }

    func testFailedShortcutIsReportedAndRetriedWithoutReplacingWorkingShortcuts() {
        let system = FakeHotkeySystem()
        system.failures[.captureArea] = -9878
        let manager = HotkeyManager(registrar: CarbonHotkeyRegistrar(api: system.api))
        defer { manager.stop() }
        var actions: [HotkeyAction] = []
        manager.onAction = { actions.append($0) }
        manager.start()
        XCTAssertEqual(manager.issues, [.init(shortcut: .captureArea, failure: .registrationFailed(-9878))])
        system.press(.tileRight)
        XCTAssertEqual(actions, [.tile(.rightHalf)])
        system.failures = [:]
        manager.refresh()
        system.press(.captureArea)
        XCTAssertEqual(actions, [.tile(.rightHalf), .captureArea])
        XCTAssertTrue(manager.issues.isEmpty)
        XCTAssertEqual(system.attempts[.captureArea], 2)
        XCTAssertEqual(system.attempts[.tileRight], 1)
        manager.start()
        XCTAssertEqual(system.attempts[.tileRight], 1)
    }

    func testOldCallbacksCannotActAfterDisableReenableOrStop() {
        let system = FakeHotkeySystem()
        let manager = HotkeyManager(registrar: CarbonHotkeyRegistrar(api: system.api))
        var actions: [HotkeyAction] = []
        manager.onAction = { actions.append($0) }
        manager.start()
        let oldPress = system.callbacks[.tileLeft]!
        manager.tilingEnabled = false
        oldPress()
        manager.tilingEnabled = true
        oldPress()
        system.press(.tileLeft)
        let beforeStop = system.callbacks[.tileLeft]!
        manager.stop()
        beforeStop()
        XCTAssertTrue(system.callbacks.isEmpty)
        XCTAssertEqual(actions, [.tile(.leftHalf)])
    }

    func testFeatureTogglesReleaseTheirKeysAndKeepCaptureWorking() {
        let system = FakeHotkeySystem()
        let manager = HotkeyManager(registrar: CarbonHotkeyRegistrar(api: system.api))
        defer { manager.stop() }
        manager.tilingEnabled = false
        manager.clipboardHistoryEnabled = true
        manager.start()
        XCTAssertEqual(Set(system.callbacks.keys), [.captureFullScreen, .captureArea, .clipboardHistory])

        manager.clipboardHistoryEnabled = false
        manager.tilingEnabled = true
        XCTAssertEqual(Set(system.callbacks.keys), [.captureFullScreen, .captureArea, .tileLeft, .tileRight, .maximize, .center])
    }

    func testStartRegistersCaptureAndTilingAndDeliversActions() {
        let system = FakeHotkeySystem()
        let manager = HotkeyManager(registrar: CarbonHotkeyRegistrar(api: system.api))
        defer { manager.stop() }
        var actions: [HotkeyAction] = []
        manager.onAction = { actions.append($0) }

        manager.start()
        XCTAssertEqual(Set(system.callbacks.keys), [
            .captureFullScreen, .captureArea, .tileLeft, .tileRight, .maximize, .center
        ])
        system.press(.tileLeft)
        system.press(.captureArea)
        XCTAssertEqual(actions, [.tile(.leftHalf), .captureArea])
    }
}

@MainActor
private final class FakeHotkeySystem {
    private struct Registered {
        let id: EventHotKeyID
        let reference: EventHotKeyRef
    }

    var releaseFailures: Set<HotkeyShortcut> = []
    var lookupFailure: OSStatus?
    var handlerFailure: OSStatus?
    var eventSignature: OSType?
    var failures: [HotkeyShortcut: OSStatus] = [:]
    var conflicts: Set<HotkeyShortcut> = []
    var attempts: [HotkeyShortcut: Int] = [:]
    private var active: [HotkeyShortcut: Registered] = [:]
    private var handler: EventHandlerUPP?
    private var context: UnsafeMutableRawPointer?
    var reservedShortcuts: Set<HotkeyShortcut> { Set(active.keys) }

    var api: CarbonHotkeyAPI {
        CarbonHotkeyAPI(
            copySystemHotkeys: { array in
                if let failure = self.lookupFailure { return failure }
                let bindings: [[String: Any]] = self.conflicts.map {
                    [kHISymbolicHotKeyEnabled: true, kHISymbolicHotKeyCode: $0.keyCode,
                     kHISymbolicHotKeyModifiers: $0.modifiers]
                }
                array = Unmanaged.passRetained(bindings as CFArray)
                return noErr
            },
            register: { shortcut, id, reference in
                self.attempts[shortcut, default: 0] += 1
                if let failure = self.failures[shortcut] { return failure }
                guard self.active[shortcut] == nil else { return OSStatus(eventHotKeyExistsErr) }
                let ref = EventHotKeyRef(bitPattern: Int(id.id))!
                reference = ref
                self.active[shortcut] = Registered(id: id, reference: ref)
                return noErr
            },
            unregister: { reference in
                guard let shortcut = self.active.first(where: { $0.value.reference == reference })?.key else {
                    return OSStatus(eventHotKeyInvalidErr)
                }
                guard !self.releaseFailures.contains(shortcut) else { return OSStatus(paramErr) }
                self.active[shortcut] = nil
                return noErr
            },
            installHandler: { handler, context, reference in
                if let failure = self.handlerFailure { return failure }
                self.handler = handler
                self.context = context
                reference = EventHandlerRef(bitPattern: 1)!
                return noErr
            },
            removeHandler: { _ in
                self.handler = nil
                self.context = nil
                return noErr
            }
        )
    }

    var callbacks: [HotkeyShortcut: () -> Void] {
        guard let handler, let context else { return [:] }
        return active.mapValues { registration in
            return {
                var event: EventRef?
                precondition(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                                         GetCurrentEventTime(), 0, &event) == noErr)
                guard let event else { preconditionFailure("No event") }
                defer { ReleaseEvent(event) }
                var id = registration.id
                if let signature = self.eventSignature { id.signature = signature }
                precondition(SetEventParameter(event, EventParamName(kEventParamDirectObject),
                                               EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id) == noErr)
                _ = handler(nil, event, context)
            }
        }
    }

    func press(_ shortcut: HotkeyShortcut) { callbacks[shortcut]?() }
}
