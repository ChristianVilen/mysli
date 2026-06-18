# Keep Awake Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a manual Amphetamine-style "Keep Awake" feature to Ku-Ka — a menu-bar toggle plus timed sessions that prevent the Mac's system idle sleep while AI agents run long tasks.

**Architecture:** A pure, clock-injectable `WakeSession` value type models session/expiry state (mirroring `ScrollTransform`). A `SleepPreventing` protocol seams the IOKit power assertion (mirroring `FileManaging`/`ClipboardManaging`), with `IOKitSleepPreventer` for production and `FakeSleepPreventer` for tests. `WakeManager` orchestrates session + preventer + expiry timer and reports state via closures. `AppDelegate` owns the manager and renders a "Keep Awake" `NSMenu` section, an active-state icon tint, a live countdown, and an expiry notification.

**Tech Stack:** Swift, AppKit/Cocoa, IOKit (`IOPMAssertionCreateWithName`), UserNotifications, XCTest. Built via Xcode (`KuKa.xcodeproj`, scheme `KuKa`).

---

## Critical build note (read before starting)

`KuKa.xcodeproj/project.pbxproj` uses **explicit file references** — it does NOT auto-include files on disk. Every new `.swift` file created in this plan MUST be added to the correct target before it will compile:

- App-code files (`WakeSession.swift`, `WakeManager.swift`) → **KuKa** target.
- Test files (`WakeSessionTests.swift`, `WakeManagerTests.swift`) → **KuKaTests** target.

Add them via Xcode (right-click the `KuKa` or `KuKaTests` group → *Add Files to "KuKa"…* → check the correct target), or by editing `project.pbxproj` to add the matching `PBXBuildFile`, `PBXFileReference`, group child, and Sources build-phase entries (use the existing `ScrollWheelManager.swift` / `ScrollTransformTests.swift` entries as the template). The build/test step in each task will fail loudly until this is done.

**Common commands used throughout:**

- Build app: `xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' build`
- Run all tests: `xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' test`
- Run one test class: append `-only-testing:KuKaTests/WakeSessionTests`

---

## Task 1: `WakeSession` — pure session/expiry model

**Files:**
- Create: `KuKa/WakeSession.swift`
- Test: `KuKaTests/WakeSessionTests.swift`

- [ ] **Step 1: Write the failing test**

Create `KuKaTests/WakeSessionTests.swift`:

```swift
import XCTest
@testable import KuKa

final class WakeSessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testIndefiniteHasNoExpiry() {
        let session = WakeSession(startedAt: start, duration: .indefinite)
        XCTAssertNil(session.expiresAt)
        XCTAssertNil(session.remaining(now: start))
        XCTAssertFalse(session.isExpired(now: start.addingTimeInterval(10_000)))
    }

    func testTimedExpiresAtStartPlusInterval() {
        let session = WakeSession(startedAt: start, duration: .timed(3600))
        XCTAssertEqual(session.expiresAt, start.addingTimeInterval(3600))
    }

    func testIsExpiredBeforeAtAndAfter() {
        let session = WakeSession(startedAt: start, duration: .timed(3600))
        XCTAssertFalse(session.isExpired(now: start.addingTimeInterval(3599)))
        XCTAssertTrue(session.isExpired(now: start.addingTimeInterval(3600)))
        XCTAssertTrue(session.isExpired(now: start.addingTimeInterval(3601)))
    }

    func testRemainingCountsDown() {
        let session = WakeSession(startedAt: start, duration: .timed(3600))
        XCTAssertEqual(session.remaining(now: start), 3600)
        XCTAssertEqual(session.remaining(now: start.addingTimeInterval(600)), 3000)
    }

    func testRemainingClampsToZero() {
        let session = WakeSession(startedAt: start, duration: .timed(3600))
        XCTAssertEqual(session.remaining(now: start.addingTimeInterval(5000)), 0)
    }
}
```

- [ ] **Step 2: Add the test file to the KuKaTests target**

In Xcode, add `KuKaTests/WakeSessionTests.swift` to the **KuKaTests** target (see Critical build note).

- [ ] **Step 3: Run the test to verify it fails**

Run: `xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' test -only-testing:KuKaTests/WakeSessionTests`
Expected: FAIL — compile error, `cannot find 'WakeSession' in scope`.

- [ ] **Step 4: Write the implementation**

Create `KuKa/WakeSession.swift`:

