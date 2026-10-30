# Unified Ku-Ka window verification

## Test-driven checks

Three tests ran before product changes. All three failed for the expected missing behavior.

| Test | Initial failure |
| --- | --- |
| `KeepAwakeControllerTests.testMenuDisplayToggleKeepsTheCurrentSessionAndExpiry` | `XCTUnwrap failed: expected non-nil value of type "NSMenuItem"`. The Keep screen on item did not exist. |
| `SettingsWindowControllerTests.testFourPagesUseOneKuKaWindowWithoutChangingPreferences` | `Optional("Ku-Ka Settings")` did not equal `Optional("Ku-Ka")`. The sidebar also contained only Settings and Instructions. |
| `StatusMenuTests.testDropdownOpensKuKaAndKeepsHelpInsideTheWindow` | Ku-Ka entry count was `0`, expected `1`. Features and feedback links were still in the dropdown. |

The initial result bundle is `build/unified-window/Logs/Test/Test-KuKa-2026.10.30_15-46-14-+0200.xcresult`.

The first focused run after implementation passed 60 tests and failed two existing tests. They still expected two sidebar buttons and a Features menu section. Those assertions now describe the approved four-page window and shorter menu. The next focused run passed all 63 tests.

Permission tests exercise the retained window's routes, visible-page callbacks, minimize and app-hide events, injected Grant and Keyboard Settings actions, optional microphone state, shortcut setup after visible presentation, failed presentation, and help destinations. They do not request real permissions. Keep Awake tests check saved choice, no session start from the check item alone, and the same expiry after toggling during a session. Existing Settings tests now check all four keyboard cycles and control bounds at 640 by 420 points.

## Full suite

```sh
xcodebuild -quiet -project KuKa.xcodeproj -scheme KuKa \
  -destination 'platform=macOS' -derivedDataPath build/unified-window \
  test -only-testing:KuKaTests
```

The final run exited 0. `xcresulttool get test-results summary` reported 992 tests, 987 passed, five skipped, and zero failures. The result bundle is `build/unified-window/Logs/Test/Test-KuKa-2026.10.30_15-55-57-+0200.xcresult`. The five skipped tests require optional real audio fixtures or meeting-panel pictures.

Xcode printed the existing CoreDevice and CoreSimulator version mismatch, duplicate destination, Info.plist resource, and actor-conversion warnings. The result bundle contains the existing thread-priority warning in WordReviewWindowTests. No models were downloaded and no real permission requests were made.

## Native preview and limits

The built app is `build/unified-window/Build/Products/Debug/KuKa.app`. Launch it with `--uitesting` to open the shared window. This host uses isolated KuKa.TestHost defaults and inert login, permission, link, sleep-prevention, and notification adapters. It displays a fixed permission snapshot and supports the Keep Awake menu without a real power assertion. It does not construct AppDelegate.

The isolated native preview was launched with a separate bundle identifier. Its accessibility tree showed the four pages, the granted Accessibility state, missing Screen Recording state, optional Microphone state, and both feedback buttons. Inert Grant, Allow, and Keyboard Settings actions opened no system prompts. The application menu's Settings command returned to Settings in the same Ku-Ka window.

A temporary renderer linked the built KuKa.debug.dylib and rendered all four pages in light and dark appearance at 760 by 700 and 640 by 420 points. The review inspected Settings, Permissions, Help, and Features at those sizes. A separate assertion confirmed that automatic screenshot setup scrolls the Keyboard Settings button fully into view at 640 by 420 points. The renderer used isolated defaults, fake activation, inert actions, and no onscreen window. Its temporary files were removed after review.

The desktop automation tool captured a Stage Manager thumbnail rather than a full-size window. The native renders prove layout, not live glass or active focus colors. Physical Tab-key focus could not be confirmed in that session. Real permission grants, actual hide and minimize events, and VoiceOver announcements remain unverified. Tests cover the injected lifecycle and all four keyboard-view loops.

An independent code review found no actionable defects. A separate comment review removed one unnecessary sentence from the Accessibility prompt explanation. This final edit changes no behavior.
