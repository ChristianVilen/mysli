# One Ku-Ka window

The app has one retained window titled Ku-Ka. Its sidebar contains Settings, Features & instructions, Permissions, and Help & feedback. This replaces the separate onboarding window. Existing Settings controls keep their persistence and runtime callbacks.

## Entry points

Ku-Ka in the dropdown opens Settings. Command-comma also selects Settings. Permissions in the dropdown, missing required access at launch, and a blocked capture or recording open Permissions in the same window. Microphone remains optional at launch. Granting access does not close the window or start a feature.

Permissions contains the live checklist and screenshot shortcut instructions. A screenshot system conflict opens and reveals those instructions automatically once. The saved setup flag changes only after the window is visible and the guidance has been revealed. The instructions remain available on later manual visits.

The dropdown keeps operational commands. Keep screen on sits with the Keep Awake durations. It uses the existing saved preference and updates an active power assertion without restarting the session. Feature explanations and the bug and feedback links move into the shared window. The links open the existing GitHub issue forms without submitting a message.

## Ownership

SettingsPage remains the sole page selection. SettingsWindowController owns the window and its visibility transitions. PermissionsManager stays in AppDelegate, which retains its sole change callback and forwards PermissionSnapshot values. PermissionActions contains the four request actions. The page has no production services.

Permission polling runs only while Permissions is selected and the window is visible, unminimized, and the app is not hidden. It stops on page exit, close, minimize, or app hide and resumes on return. Opening System Settings does not stop polling for a checklist that remains visible.

The preview uses the same pages with fixed permission values and inert permission, link, login, notification, and power adapters. XCTest continues to use the passive launch host.

## Approaches

Extending the existing SettingsWindowController keeps the retained window, form actions, file sheets, and activation behavior together. A second design introduced a new window shell and separate Settings and Permissions controllers. That design required a larger extraction and more connections without changing the user experience.

The implementation uses the existing controller and separate view files for Permissions and Help. It takes the explicit hide and minimize handling from the shell design. Independent design review agreed with this choice.

## Verification

The user selected TDD for page routing and the Keep Awake action. Tests cover the same window identity, page routes, permission visibility, injected actions, shortcut setup bookkeeping, saved preferences, and unchanged active-session expiry. Existing keyboard, compact-layout, appearance, and launch-host checks cover the expanded window. Live native UI verification is recorded separately.