```swift
import Foundation

/// How long a keep-awake session should last.
enum WakeDuration: Equatable {
    case indefinite
    case timed(TimeInterval)
}

/// Pure, side-effect-free model of a keep-awake session. All time-dependent
/// queries take an explicit `now` so the logic is deterministically testable.
struct WakeSession: Equatable {
    let startedAt: Date
    let duration: WakeDuration

    var expiresAt: Date? {
        switch duration {
        case .indefinite:
            return nil
        case .timed(let interval):
            return startedAt.addingTimeInterval(interval)
        }
    }

    func isExpired(now: Date) -> Bool {
        guard let expiresAt = expiresAt else { return false }
        return now >= expiresAt
    }

    func remaining(now: Date) -> TimeInterval? {
        guard let expiresAt = expiresAt else { return nil }
        return max(0, expiresAt.timeIntervalSince(now))
    }
}
```

- [ ] **Step 5: Add the source file to the KuKa target**

In Xcode, add `KuKa/WakeSession.swift` to the **KuKa** target.

- [ ] **Step 6: Run the test to verify it passes**

Run: `xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' test -only-testing:KuKaTests/WakeSessionTests`
Expected: PASS — 5 tests pass.

- [ ] **Step 7: Commit**

```bash
git add KuKa/WakeSession.swift KuKaTests/WakeSessionTests.swift KuKa.xcodeproj/project.pbxproj
git commit -m "feat: add WakeSession pure model for keep-awake"
```

---

## Task 2: `SleepPreventing` seam + `IOKitSleepPreventer` + fake

**Files:**
- Create: `KuKa/WakeManager.swift` (protocol + IOKit implementation; `WakeManager` class added in Task 3)
- Modify: `KuKaTests/Mocks.swift` (add `FakeSleepPreventer`)

- [ ] **Step 1: Write the protocol and production implementation**

Create `KuKa/WakeManager.swift`:

```swift
import Foundation
import IOKit.pwr_mgt

/// Seam over the IOKit power assertion so the orchestration logic can be
/// tested without touching real system sleep state.
protocol SleepPreventing: AnyObject {
    /// Create the assertion if not already held. Idempotent.
    func begin(reason: String)
    /// Release the assertion if held. Idempotent.
    func end()
    var isPreventing: Bool { get }
}

/// Production implementation backed by `IOPMAssertionCreateWithName` with the
/// `PreventUserIdleSystemSleep` assertion type — keeps the system awake while
/// allowing the display to sleep.
final class IOKitSleepPreventer: SleepPreventing {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isPreventing = false

    func begin(reason: String) {
        guard !isPreventing else { return }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        if result == kIOReturnSuccess {
            assertionID = id
            isPreventing = true
        } else {
            NSLog("Ku-Ka: failed to create power assertion (code \(result))")
        }
    }

    func end() {
        guard isPreventing else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isPreventing = false
    }
}
```

- [ ] **Step 2: Add the source file to the KuKa target**

In Xcode, add `KuKa/WakeManager.swift` to the **KuKa** target.

- [ ] **Step 3: Add the fake to Mocks.swift**

Append to `KuKaTests/Mocks.swift`:

```swift
// MARK: - Fake Sleep Preventer

class FakeSleepPreventer: SleepPreventing {
    private(set) var beginCount = 0
    private(set) var endCount = 0
    private(set) var lastReason: String?
    private(set) var isPreventing = false

    func begin(reason: String) {
        guard !isPreventing else { return }
        isPreventing = true
        beginCount += 1
        lastReason = reason
    }

    func end() {
        guard isPreventing else { return }
        isPreventing = false
        endCount += 1
    }
}
```

- [ ] **Step 4: Verify it builds**

Run: `xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED. (No `WakeManager` class yet — that's Task 3. This step only confirms the protocol + IOKit type + fake compile.)

- [ ] **Step 5: Commit**

```bash
git add KuKa/WakeManager.swift KuKaTests/Mocks.swift KuKa.xcodeproj/project.pbxproj
git commit -m "feat: add SleepPreventing seam and IOKit power-assertion impl"
```

---

## Task 3: `WakeManager` orchestration

**Files:**
- Modify: `KuKa/WakeManager.swift` (add `WakeManager` class)
- Test: `KuKaTests/WakeManagerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `KuKaTests/WakeManagerTests.swift`:

