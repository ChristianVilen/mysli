# Keep Awake — Design

**Date:** 2026-06-17
**Status:** Approved (pending spec review)
**Branch:** `sleep-prevention`

## Summary

Add an Amphetamine-style "keep the Mac awake" feature to Ku-Ka, aimed at a developer
running long-living AI-agent tasks who needs the machine to stay running while it works.
The feature is **manual** (the user is in control): a quick on/off toggle plus timed
sessions. It prevents *system* idle sleep only; the display is free to sleep.

This is deliberately not AI-detection-driven. The user chose the reliable, predictable
manual model over heuristic process detection or hook-based automation.

## Goals

- A one-click "keep awake until I turn it off" toggle.
- Timed sessions with presets (30 min / 1 hr / 2 hr / 4 hr / until I turn it off) and a
  live countdown.
- Keep the system (CPU, network, running agents) awake; allow the display to sleep.
- At-a-glance state from the menu bar icon.
- Clear, honest communication of the one thing this cannot do (lid-close sleep).

## Non-goals

- No automatic detection of AI-agent processes (deferred; may be a future opt-in).
- No hook/CLI integration for agents.
- No global hotkey (deferred).
- No "keep awake while app X is frontmost" (deferred).
- No persistence of an *active* session across app launches.

## Mechanism

A single IOKit power assertion:

- Type: `kIOPMAssertionTypePreventUserIdleSystemSleep`.
- Created with `IOPMAssertionCreateWithName(...)`, released with `IOPMAssertionRelease(...)`.
- This is exactly what `caffeinate` (without `-d`) and Amphetamine's system-sleep mode use.
- The display is intentionally **not** held awake — saves power and OLED wear, which is
  the right default for an unattended long agent run.

## Architecture

Follows the established Ku-Ka pattern: one focused manager class per feature, owned by
`AppDelegate`, communicating state changes back via a closure. Pure logic is extracted
into a separate testable type, mirroring `ScrollTransform` / `ScrollTransformSettings`.

### Components

**`WakeSession` (pure, testable) — new file `KuKa/WakeSession.swift`**

A value type that models session state with no side effects, so timer/expiry logic is
unit-testable with an injected clock (the `ScrollTransform` precedent).

```
enum WakeDuration: Equatable {
    case indefinite
    case timed(TimeInterval)   // e.g. 1800, 3600, 7200, 14400
}

struct WakeSession: Equatable {
    let startedAt: Date
    let duration: WakeDuration

    var expiresAt: Date?                 // nil when .indefinite
    func isExpired(now: Date) -> Bool
    func remaining(now: Date) -> TimeInterval?   // nil when .indefinite
}
```

**`SleepPreventing` protocol + `IOKitSleepPreventer` — in `KuKa/WakeManager.swift`**

Thin seam over IOKit so tests inject a fake and never create real assertions.

```
protocol SleepPreventing: AnyObject {
    func begin(reason: String)   // create assertion if not already held
    func end()                   // release assertion if held
    var isPreventing: Bool { get }
}
```

`IOKitSleepPreventer` is the production implementation wrapping `IOPMAssertionCreateWithName`
/ `IOPMAssertionRelease`. It is idempotent: `begin` while already preventing is a no-op;
`end` while not preventing is a no-op.

**`WakeManager` — new file `KuKa/WakeManager.swift`**

Orchestrates session + preventer + timer. Owned by `AppDelegate`.

- State: `private(set) var session: WakeSession?`, derived `var isActive: Bool`.
- `func activate(_ duration: WakeDuration)` — sets `session`, calls `preventer.begin`,
  schedules a `Timer` for `.timed` (fires at expiry → `deactivate(expired: true)`).
  Re-activating while active replaces the session and resets the timer.
- `func deactivate(expired: Bool = false)` — invalidates timer, calls `preventer.end`,
  clears `session`, fires `onExpire` callback if `expired`.
- `var onStateChange: (() -> Void)?` — `AppDelegate` repaints menu + icon.
- `var onExpire: (() -> Void)?` — `AppDelegate` posts the expiry notification.
- Dependencies injected via init (`SleepPreventing`, a clock closure `() -> Date`) with
  production defaults, so unit tests pass fakes.
