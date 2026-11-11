import XCTest
@testable import Mysli

@MainActor
final class StatusMenuTests: XCTestCase {
    func testDictationMarkPreservesTheOtherThreeCorners() throws {
        let existing = sut.icon(keepAwakeActive: true, recording: .recording, warning: .shortcutsUnavailable)
        let listening = sut.icon(keepAwakeActive: true, recording: .recording,
                                 warning: .shortcutsUnavailable, dictationListening: true)
        for (x, y) in [(13, 4), (13, 13), (4, 13)] {
            XCTAssertEqual(pixel(of: listening, atX: x, y: y, in: .aqua),
                           pixel(of: existing, atX: x, y: y, in: .aqua))
        }
        XCTAssertNotEqual(pixel(of: listening, atX: 4, y: 4, in: .aqua),
                          pixel(of: existing, atX: 4, y: 4, in: .aqua))
    }
    private var meetingsRoot: URL!
    private var sut: StatusMenu!

    override func setUp() async throws {
        meetingsRoot = try makeTemporaryDirectory()
        let recorder = MeetingRecorder(
            permissions: PermissionsManager(isAccessibilityTrusted: { true }, hasScreenCaptureAccess: { true },
                                            microphoneAccess: { .granted }),
            root: { [unowned self] in meetingsRoot },
            capture: FakeMeetingAudioCapture(),
            notifier: FakeNotifier())
        let meetingNotes = MeetingNotesController(
            recorder: recorder,
            root: { [unowned self] in meetingsRoot },
            processor: makeMeetingProcessor(),
            wordsToCheck: { [unowned self] in WordReview.openQuestionCount(of: $0, in: meetingsRoot, knownWords: .empty) },
            summaryTool: { .automatic },
            notifier: FakeNotifier())
        let keepAwake = KeepAwakeController(wakeManager: WakeManager(preventer: FakeSleepPreventer()),
                                             keepDisplayAwake: true, notifier: FakeNotifier())
        sut = StatusMenu(sections: [keepAwake, meetingNotes])
    }

    private func item(titled title: String) -> NSMenuItem? {
        menuItems.first { $0.title == title }
    }

    private var menuItems: [NSMenuItem] { sut.menu.items }

    private func click(_ item: NSMenuItem) {
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
    }

    func testShowLogFollowsSettingsAndCallsItsAction() throws {
        let settings = try XCTUnwrap(menuItems.firstIndex { $0.title == "Settings…" })
        XCTAssertEqual(menuItems[settings + 1].title, "Show Log…")
        var shown = 0
        sut.onShowLog = { shown += 1 }
        click(try XCTUnwrap(item(titled: "Show Log…")))
        XCTAssertEqual(shown, 1)
    }

    func testRepeatedHealthDoesNotReplaceMenuItems() {
        let health = HotkeyHealth(issues: [.init(shortcut: .tileLeft, failure: .releaseFailed(-50))])
        sut.updateHotkeyHealth(health)
        let warning = sut.menu.items.first
        XCTAssertNotNil(item(titled: "⚠️ ⌃⌥← (tile left) could not be released"))
        XCTAssertNotNil(item(titled: "Mysli will retry automatically"))
        sut.updateHotkeyHealth(health)
        XCTAssertTrue(sut.menu.items.first === warning)
    }

    func testPermissionRecoveryKeepsTheShortcutWarningUntilRegistrationRecovers() {
        let issues = [HotkeyRegistrationIssue(shortcut: .captureArea, failure: .systemConflict)]
        sut.updateHotkeyHealth(.init(accessibilityMissing: true, issues: issues))
        sut.updateHotkeyHealth(.init(issues: issues))
        XCTAssertNil(item(titled: "⚠️ Window tiling and paste need Accessibility permission"))
        XCTAssertNotNil(item(titled: "⚠️ ⇧⌘4 (selected area) is used by macOS"))
        sut.updateHotkeyHealth(.healthy)
        XCTAssertFalse(menuItems.contains { $0.title.hasPrefix("⚠️") })
    }

    func testShortcutWarningsShowConflictsAndPermissionWithoutBlamingAnApp() {
        let health = HotkeyHealth(accessibilityMissing: true, issues: [
            .init(shortcut: .captureArea, failure: .systemConflict),
            .init(shortcut: .tileLeft, failure: .registrationFailed(-9878))
        ])
        sut.updateHotkeyHealth(health)
        XCTAssertNotNil(item(titled: "⚠️ ⇧⌘4 (selected area) is used by macOS"))
        XCTAssertNotNil(item(titled: "⚠️ Window tiling and paste need Accessibility permission"))
        XCTAssertNotNil(item(titled: "⚠️ ⌃⌥← (tile left) could not be registered"))
        XCTAssertNotNil(item(titled: "In Screenshots, turn off the matching macOS shortcut"))
        var opened = false
        sut.onOpenKeyboardSettings = { opened = true }
        click(item(titled: "Open Keyboard Settings…")!)
        XCTAssertTrue(opened)
        XCTAssertFalse(menuItems.contains { $0.title.contains("blocked by") || $0.title.contains("unlock") })
    }