```swift
import XCTest
@testable import KuKa

final class WakeManagerTests: XCTestCase {
    private var clock: Date!
    private var preventer: FakeSleepPreventer!
    private var manager: WakeManager!

    override func setUp() {
        super.setUp()
        clock = Date(timeIntervalSince1970: 1_000_000)
        preventer = FakeSleepPreventer()
        manager = WakeManager(preventer: preventer, now: { self.clock })
    }

    func testActivateIndefiniteBeginsPreventionAndIsActive() {
        var stateChanges = 0
        manager.onStateChange = { stateChanges += 1 }

        manager.activate(.indefinite)

        XCTAssertTrue(manager.isActive)
        XCTAssertEqual(preventer.beginCount, 1)
        XCTAssertEqual(preventer.endCount, 0)
        XCTAssertEqual(stateChanges, 1)
        XCTAssertNil(manager.session?.expiresAt)
    }

    func testManualDeactivateEndsPreventionWithoutFiringExpiry() {
        var expired = false
        manager.onExpire = { expired = true }

        manager.activate(.indefinite)
        manager.deactivate()

        XCTAssertFalse(manager.isActive)
        XCTAssertEqual(preventer.endCount, 1)
        XCTAssertFalse(expired)
    }

    func testReactivateKeepsSingleAssertion() {
        manager.activate(.timed(3600))
        manager.activate(.timed(7200))

        XCTAssertEqual(preventer.beginCount, 1) // begin is idempotent; no double-assert
        XCTAssertEqual(preventer.endCount, 0)
        XCTAssertTrue(manager.isActive)
        XCTAssertEqual(manager.session?.duration, .timed(7200))
    }

    func testDoubleDeactivateIsBalanced() {
        manager.activate(.indefinite)
        manager.deactivate()
        manager.deactivate()

        XCTAssertEqual(preventer.beginCount, 1)
        XCTAssertEqual(preventer.endCount, 1)
    }

    func testTimedSessionExpiresAndFiresCallbacks() {
        var expired = false
        manager.onExpire = { expired = true }

        let done = expectation(description: "timed session expires")
        manager.onStateChange = {
            if !self.manager.isActive { done.fulfill() }
        }

        manager.activate(.timed(0.2))
        wait(for: [done], timeout: 2.0)

        XCTAssertFalse(manager.isActive)
        XCTAssertEqual(preventer.endCount, 1)
        XCTAssertTrue(expired)
    }
}
```

- [ ] **Step 2: Add the test file to the KuKaTests target**

In Xcode, add `KuKaTests/WakeManagerTests.swift` to the **KuKaTests** target.

- [ ] **Step 3: Run the test to verify it fails**

Run: `xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' test -only-testing:KuKaTests/WakeManagerTests`
Expected: FAIL — compile error, `cannot find 'WakeManager' in scope`.

- [ ] **Step 4: Write the implementation**

Append the `WakeManager` class to `KuKa/WakeManager.swift`:

```swift
/// Orchestrates a keep-awake session: drives the `SleepPreventing` seam,
/// schedules expiry for timed sessions, and reports state via closures.
/// Not thread-safe; intended to be used from the main thread.
final class WakeManager {
    private let preventer: SleepPreventing
    private let now: () -> Date
    private var timer: Timer?

    private(set) var session: WakeSession?
    var isActive: Bool { session != nil }

    /// Fired whenever the active/inactive state or session changes.
    var onStateChange: (() -> Void)?
    /// Fired only when a timed session reaches its expiry (not on manual off).
    var onExpire: (() -> Void)?

    init(preventer: SleepPreventing = IOKitSleepPreventer(), now: @escaping () -> Date = { Date() }) {
        self.preventer = preventer
        self.now = now
    }

    func activate(_ duration: WakeDuration) {
        timer?.invalidate()
        timer = nil

        let session = WakeSession(startedAt: now(), duration: duration)
        self.session = session
        preventer.begin(reason: "Ku-Ka Keep Awake")

        if let expiresAt = session.expiresAt {
            let interval = max(0, expiresAt.timeIntervalSince(now()))
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                self?.deactivate(expired: true)
            }
        }

        onStateChange?()
    }

    func deactivate(expired: Bool = false) {
        guard session != nil else { return }
        timer?.invalidate()
        timer = nil
        preventer.end()
        session = nil
        onStateChange?()
        if expired { onExpire?() }
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' test -only-testing:KuKaTests/WakeManagerTests`
Expected: PASS — 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add KuKa/WakeManager.swift KuKaTests/WakeManagerTests.swift KuKa.xcodeproj/project.pbxproj
git commit -m "feat: add WakeManager orchestration with timed expiry"
```

---

## Task 4: Menu section + activation wiring in AppDelegate

**Files:**
- Modify: `KuKa/AppDelegate.swift`

This task and the next three are AppKit UI wiring that is not unit-tested (consistent with the existing app: `AppDelegate` has no unit tests). Each is verified by building and running the app.

- [ ] **Step 1: Add properties**

In `KuKa/AppDelegate.swift`, add to the property block near the top of the class (after line 16, `private var linesPerTickItems: [NSMenuItem] = []`):

```swift
    private let wakeManager = WakeManager()
    private var keepAwakeHeaderItem: NSMenuItem!
    private var keepAwakeTurnOffItem: NSMenuItem!
    private var keepAwakePresetItems: [NSMenuItem] = []
    private var menuCountdownTimer: Timer?
