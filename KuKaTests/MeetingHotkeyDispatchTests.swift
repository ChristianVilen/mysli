import Carbon.HIToolbox
import XCTest
@testable import KuKa

@MainActor
final class MeetingHotkeyDispatchTests: MeetingNotesTestCase {
    func testCarbonStartsRecordingAndTheOpenMenuKeyEquivalentStopsItOnce() async throws {
        var meetingID: EventHotKeyID?
        var api = CarbonHotkeyAPI()
        api.copySystemHotkeys = { bindings in
            bindings = Unmanaged.passRetained([] as CFArray)
            return noErr
        }
        api.register = { shortcut, id, reference in
            if shortcut == .meetingRecording { meetingID = id }
            reference = EventHotKeyRef(bitPattern: Int(id.id))
            return noErr
        }
        api.unregister = { _ in noErr }
        let manager = HotkeyManager(registrar: CarbonHotkeyRegistrar(api: api))
        let app = AppDelegate(hotkeyManager: manager, meetingRecorder: recorder)
        defer { manager.stop(); withExtendedLifetime(app) {} }
        menu.removeAllItems()
        let statusMenu = StatusMenu(settings: Settings(), sections: [sut],
                                    onTrackingChange: { manager.meetingMenuIsOpen = $0 })
        menu = statusMenu.menu
        manager.start()
        let id = try XCTUnwrap(meetingID)

        try postHotkey(id)
        await waitUntil { recorder.phase == .recording }
        XCTAssertEqual(recorder.phase, .recording)
        guard recorder.phase == .recording else { return }

        var sent = false
        var handled = false
        let key = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.control, .option],
            timestamp: 0, windowNumber: 0, context: nil, characters: "m",
            charactersIgnoringModifiers: "m", isARepeat: false, keyCode: 46))
        let menu = try XCTUnwrap(menu)
        let tick: @MainActor @Sendable () -> Void = {
            sent = true
            XCTAssertTrue(manager.meetingMenuIsOpen)
            handled = menu.performKeyEquivalent(with: key)
            menu.cancelTracking()
        }
        let timer = Timer(timeInterval: 0.02, repeats: false) { _ in
            MainActor.assumeIsolated { tick() }
        }
        RunLoop.main.add(timer, forMode: .eventTracking)
        defer { timer.invalidate() }
        menu.popUp(positioning: nil, at: NSPoint(x: 400, y: 400), in: nil)
        await waitUntil { recorder.phase == .idle }
        XCTAssertTrue(sent)
        XCTAssertTrue(handled)
        XCTAssertFalse(manager.meetingMenuIsOpen)
        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertEqual(capture.recordings.first?.stopCount, 1)
        await sut.waitUntilIdle()
    }

    private func postHotkey(_ id: EventHotKeyID) throws {
        var event: EventRef?
        XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                                   GetCurrentEventTime(), 0, &event), noErr)
        let eventRef = try XCTUnwrap(event)
        defer { ReleaseEvent(eventRef) }
        var id = id
        XCTAssertEqual(SetEventParameter(eventRef, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id), noErr)
        XCTAssertEqual(PostEventToQueue(GetMainEventQueue(), eventRef, Int16(kEventPriorityHigh)), noErr)
    }
}