    func testMenuEndsWithSettingsLogAndQuitAfterTheTools() throws {
        XCTAssertEqual(menuItems.suffix(4).map { $0.isSeparatorItem ? "-" : $0.title },
                       ["Settings…", "Show Log…", "-", "Quit Mysli"])
        XCTAssertNil(item(titled: "Mysli…"))
        XCTAssertNil(item(titled: "Permissions…"))
        XCTAssertNotNil(item(titled: "Start Recording Meeting"))
        var shown = 0
        sut.onShowSettings = { shown += 1 }
        click(try XCTUnwrap(item(titled: "Settings…")))
        XCTAssertEqual(shown, 1)
    }

    func testCommandCommaInApplicationMenuOpensSettings() throws {
        var opened = 0
        sut.onShowSettings = { opened += 1 }
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil, characters: ",", charactersIgnoringModifiers: ",",
            isARepeat: false, keyCode: 43))
        XCTAssertTrue(sut.applicationMenu().performKeyEquivalent(with: event))
        XCTAssertEqual(opened, 1)
    }

    func testMeetingNotesSectionFollowsKeepAwake() throws {
        let keepAwake = try XCTUnwrap(menuItems.firstIndex { $0.view is KeepAwakePanelView })
        let meetingNotes = try XCTUnwrap(menuItems.firstIndex { $0.title == "Meeting Notes" })
        let settings = try XCTUnwrap(menuItems.firstIndex { $0.title == "Settings…" })

        XCTAssertLessThan(keepAwake, meetingNotes)
        XCTAssertLessThan(meetingNotes, settings)
    }

    func testIconDiffersWhenKeepAwakeIsActive() {
        let plain = sut.icon(keepAwakeActive: false, recording: nil, warning: nil)
        let badged = sut.icon(keepAwakeActive: true, recording: nil, warning: nil)
        XCTAssertNotEqual(plain.tiffRepresentation, badged.tiffRepresentation)
    }

    func testRecordingAddsItsOwnDotNextToTheOthers() {
        let plain = sut.icon(keepAwakeActive: false, recording: nil, warning: nil)
        let recording = sut.icon(keepAwakeActive: false, recording: .recording, warning: nil)
        let others = sut.icon(keepAwakeActive: true, recording: nil, warning: .shortcutsUnavailable)
        let all = sut.icon(keepAwakeActive: true, recording: .recording, warning: .shortcutsUnavailable)

        XCTAssertNotEqual(plain.tiffRepresentation, recording.tiffRepresentation)
        XCTAssertNotEqual(others.tiffRepresentation, all.tiffRepresentation)
    }

    func testThePausedMarkDiffersFromTheRecordingMarkAndFromNoMark() {
        let plain = sut.icon(keepAwakeActive: false, recording: nil, warning: nil)
        let recording = sut.icon(keepAwakeActive: false, recording: .recording, warning: nil)
        let paused = sut.icon(keepAwakeActive: false, recording: .paused, warning: nil)

        XCTAssertNotEqual(paused.tiffRepresentation, recording.tiffRepresentation)
        XCTAssertNotEqual(paused.tiffRepresentation, plain.tiffRepresentation)
    }

    func testIconWithoutMarksIsATemplateSoMacOSColorsIt() {
        XCTAssertTrue(sut.icon(keepAwakeActive: false, recording: nil, warning: nil).isTemplate)
    }

    func testMarkedIconPaintsTheBowlInTheMenuBarTextColor() throws {
        let icon = sut.icon(keepAwakeActive: true, recording: nil, warning: nil)
        // (5, 12) in the 18-point icon is inside the bowl and outside every mark.
        let onDark = try XCTUnwrap(pixel(of: icon, atX: 5, y: 12, in: .darkAqua))
        let onLight = try XCTUnwrap(pixel(of: icon, atX: 5, y: 12, in: .aqua))
        XCTAssertGreaterThan(onDark.alphaComponent, 0.5)
        XCTAssertGreaterThan(onDark.brightnessComponent, 0.7)
        XCTAssertGreaterThan(onLight.alphaComponent, 0.5)
        XCTAssertLessThan(onLight.brightnessComponent, 0.3)
    }

    /// Draws `image` at 1 pixel per point under `appearance`; `y` counts down from the top edge.
    private func pixel(of image: NSImage, atX x: Int, y: Int, in appearance: NSAppearance.Name) -> NSColor? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 18, pixelsHigh: 18, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep),
              let named = NSAppearance(named: appearance) else { return nil }
        named.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            image.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
            NSGraphicsContext.restoreGraphicsState()
        }
        return rep.colorAt(x: x, y: y)
    }
}
