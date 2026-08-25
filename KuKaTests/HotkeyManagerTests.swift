import XCTest
@testable import KuKa

/// Tests feed synthetic key events straight into `HotkeyManager.handleEvent`
/// — no event tap, no Accessibility permission needed. What's under test is
/// the routing decision: which key combos get swallowed (returning nil tells
/// the tap to drop the event) and which pass through to other apps, and
/// which `HotkeyAction` each swallowed combo turns into.
final class HotkeyManagerTests: XCTestCase {
    private var manager: HotkeyManager!

    override func setUp() {
        super.setUp()
        manager = HotkeyManager()
    }

    /// Feeds one synthetic key press through `handleEvent` and reports
    /// whether it was swallowed (handleEvent returned nil). The Unmanaged
    /// return value never leaves this function: it holds the event pointer
    /// without retaining it, so letting an assertion stringify it after the
    /// event deallocates crashes the test host.
    private func isSwallowed(_ keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
        event.flags = flags
        return withExtendedLifetime(event) {
            manager.handleEvent(event) == nil
        }
    }

    private let tilingKeys: [(code: CGKeyCode, action: HotkeyAction, name: String)] = [
        (0x7B, .tile(.leftHalf), "left arrow"),
        (0x7C, .tile(.rightHalf), "right arrow"),
        (0x24, .tile(.maximize), "return"),
        (0x08, .tile(.center), "c"),
    ]
    private let ctrlOption: CGEventFlags = [.maskControl, .maskAlternate]

    // MARK: - Tiling enabled (default)

    func testTilingKeysAreSwallowedAndDeliverTheirActionsByDefault() {
        for (code, expected, name) in tilingKeys {
            let fired = expectation(description: "action delivered for \(name)")
            manager.onAction = { action in
                XCTAssertEqual(action, expected)
                fired.fulfill()
            }

            XCTAssertTrue(
                isSwallowed(code, flags: ctrlOption),
                "\(name) should be swallowed while tiling is enabled"
            )
            waitForExpectations(timeout: 1)
        }
    }

    // MARK: - Tiling disabled

    func testTilingKeysPassThroughWithoutDeliveringActionsWhenDisabled() {
        manager.tilingEnabled = false

        for (code, _, name) in tilingKeys {
            let notFired = expectation(description: "no action for \(name)")
            notFired.isInverted = true
            manager.onAction = { _ in notFired.fulfill() }

            XCTAssertFalse(
                isSwallowed(code, flags: ctrlOption),
                "\(name) should pass through to other apps while tiling is disabled"
            )
            waitForExpectations(timeout: 0.2)
        }
    }

    func testScreenshotHotkeysStillWorkWhenTilingIsDisabled() {
        manager.tilingEnabled = false

        let fired = expectation(description: "screenshot action delivered")
        manager.onAction = { action in
            XCTAssertEqual(action, .captureArea)
            fired.fulfill()
        }

        XCTAssertTrue(
            isSwallowed(0x15, flags: [.maskShift, .maskCommand]),
            "Shift+Cmd+4 should still be swallowed with tiling disabled"
        )
        waitForExpectations(timeout: 1)
    }

    func testReenablingTilingRestoresTheHotkeys() {
        manager.tilingEnabled = false
        manager.tilingEnabled = true

        let fired = expectation(description: "action delivered after re-enable")
        manager.onAction = { action in
            XCTAssertEqual(action, .tile(.leftHalf))
            fired.fulfill()
        }

        XCTAssertTrue(isSwallowed(0x7B, flags: ctrlOption))
        waitForExpectations(timeout: 1)
    }

    // MARK: - Clipboard history (Shift+Cmd+C)

    func testShiftCommandCRoutesToShowClipboardHistoryWhenEnabled() {
        manager.clipboardHistoryEnabled = true

        let fired = expectation(description: "clipboard history action delivered")
        manager.onAction = { action in
            XCTAssertEqual(action, .showClipboardHistory)
            fired.fulfill()
        }

        XCTAssertTrue(
            isSwallowed(0x08, flags: [.maskShift, .maskCommand]),
            "Shift+Cmd+C should be swallowed while clipboard history is enabled"
        )
        waitForExpectations(timeout: 1)
    }

    func testShiftCommandCPassesThroughWhenDisabled() {
        manager.clipboardHistoryEnabled = false

        // No expectation/wait needed: handleEvent only dispatches onAction
        // on the swallowed path, so a false isSwallowed already proves
        // synchronously that no delivery happens, ever — waiting out the
        // main-queue async would only prove the same thing more slowly.
        XCTAssertFalse(
            isSwallowed(0x08, flags: [.maskShift, .maskCommand]),
            "Shift+Cmd+C should pass through to other apps while clipboard history is disabled"
        )
    }

    func testShiftCommandCWithExtraModifiersPassesThrough() {
        manager.clipboardHistoryEnabled = true

        let extraModifierFlags: [(CGEventFlags, String)] = [
            ([.maskShift, .maskCommand, .maskControl], "Control"),
            ([.maskShift, .maskCommand, .maskAlternate], "Option"),
        ]

        for (flags, name) in extraModifierFlags {
            // No expectation/wait needed here either — see
            // testShiftCommandCPassesThroughWhenDisabled.
            XCTAssertFalse(
                isSwallowed(0x08, flags: flags),
                "Shift+Cmd+C with \(name) also held should pass through, not be treated as ours"
            )
        }
    }

    // MARK: - Existing combos unaffected by the clipboard history flag

    func testExistingCombosUnchangedInBothClipboardHistoryStates() {
        for clipboardHistoryEnabled in [true, false] {
            manager.clipboardHistoryEnabled = clipboardHistoryEnabled

            for (code, expected, name) in tilingKeys {
                let fired = expectation(
                    description: "tiling action for \(name) delivered (clipboardHistoryEnabled=\(clipboardHistoryEnabled))"
                )
                manager.onAction = { action in
                    XCTAssertEqual(action, expected)
                    fired.fulfill()
                }

                XCTAssertTrue(
                    isSwallowed(code, flags: ctrlOption),
                    "\(name) should still be swallowed (clipboardHistoryEnabled=\(clipboardHistoryEnabled))"
                )
                waitForExpectations(timeout: 1)
            }

            let screenshotFired = expectation(
                description: "screenshot action delivered (clipboardHistoryEnabled=\(clipboardHistoryEnabled))"
            )
            manager.onAction = { action in
                XCTAssertEqual(action, .captureArea)
                screenshotFired.fulfill()
            }

            XCTAssertTrue(
                isSwallowed(0x15, flags: [.maskShift, .maskCommand]),
                "Shift+Cmd+4 should still be swallowed (clipboardHistoryEnabled=\(clipboardHistoryEnabled))"
            )
            waitForExpectations(timeout: 1)
        }
    }
}
