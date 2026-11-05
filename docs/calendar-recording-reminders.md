# Calendar recording reminders integration

The integration is off by default. Eligible events offer **Start Recording**, then **Stop Recording** or **Continue Recording** at the end. Only accepted actions change recording. Calendar edits and permission loss never stop audio.

## Settings and onboarding

`AppDelegate.calendarReminders` exposes the app-owned `CalendarReminderController?` on the main actor. Production launch assigns it before starting its resume task. XCTest and `--uitesting` do not construct this controller. Settings and onboarding use the same controller, EventKit source, and notification delegate.

The switch reads `Settings.calendarRecordingRemindersEnabled`, whose default is false. Its action sends the choice to `ToolController`. That owner applies the tool flags first, then awaits `calendarReminders?.setEnabled(newValue)`. Writing the defaults key alone does not enable reminders or request access.

Meetings must be on. Turning Meetings off calls `setEnabled(false)` and disables the reminder switch. Turning Meetings back on leaves reminders off. The controller also refuses an enable request while `Settings.meetingsEnabled` is false.

Onboarding offers reminders as an unchecked choice under Meetings. Continue sends a `ToolSelection` to the same `ToolController`. It applies the reminder choice through `setEnabled(_:)` when it differs from the saved preference. A choice replaced before its task starts is not applied. `Onboarding` saves the Allow access step before the callback can show permission prompts. Skip setup keeps the saved reminder setting and does not apply an unsubmitted choice.

`AppDelegate` owns `controller.onStatusChange`. The callback runs on the main actor and updates the Meetings status line and permission snapshots. Views do not replace it. The status cases are `off`, `requestingAccess`, `ready`, `calendarAccessRequired`, `notificationsRequired`, and `readFailed`.

`setEnabled(true) async` requests Calendar access, then notification access if Calendar is allowed. A denied Calendar grant needs a change in System Settings. The system prompt does not repeat after a refusal. Event checks stay suspended across both permission requests, so polling cannot interrupt the request sequence.

`RequiredPermissions` includes Calendar and Notifications only while Meetings and reminders are on. Setup, the Permissions page, and the launch check use that list. After setup, a missing required grant opens the Permissions page at launch. Its Calendar row calls `PermissionsManager.requestCalendar()` through the same `EventKitCalendarSource`. Its Notifications row calls `PermissionsManager.requestNotifications()`. Neither row turns reminders on.

`resume() async` reads the Meetings and reminder preferences without writing or prompting. Meetings off keeps the controller off, even if an external defaults write left the reminder flag on. `refresh() async` rechecks grants and events after permission requests finish. Settings can call it when its window opens or returns from System Settings. The driver also checks every 60 seconds.

## Ownership and shared files

`EventKitCalendarSource` is the only production EventKit reader. It requests full access and calls no save or remove API. It converts identity, title, dates, recurrence, availability, cancellation, and the current user's decline status. It reads no notes, locations, or attendee names.

`CalendarReminderController` owns policy, receipts, event revisions, tokens, and recording associations. `CalendarReminderNotifications` builds native requests and categories through injectable `Calls`. `SystemNotifier` remains the only delegate. Its `onCalendarReminder` callback awaits the controller before the delegate completes the response. Existing file and Check Words routes remain available.

The controller holds one optional offer whose kind carries the event and, for an end offer, the recording session. Its recording link is either validating Start or associated. The association's end reminder is waiting, offered at a deadline, or continued. The notification adapter owns pending-add cancellation and failed-add cleanup. Removing a token prevents an in-flight add from leaving a visible request. An old add failure can clear only its own controller offer.

`CalendarReminderDriver` owns EventKit-change, wake, clock-change, and time-zone-change observers. It owns a 60-second safety timer and one replaceable next-boundary timer. `schedule(at: nil)` cancels only the boundary. `stop()` removes all resources. Tests replace the observers and timers through `Calls`.

Production `AppDelegate` constructs the integration. `AppLaunchMode` selects separate passive and preview hosts for tests. The existing `meetingNotes.onStateChange` updates the status icon and forwards `recorderDidChange()`. It does not replace recorder callbacks. Quit cancels startup and shuts down calendar watchers before meeting processing. The notification adapter removes stale pending and delivered requests with the `calendar-recording.` prefix at launch, while preserving other requests and categories.

The Settings work in #43 reconciled `AppDelegate.swift` and `Settings.swift` with this integration. `MeetingNotesController.swift` adds a title to its existing disabled recording line. The visible suffix is limited to 48 characters. The tooltip and accessibility label retain the full title. Manual recording keeps its existing status. `Info.plist` adds `NSCalendarsFullAccessUsageDescription`. Source folders remain synchronized with Xcode, with no project-file entries.

## Eligibility and limits

The controller queries from two minutes before now through 24 hours ahead and reads its associated occurrence separately. All-day, cancelled, declined, explicitly free, and nonpositive-duration events are excluded. Tentative events and events without attendees are eligible. Overlapping starts yield one offer. A starting, recording, or paused session consumes due starts without replaying them later.

Recurring identities include the original recurrence date, including detached occurrences whose start moved. Nonrecurring identities never use the mutable start date. Exact recurrence reads use fresh predicates around the original date and last observed start. They never accept the first series occurrence merely because its identifier matches.

Within one source lifetime, an external identifier can preserve identity across a calendar move or local identifier change. The alias includes the provider account and original recurrence date. The previous calendar and item must no longer resolve before a new locator can take its identity. Duplicate external identities permanently disable that alias for this source instance. Narrow exact reads cannot establish aliases. A different account never inherits an alias. No match uses a title.

`CalendarEventFields` requires an explicit provider source. Native mapping supplies `calendar.source.sourceIdentifier`. Only test fixtures use `"synthetic"`.

Provider identity changes after restart, a cache reset beyond 4,096 observed identities, and detached events moved outside both exact-read windows can lose the association. A series that still resolves under its old identifier can prevent a detached alias from moving. These cases fail closed. They can miss a reminder or treat a changed identifier as a new occurrence. Mysli cannot prove identity across a full provider resync. Provider sync delays can also delay edits. The app must be running. A long sleep can miss starts outside the two-minute grace period.

Accepted Start fixes the normalized title for that recording and its documents. End-time changes move the end offer. Continue suppresses later end offers for that session. Recording remains manual if its association becomes unsafe.

## Verification

Tests use synthetic calendar fields, fake timer signals, injected notification-center calls, isolated defaults, and temporary generated notes. No test constructs a real EventKit store or posts a real notification. See the [synthetic evidence record](superpowers/evidence/2026-10-29-calendar-reminders.md).

Onboarding tests cover saved progress, tool choices, prompt order, and the shared window. A fake Calendar request stays pending during a refresh to check that Notifications is still requested after Calendar access is allowed. Native pictures check layout without using real permission prompts.

Native notification banners, action expansion, VoiceOver, actual grants, real recurrence edits, sleep and wake, provider sync, and System Settings navigation still need manual checks. A real restart after Screen Recording access and Stage Manager activation also remain unchecked.
