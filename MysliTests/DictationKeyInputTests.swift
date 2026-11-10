import XCTest
@testable import Mysli

@MainActor
final class DictationKeyInputTests: XCTestCase {
    func testCarbonEscapeLifecycleFailureAndModeChange() throws {
        let system = FakeHotkeySystem()
        let manager = HotkeyManager(registrar: CarbonHotkeyRegistrar(api: system.api))
        manager.screenshotsEnabled = false
        manager.tilingEnabled = false
        manager.start()
        defer { manager.stop() }
        let source = FakeFnSource()
        let keys = SystemDictationKeyInput(manager: manager, source: source, mode: .carbon)
        var events: [DictationKeyEvent] = []
        try keys.start { events.append($0) }
        XCTAssertEqual(system.reservedShortcuts, [.dictation])
        system.failures[.dictationEscape] = -50
        XCTAssertThrowsError(try keys.setCancellable(true))
        XCTAssertEqual(system.reservedShortcuts, [.dictation])
        system.failures = [:]
        try keys.setCancellable(true)
        system.press(.dictationEscape)
        XCTAssertEqual(system.reservedShortcuts, [.dictation, .dictationEscape])
        try keys.setCancellable(false)
        XCTAssertEqual(system.reservedShortcuts, [.dictation])
        try keys.setCancellable(true)
        try keys.configure(mode: .fn)
        XCTAssertEqual(system.reservedShortcuts, [])
        XCTAssertEqual(events, [.cancelled, .cancelled])
        XCTAssertEqual(source.requests, 0)
        source.send(.flagsChanged(keyCode: 63, fn: true))
        keys.stop()
        XCTAssertEqual(events, [.cancelled, .cancelled, .pressed, .cancelled])
    }

    func testCarbonLossCancelsWorkAndUnregistersEscape() throws {
        let system = FakeHotkeySystem()
        let manager = HotkeyManager(registrar: CarbonHotkeyRegistrar(api: system.api))
        manager.start()
        defer { manager.stop() }
        let keys = SystemDictationKeyInput(manager: manager, source: FakeFnSource(), mode: .carbon)
        var events: [DictationKeyEvent] = []
        try keys.start { events.append($0) }
        try keys.setCancellable(true)
        manager.stop()
        XCTAssertEqual(events, [.unavailable])
        XCTAssertFalse(system.reservedShortcuts.contains(.dictationEscape))
    }
    func testFnRequiresPhysicalPressAndCancelsChordsUntilRelease() throws {
        let source = FakeFnSource()
        let keys = SystemDictationKeyInput(manager: HotkeyManager(), source: source)
        var events: [DictationKeyEvent] = []
        try keys.start { events.append($0) }
        source.send(.keyDown(123))
        source.send(.flagsChanged(keyCode: 123, fn: true))
        source.send(.flagsChanged(keyCode: 63, fn: true))
        source.send(.flagsChanged(keyCode: 63, fn: true))
        source.send(.keyDown(123))
        source.send(.flagsChanged(keyCode: 63, fn: true))
        source.send(.flagsChanged(keyCode: 63, fn: false))
        source.send(.flagsChanged(keyCode: 63, fn: true))
        source.send(.flagsChanged(keyCode: 63, fn: false))
        XCTAssertEqual(events, [.pressed, .cancelled, .pressed, .released])
    }

    func testFunctionRowAndOtherModifierCancelAndEscapeWorksAfterRelease() throws {
        let source = FakeFnSource()
        let keys = SystemDictationKeyInput(manager: HotkeyManager(), source: source)
        var events: [DictationKeyEvent] = []
        try keys.start { events.append($0) }
        for event in [FnKeyEvent.keyDown(96), .flagsChanged(keyCode: 96, fn: true)] { source.send(event) }
        source.send(.flagsChanged(keyCode: 63, fn: true))
        source.send(.keyDown(96))
        source.send(.flagsChanged(keyCode: 63, fn: false))
        source.send(.flagsChanged(keyCode: 63, fn: true))
        source.send(.flagsChanged(keyCode: 56, fn: true))
        source.send(.flagsChanged(keyCode: 63, fn: false))
        source.send(.flagsChanged(keyCode: 63, fn: true))
        source.send(.flagsChanged(keyCode: 63, fn: false))
        try keys.setCancellable(true)
        source.send(.keyDown(53))
        XCTAssertEqual(events, [.pressed, .cancelled, .pressed, .cancelled, .pressed, .released, .cancelled])
    }

    func testStopAndSourceFailureRejectStaleCallbacks() throws {
        let source = FakeFnSource()
        let keys = SystemDictationKeyInput(manager: HotkeyManager(), source: source)
        var events: [DictationKeyEvent] = []
        try keys.start { events.append($0) }
        let stale = source.receive!
        source.send(.flagsChanged(keyCode: 63, fn: true))
        source.send(.lost)
        XCTAssertThrowsError(try keys.setCancellable(true))
        stale(.flagsChanged(keyCode: 63, fn: false))
        try keys.start { events.append($0) }
        source.send(.flagsChanged(keyCode: 63, fn: true))
        keys.stop()
        stale(.flagsChanged(keyCode: 63, fn: true))
        XCTAssertEqual(events, [.pressed, .unavailable, .pressed, .cancelled])
    }

    func testStartChecksPermissionButOnlySetupRequestsIt() throws {
        let source = FakeFnSource()
        source.isAvailable = false
        let keys = SystemDictationKeyInput(manager: HotkeyManager(), source: source)
        XCTAssertThrowsError(try keys.start { _ in })
        XCTAssertEqual(source.requests, 0)
        XCTAssertFalse(keys.isAvailable)
        XCTAssertTrue(keys.requestPermission())
        XCTAssertEqual(source.requests, 1)
        try keys.start { _ in }
        XCTAssertTrue(keys.isAvailable)
        keys.stop()
    }

    func testSourceCreationFailureAndModeChangeInvalidateCallbacks() throws {
        let source = FakeFnSource()
        source.fails = true
        let keys = SystemDictationKeyInput(manager: HotkeyManager(), source: source)
        XCTAssertThrowsError(try keys.start { _ in })
        XCTAssertEqual(keys.failure, .source)
        source.fails = false
        var events: [DictationKeyEvent] = []
        try keys.start { events.append($0) }
        let stale = source.receive!
        source.send(.flagsChanged(keyCode: 63, fn: true))
        XCTAssertThrowsError(try keys.configure(mode: .carbon))
        stale(.flagsChanged(keyCode: 63, fn: true))
        XCTAssertEqual(events, [.pressed, .cancelled])
    }
}

@MainActor
final class FakeFnSource: FnEventSource {
    var isAvailable = true
    var requests = 0
    var fails = false
    var receive: ((FnKeyEvent) -> Void)?
    func requestPermission() -> Bool { requests += 1; isAvailable = true; return true }
    func start(_ receive: @escaping (FnKeyEvent) -> Void) throws {
        if fails { throw DictationKeyFailure.source }
        self.receive = receive
    }
    func stop() { receive = nil }
    func send(_ event: FnKeyEvent) { receive?(event) }
}