```

- [ ] **Step 2: Wire the manager callbacks at launch**

In `applicationDidFinishLaunching(_:)`, add a call after `setupThumbnailStack()`:

```swift
        setupWakeManager()
```

Then add the method (place it after `setupThumbnailStack()`'s definition):

```swift
    private func setupWakeManager() {
        wakeManager.onStateChange = { [weak self] in self?.refreshKeepAwakeUI() }
        wakeManager.onExpire = { [weak self] in self?.notifyKeepAwakeEnded() }
    }
```

- [ ] **Step 3: Build the Keep Awake menu section**

In `setupMenuBar()`, locate the separator that follows the Thumbnail Duration block (the `menu.addItem(.separator())` immediately before the `// --- Scroll Wheel ---` comment). Insert this block right after that separator and before `// --- Scroll Wheel ---`:

```swift
        // --- Keep Awake ---
        let keepAwakeLabel = NSMenuItem(title: "Keep Awake", action: nil, keyEquivalent: "")
        keepAwakeLabel.isEnabled = false
        menu.addItem(keepAwakeLabel)

        keepAwakeHeaderItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        keepAwakeHeaderItem.isEnabled = false
        keepAwakeHeaderItem.isHidden = true
        menu.addItem(keepAwakeHeaderItem)

        keepAwakeTurnOffItem = NSMenuItem(title: "Turn Off", action: #selector(turnOffKeepAwake), keyEquivalent: "")
        keepAwakeTurnOffItem.target = self
        keepAwakeTurnOffItem.isHidden = true
        menu.addItem(keepAwakeTurnOffItem)

        let keepAwakeForItem = NSMenuItem(title: "Keep Awake For", action: nil, keyEquivalent: "")
        let keepAwakeMenu = NSMenu()
        for (title, minutes) in [("30 minutes", 30), ("1 hour", 60), ("2 hours", 120), ("4 hours", 240), ("Until I turn it off", 0)] {
            let item = NSMenuItem(title: title, action: #selector(selectKeepAwakeDuration(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            keepAwakeMenu.addItem(item)
            keepAwakePresetItems.append(item)
        }
        keepAwakeForItem.submenu = keepAwakeMenu
        menu.addItem(keepAwakeForItem)

        let lidHintItem = NSMenuItem(title: "Closing the lid still sleeps your Mac", action: nil, keyEquivalent: "")
        lidHintItem.isEnabled = false
        lidHintItem.indentationLevel = 1
        menu.addItem(lidHintItem)

        menu.addItem(.separator())
```

- [ ] **Step 4: Add the action methods**

Add these methods to `AppDelegate` (place them after the `changeLinesPerTick(_:)` method):

```swift
    // MARK: - Keep Awake

    @objc private func selectKeepAwakeDuration(_ sender: NSMenuItem) {
        let duration: WakeDuration = sender.tag == 0
            ? .indefinite
            : .timed(TimeInterval(sender.tag * 60))
        if sender.tag != 0 {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        wakeManager.activate(duration)
    }

    @objc private func turnOffKeepAwake() {
        wakeManager.deactivate()
    }

    private func refreshKeepAwakeUI() {
        updateKeepAwakeMenu()
        updateStatusItemIcon()
    }

    private func updateKeepAwakeMenu() {
        let active = wakeManager.isActive
        keepAwakeHeaderItem.isHidden = !active
        keepAwakeTurnOffItem.isHidden = !active

        if active, let session = wakeManager.session {
            if let remaining = session.remaining(now: Date()) {
                keepAwakeHeaderItem.title = "☕ Awake · \(Self.formatRemaining(remaining))"
            } else {
                keepAwakeHeaderItem.title = "☕ Awake · On"
            }
        }

        let activeTag = activeKeepAwakeTag()
        for item in keepAwakePresetItems {
            item.state = (active && item.tag == activeTag) ? .on : .off
        }
    }

    private func activeKeepAwakeTag() -> Int {
        guard let session = wakeManager.session else { return -1 }
        switch session.duration {
        case .indefinite: return 0
        case .timed(let interval): return Int(interval / 60)
        }
    }

    static func formatRemaining(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(ceil(interval / 60))
        if totalMinutes <= 0 { return "less than a minute left" }
        if totalMinutes < 60 { return "\(totalMinutes) min left" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours)h left" : "\(hours)h \(minutes)m left"
    }
```

