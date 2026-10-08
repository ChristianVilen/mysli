# Registered hotkeys

## Problem

Ku-Ka receives every global shortcut through one `CGEventTap`. Secure Input can
prevent keyboard events from reaching that tap, stopping both capture and tiling.
Re-enabling the tap cannot remove that restriction.

The health warning also assigns blame without enough evidence. It resolves
`kCGSSessionSecureInputPID` once after ten seconds and keeps the app name until
Secure Input clears. The value does not establish which app caused the problem.

## Decisions

Use `RegisterEventHotKey` for all seven shortcuts. Keep the existing combinations:

| Action | Shortcut |
| --- | --- |
| Capture full screen | Shift+Command+3 |
| Select capture area | Shift+Command+4 |
| Open clipboard history | Shift+Command+C |
| Tile left / right | Control+Option+Left / Right |
| Maximize / restore | Control+Option+Return |
| Center | Control+Option+C |

The user chose to keep the screenshot shortcuts and receive setup instructions
when macOS uses the same combinations. The user also chose TDD at HotkeyManager's
start/stop, feature toggle, action callback, and failure reporting boundary.

An alternative would keep the event tap for screenshots and register only the
other shortcuts. That would leave screenshots exposed to the reported failure.

## Registration and ownership

`HotkeyManager` owns desired shortcuts, feature toggles, retry timing, and wake
observers. Its `onAction` property forwards the registrar's callback to capture,
tiling, and clipboard features. It stores reported issues, but no registration
map or generation tokens.

`CarbonHotkeyRegistrar.reconcile(desired:)` is the one operation that applies the
desired set and returns ordered issues. The registrar owns one map containing
each registration's ID, reference, and active/pending-release state. It checks
enabled system shortcuts, releases removed keys, preserves working registrations,
and registers missing keys. Carbon accepts some system conflicts, so an enabled
matching system binding prevents registration even if the call would succeed.

Every registration gets a fresh ID. The event handler checks the Ku-Ka signature,
ID, and active state before delivering an action. A failed release keeps its
reference in pending-release state, rejects events, and reports `releaseFailed`
even when the shortcut is no longer desired. Reconciliation retries releases
before attempting to register the same key again.

`CarbonHotkeyAPI` supplies the five OS calls: copy system bindings, register,
unregister, install the handler, and remove it. Its production defaults call
Carbon directly. Tests replace only these calls and exercise the actual
reconciliation and handler code.

The manager reconciles every five seconds and on menu open, and renews
registrations after wake/session activation. `stop()` stops scheduling, requests
release, and reports any pending failures; repeated stop or later start can retry.
Both owners clean up in isolated deinitializers. macOS reclaims any registration
still held when the process exits.

## Status and setup

Replace the tap/Secure Input health model with registration failures and the
Accessibility permission state. `HotkeyHealth` is a value built directly by
`AppDelegate.updateStatus()` from both owners. The menu caches only its last
rendered value to avoid rebuilding identical warnings. Remove Secure Input polling, cached app names,
the ten-second dwell rule, and advice claiming lock/unlock fixes the problem.

The menu lists each unavailable shortcut. System conflicts direct the user to
System Settings > Keyboard > Keyboard Shortcuts. Screenshot conflicts point to
Screenshots and the two matching shortcuts. Include an action to open Keyboard
settings. Ku-Ka never changes system shortcut preferences itself.

When a screenshot conflict is first detected, show a screenshot setup page once.
Use the existing onboarding window and persist `didShowScreenshotShortcutSetup`
in Settings. If permission setup is open, wait until it closes; Accessibility
can be skipped without hiding screenshot instructions. Show only the conflicting
screenshot keys, their default macOS setting names, an Open Keyboard Settings
button, and a Later button. Explain automatic retry and how to restore the macOS
shortcuts after quitting Ku-Ka. Keep the menu guidance available after dismissal.

Other registration errors include the shortcut and numeric macOS error in logs;
the menu uses a short failure message. Other shortcuts continue to work.
Registration success means the OS accepted the shortcut; it is not proof that
the target window can move or that a capture or paste will succeed.

Register shortcuts independently of Accessibility permission. That permission
is still needed for window movement and synthetic paste. Screen Recording is
still needed for capture. Preserve the test-mode guard so XCTest never registers
real shortcuts or polls the real clipboard.

## Scope and constraints

- Swift 5 language mode, macOS 26.0+, AppKit and Carbon; no new package dependency.
- Xcode 26+ / Swift 6.2+ compiler for main-actor isolated deinitializers.
- Keep existing shortcut combinations and feature toggle defaults.
- Do not change macOS preferences, bypass Secure Input, or use private APIs.
- Do not add source-file entries to the synchronized Xcode project.
- Keep capture, selection, tiling layout, and clipboard paste behavior unchanged.
- Update AGENTS.md, CONTEXT.md, README.md, and affected permission descriptions.
- Do not claim that this makes every window movable or synthetic paste reliable
  during Secure Input. These operations use separate APIs.

## Verification

Use fake Carbon calls with the real registrar to verify the HotkeyManager boundary: desired
registrations, one action per callback, idempotent start, stop cleanup, stale
callback rejection, feature toggles, partial registration failure, conflict
recovery, renewal after wake, failed releases, and stop recovery. Menu tests cover
combined warnings, partial recovery, release failures, and duplicate-render suppression.

Run focused tests after each red/green cycle, then the full XCTest suite and a
Release build. Test real registration and release with a temporary macOS probe.
Manually check physical shortcuts with Secure Input active, screenshot conflicts
enabled and disabled, feature toggles, and sleep/wake. Automated tests with a
fake OS calls cannot prove physical delivery through Secure Input.

## Verification results

The installed SDK's `CarbonEvents.h` documents exclusive registration and
`CopySymbolicHotKeys`. AltTab's API comparison reports registered hotkeys working
through Secure Input:
https://github.com/lwouis/alt-tab-macos/blob/master/src/experimentations/README.md

Before the judo refactor, all 248 XCTest tests passed and the Release build
succeeded on macOS 26.7 with Xcode 27.0. The live registration probe observed
Secure Input active, successful registrations for all seven combinations, and
enabled macOS bindings for both screenshot shortcuts.

A separate probe compiled the actual adapter sources. It verified handler
dispatch, wrong-signature rejection, stale registration IDs, stop, and releasing
exclusive registrations so they could be claimed again. That probe sent Carbon
events to its own handler; it did not simulate physical keys.

The user confirmed on October 8 that screenshot capture works after disabling
the matching macOS screenshot shortcuts. Physical shortcut delivery during
Secure Input and a real sleep/wake cycle still need a manual check. The temporary
probes and build data are removed after verification.

After the approved judo changes, all 251 XCTest tests passed and the Release
build succeeded. A regression confirmed that the earlier implementation hid a
failed release when a feature was disabled; it now passes through the real
registrar with fake Carbon calls. Another regression confirmed repeated health
updates rebuilt the menu; unchanged values now preserve the menu items. The
independent follow-up review found no remaining concrete issue in B1 or B2.
The final probe also passed with the production Carbon calls: registration,
handler dispatch, stale-ID rejection, reconciliation, and release.

After the October 8 review follow-up, all 258 XCTest tests passed with no skips,
and the Release build succeeded. The new screenshot setup page was rendered and
checked for clipped text and controls. Independent Standards and Spec reviews
found no concrete defect. The user has not yet checked physical shortcuts during
Secure Input or after a real sleep/wake cycle.
