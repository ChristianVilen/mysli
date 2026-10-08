# Registered hotkeys implementation plan

**Goal:** Keep Ku-Ka shortcuts available during Secure Input and report shortcut
failures without blaming another app.

**Architecture:** HotkeyManager supplies desired shortcuts and schedules retries.
CarbonHotkeyRegistrar owns all registration state and applies that desired set.
AppDelegate builds the menu's health value directly from current owners.

**Tech stack:** Swift 5 language mode, macOS 26.0+, Xcode 26+ / Swift 6.2+,
AppKit, Carbon, XCTest.

**Spec:** [Registered hotkeys design](../specs/2026-09-18-registered-hotkeys-design.md).

## Constraints

- Keep all seven existing combinations and feature toggle defaults.
- Use public APIs; do not change macOS shortcut preferences.
- Keep real shortcut registration behind AppDelegate's test-mode guard.
- Add no package dependency or manual Xcode source-file entries.
- Use TDD at the public lifecycle, feature toggles, action callback, and failure
  reporting boundary. Replace OS calls in tests, not registration logic.

## 1. Register shortcuts and recover failures

Files: `KuKa/HotkeyManager.swift`, `KuKa/HotkeyRegistration.swift`,
`KuKa/HotkeyShortcut.swift`, `KuKa/CarbonHotkeyAPI.swift`,
`KuKaTests/HotkeyManagerTests.swift`.

- [x] Verify the old behavior, then run failing regression tests before fixes.
- [x] Define the seven combinations, labels, actions, and failure cases.
- [x] Register exclusively with Carbon and reject enabled system conflicts.
- [x] Retain working registrations during normal refresh; retry failed ones.
- [x] Release shortcuts when a feature is disabled, and renew them after wake.
- [x] Stop timers/observers and clean up registrations on stop and deinit.
- [x] Verify registration, toggles, stale events, partial failures, and recovery.

## 2. Report current status and guide setup

Files: `KuKa/HotkeyHealth.swift`, `KuKa/StatusMenu.swift`,
`KuKa/AppDelegate.swift`, `KuKa/PermissionsManager.swift`,
`KuKa/OnboardingWindowController.swift`, `KuKaTests/StatusMenuTests.swift`.

- [x] Remove Secure Input polling, cached app attribution, and dwell timers.
- [x] Show each shortcut problem alongside missing Accessibility permission.
- [x] Add Keyboard Settings guidance for conflicting macOS bindings.
- [x] Register independently of Accessibility while preserving the test guard.
- [x] Update permission descriptions for window movement and clipboard paste.
- [x] Verify warnings, partial recovery, setup actions, and cleanup.

## 3. Approved judo findings

### B1: One owner for registration state

The user approved this follow-up before implementation.

- [x] Write a regression where release fails after disabling tiling. Observe the
  old manager incorrectly report no issues.
- [x] Give `CarbonHotkeyRegistrar` the complete reconciliation operation:

```swift
func reconcile(desired: Set<HotkeyShortcut>) -> [HotkeyRegistrationIssue]
@discardableResult func stop() -> [HotkeyRegistrationIssue]
```

- [x] Store active and pending-release entries in one map in the registrar.
- [x] Remove the manager's registration map, UUID generations, and release-retry
  protocol. Fresh Carbon event IDs reject stale input.
- [x] Report `releaseFailed(OSStatus)` even when a shortcut is no longer desired.
  Do not register the same combination until its pending release succeeds.
- [x] Introduce `CarbonHotkeyAPI`, a value containing five injectable native
  calls. Existing lifecycle tests now exercise the real registrar.
- [x] Verify failed-release visibility, rejected callbacks, recovery, and
  repeated stop completing a pending release.

### B2: Remove cached health monitoring

- [x] Write a failing test proving repeated health updates replace menu items.
- [x] Delete the monitor class and its callback chain; retain `HotkeyHealth`
  as a value.
- [x] Build the value in `AppDelegate.updateStatus()` from current permission
  and registration state. Use the same value for the menu and icon.
- [x] Skip unchanged values in `StatusMenu` before rebuilding warnings.
- [x] Move health coverage to menu tests, including permission recovery that
  preserves unrelated shortcut warnings.

## 4. Verify and document

- [x] Update AGENTS.md, CONTEXT.md, README.md, and the design.
- [x] Run all tests: 251 passed, zero failed or skipped.
- [x] Build Release successfully.
- [x] Obtain an independent review of B1/B2; no remaining concrete defect or
  duplicate state ownership was found.
- [x] Run the final production Carbon API probe: registration, dispatch, stale
  IDs, reconciliation, and release all passed.
- [x] Check screenshot setup in System Settings: the user confirmed capture
  works after disabling the matching macOS shortcuts on October 8.
- [ ] Check physical shortcuts during Secure Input and a real sleep/wake cycle.
- [x] Remove temporary probes and build data after all commands finish.

Commands use a unique task directory:

```sh
xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' \
  -derivedDataPath "$task_tmp/DerivedData" test
xcodebuild -project KuKa.xcodeproj -scheme KuKa -configuration Release \
  -derivedDataPath "$task_tmp/DerivedData" build
git diff --check
```

## Verification limits

The earlier native probe observed Secure Input active and accepted registrations
for all seven combinations. Both screenshot combinations also had enabled macOS
bindings. Successful registration does not prove physical shortcut delivery.

The tests send Carbon events to the actual handler through fake OS calls. They
cover state changes and dispatch, but do not prove physical keyboard delivery,
synthetic clipboard paste, or a real wake cycle.

Xcode reports existing CoreDevice/CoreSimulator version warnings and the project's
Info.plist resource warning. The macOS tests and build still succeed.

The original automated verification changed no system settings and did not
replace or restart the installed Ku-Ka app.

## October 8 review follow-up

- [x] Show screenshot setup once when a conflict is first detected, after any
  permission window closes. Keep menu instructions available after dismissal.
- [x] Correct the permission explanations, status-dot documentation, and the
  stale window-capture guidance.
- [x] Add retained tests for system-lookup failure, handler-installation failure,
  recovery, and another app's event signature.
- [x] Test setup persistence, permission-window ordering, skipped Accessibility,
  matching shortcut instructions, and the Keyboard Settings action.
- [x] Run the final full test suite: 258 passed, zero failed or skipped.
- [x] Build Release successfully after the follow-up changes.
- [x] Render and inspect the screenshot setup page for clipped text and controls.
- [x] Obtain independent Standards and Spec reviews of the follow-up; neither
  found a concrete defect.

The user reported that Secure Input and real sleep/wake checks have not been
done yet, then authorized committing, pushing, and opening the PR with those
checks pending. Record that limit in the PR; keep both manual checks open.