- [ ] **Step 5: Add the UserNotifications import**

At the top of `KuKa/AppDelegate.swift`, below `import ServiceManagement`, add:

```swift
import UserNotifications
```

(`notifyKeepAwakeEnded()` and `updateStatusItemIcon()` are added in Tasks 7 and 5 respectively. To build and test Task 4 in isolation, temporarily stub them at the end of the class — they are replaced with real bodies later:)

```swift
    private func updateStatusItemIcon() {}
    private func notifyKeepAwakeEnded() {}
```

- [ ] **Step 6: Build and run, verify menu behavior**

Run: `xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

Then run the app from Xcode (`Cmd+R`) and verify by hand:
- The menu shows a "Keep Awake" section with a "Keep Awake For" submenu and the lid-close hint row.
- Picking "1 hour" makes the header row ("☕ Awake · 59 min left") and "Turn Off" appear, and "1 hour" gets a checkmark.
- "Turn Off" hides the header/Turn-Off rows and clears the checkmark.
- With Keep Awake on, run `pmset -g assertions` in Terminal and confirm a `PreventUserIdleSystemSleep` assertion named "Ku-Ka Keep Awake" is listed; confirm it disappears after Turn Off.

- [ ] **Step 7: Commit**

```bash
git add KuKa/AppDelegate.swift
git commit -m "feat: add Keep Awake menu section and activation wiring"
```

---

## Task 5: Active-state menu-bar icon

**Files:**
- Modify: `KuKa/AppDelegate.swift`

- [ ] **Step 1: Make the icon a template image**

In `setupMenuBar()`, in the block that sets `button.image` from `MenuBarIcon` (currently sets `icon.size` then `button.image = icon`), mark the image as a template so it tints correctly. Change:

```swift
            if let icon = NSImage(named: "MenuBarIcon") {
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            } else {
```

to:

```swift
            if let icon = NSImage(named: "MenuBarIcon") {
                icon.size = NSSize(width: 18, height: 18)
                icon.isTemplate = true
                button.image = icon
            } else {
```

- [ ] **Step 2: Replace the stubbed `updateStatusItemIcon()` with the real body**

Replace the temporary stub from Task 4 (`private func updateStatusItemIcon() {}`) with:

```swift
    private func updateStatusItemIcon() {
        guard let button = statusItem.button else { return }
        button.contentTintColor = wakeManager.isActive ? .controlAccentColor : nil
    }
```

- [ ] **Step 3: Build and run, verify icon state**

Run: `xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

Run the app (`Cmd+R`) and verify by hand:
- Turning Keep Awake on tints the menu-bar icon with the system accent color.
- Turning it off returns the icon to its normal monochrome appearance.

- [ ] **Step 4: Commit**

```bash
git add KuKa/AppDelegate.swift
git commit -m "feat: tint menu-bar icon while Keep Awake is active"
```

---

## Task 6: Live countdown while the menu is open

**Files:**
- Modify: `KuKa/AppDelegate.swift`

- [ ] **Step 1: Make AppDelegate the menu delegate**

In `setupMenuBar()`, immediately before the final `statusItem.menu = menu`, add:

```swift
        menu.delegate = self
```

- [ ] **Step 2: Conform to `NSMenuDelegate`**

Change the class declaration:

```swift
class AppDelegate: NSObject, NSApplicationDelegate {
```

to:

```swift
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
```

- [ ] **Step 3: Add the delegate methods**

Add to `AppDelegate` (after `updateKeepAwakeMenu()`):

```swift
    func menuWillOpen(_ menu: NSMenu) {
        updateKeepAwakeMenu()
        guard wakeManager.isActive, wakeManager.session?.expiresAt != nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateKeepAwakeMenu()
        }
        // .common mode so it keeps firing while the menu tracks events.
        RunLoop.current.add(timer, forMode: .common)
        menuCountdownTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        menuCountdownTimer?.invalidate()
        menuCountdownTimer = nil
    }
```

- [ ] **Step 4: Build and run, verify the countdown ticks**

Run: `xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

Run the app (`Cmd+R`), start a timed session (e.g. 30 minutes), open the menu and keep it open: the "☕ Awake · N min left" header updates as time passes. Closing and reopening the menu still shows the correct remaining time.

- [ ] **Step 5: Commit**

```bash
git add KuKa/AppDelegate.swift
git commit -m "feat: live countdown in Keep Awake menu while open"
```

---

## Task 7: Expiry notification

**Files:**
- Modify: `KuKa/AppDelegate.swift`

- [ ] **Step 1: Replace the stubbed `notifyKeepAwakeEnded()` with the real body**

Replace the temporary stub from Task 4 (`private func notifyKeepAwakeEnded() {}`) with:

```swift
    private func notifyKeepAwakeEnded() {
        let content = UNMutableNotificationContent()
        content.title = "Ku-Ka"
        content.body = "Keep-awake ended — your Mac can sleep again."
        let request = UNNotificationRequest(
            identifier: "keepAwakeEnded",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
```

- [ ] **Step 2: Build and run, verify the notification**

Run: `xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

Run the app (`Cmd+R`). The first time you start a timed session, macOS prompts for notification permission — allow it. Start a very short timed session for testing — temporarily add a `("10 seconds", -10)`-style preset is NOT needed; instead start "30 minutes" and confirm authorization is requested. To verify delivery without waiting, you may temporarily change one preset's `minutes` to a tiny value (e.g. via debugger or a throwaway edit), confirm the banner "Keep-awake ended — your Mac can sleep again." appears at expiry, then revert. Manual "Turn Off" must NOT produce a notification.

- [ ] **Step 3: Commit**

```bash
git add KuKa/AppDelegate.swift
git commit -m "feat: notify when a timed Keep Awake session ends"
```

---

## Task 8: Release assertion on quit

**Files:**
- Modify: `KuKa/AppDelegate.swift`

- [ ] **Step 1: Add `applicationWillTerminate`**

Add this method to `AppDelegate` (near `applicationDidFinishLaunching`):

```swift
    func applicationWillTerminate(_ notification: Notification) {
        wakeManager.deactivate()
    }
```

- [ ] **Step 2: Build and run, verify cleanup**

Run: `xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

Run the app (`Cmd+R`), turn Keep Awake on, confirm the assertion via `pmset -g assertions`, then Quit Ku-Ka. Confirm the `PreventUserIdleSystemSleep` "Ku-Ka Keep Awake" assertion is gone.

- [ ] **Step 3: Commit**

```bash
git add KuKa/AppDelegate.swift
git commit -m "feat: release Keep Awake assertion on app quit"
```

---

## Task 9: Documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add the feature to the README**

In `README.md`, under the `## Features` list, add a bullet after the "Launch at Login toggle" line:

```markdown
- Keep Awake — prevent the Mac from sleeping while long AI-agent tasks run, via a menu-bar toggle and timed sessions (30 min / 1 hr / 2 hr / 4 hr / until off)
```

Then add a section after the Features list:

```markdown
## Keep Awake

Ku-Ka can stop your Mac from going to sleep while a long-running task (for example an AI coding agent) works. Open the menu bar item and choose **Keep Awake For** a preset duration, or "Until I turn it off". The menu-bar icon is tinted while active, and the menu shows a live countdown.

This prevents *system* idle sleep — the display is still free to sleep, which saves power. Note that **closing a laptop's lid still puts the Mac to sleep** unless it is on AC power with an external display attached; no app can override that through public macOS APIs. Use it with the lid open or docked for overnight runs.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: document the Keep Awake feature"
```

---

## Final verification

- [ ] **Run the full test suite**

Run: `xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' test`
Expected: all tests pass, including `WakeSessionTests` (5) and `WakeManagerTests` (5).

- [ ] **Full manual smoke test**

Run the app and confirm end-to-end: toggle on (indefinite) → icon tints, assertion present → Turn Off → assertion gone; timed session → countdown ticks in the open menu → expiry fires the notification and clears state; quit while active releases the assertion.