- Released defensively on app terminate (IOKit also auto-releases on process exit).

### AppDelegate wiring

- Owns a `WakeManager` instance (alongside the existing managers).
- New "Keep Awake" `NSMenu` section inserted above "Scroll Wheel".
- Implements `NSMenuDelegate.menuWillOpen` to render the current countdown fresh, plus a
  1 s repeating `Timer` that updates the countdown title *only while the menu is open*
  (invalidated in `menuDidClose`).
- Updates the status-item button image on every `onStateChange`.
- Persists the last-chosen timed preset to `UserDefaults` (key `keepAwakeDefaultDuration`);
  does **not** persist active state.

## Menu UX

```
Keep Awake
  ☕ Awake · 47 min left          ← shown only when active ("On" when indefinite)
  ──────
  Turn Off                       ← shown only when active
  Keep Awake For ▸
      30 minutes
      1 hour
      2 hours
      4 hours
      Until I turn it off
  Closing the lid still sleeps    ← subtle disabled hint row (see Limitations)
```

- Inactive: header + "Turn Off" hidden; "Keep Awake For ▸" is the entry point.
- Selecting a preset (or re-selecting a different one) activates / resets the session.
- A checkmark marks the currently active preset inside the submenu.

## Menu-bar icon state

- Idle: the existing `MenuBarIcon`.
- Active: a visually distinct variant (filled/tinted version, or the base icon with a
  small badge dot) so state is readable from the menu bar without opening the menu.
- Implementation detail (filled asset vs. programmatic tint/badge) is left to the
  implementation plan; the requirement is a clear, continuous active/idle distinction.

## Notifications

When a **timed** session reaches expiry, post a single quiet `UNUserNotification`:
"Ku-Ka: keep-awake ended — your Mac can sleep again." Indefinite sessions and manual
"Turn Off" do not notify. Requires user notification authorization, requested lazily the
first time a timed session is started.

## Limitations (stated honestly)

- Prevents **idle** sleep only. On a laptop, **closing the lid still sleeps the Mac**
  unless on AC power with an external display attached. No public API overrides clamshell
  sleep (Amphetamine included). Surfaced as a subtle disabled hint row in the menu.

## Edge cases

- Activate while already active → replace session, reset timer, keep a single assertion.
- "Until I turn it off" → no timer; clears any existing timer.
- Quit while active → assertion released in `applicationWillTerminate`.
- Timer fires → release assertion, clear state, repaint, post expiry notification.
- Notification authorization denied → feature still works silently; no error surfaced.

## Testing

Tests added to the existing `KuKaTests` target (XCTest), following `ScrollTransformTests`:

- `WakeSessionTests`:
  - `expiresAt` is `nil` for `.indefinite`, `startedAt + interval` for `.timed`.
  - `isExpired(now:)` false before expiry, true at/after expiry.
  - `remaining(now:)` counts down correctly and is `nil` for `.indefinite`.
- `WakeManagerTests` (with a `FakeSleepPreventer` and an injected clock):
  - `activate(.indefinite)` → preventer `begin` called once, `isActive == true`, no expiry.
  - `activate(.timed)` then advancing the clock past expiry → `deactivate(expired:true)`,
    preventer `end` called, `onExpire` fired.
  - Re-activating while active → preventer still holds exactly one assertion (no double
    `begin`), session replaced.
  - `deactivate()` (manual) → preventer `end`, `onExpire` NOT fired.
  - Idempotency: double `activate` / double `deactivate` don't unbalance begin/end.

IOKit is never exercised in tests — only the `SleepPreventing` seam is.

## Files touched

- `KuKa/WakeSession.swift` (new) — pure session/expiry model.
- `KuKa/WakeManager.swift` (new) — manager + `SleepPreventing` + `IOKitSleepPreventer`.
- `KuKa/AppDelegate.swift` — menu section, icon state, menu-open countdown timer, terminate cleanup.
- `KuKaTests/WakeSessionTests.swift` (new).
- `KuKaTests/WakeManagerTests.swift` (new).
- `README.md` — document the feature (and its lid-close limitation).
- Possibly `KuKa/Assets.xcassets` — an active-state menu-bar icon variant (if the asset
  approach is chosen over programmatic tint/badge).
