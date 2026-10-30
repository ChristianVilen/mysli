# Calendar recording reminders integration

The integration is off by default. Eligible events offer **Start Recording**, then **Stop Recording** or **Continue Recording** at the end. Only accepted actions change recording. Calendar edits and permission loss never stop audio.

## Settings contract for #43

`AppDelegate.calendarReminders` exposes the app-owned `CalendarReminderController?` on the main actor. It becomes available when production launch begins its resume task. It stays nil in XCTest and `--uitesting`. Settings must use this controller, with no second EventKit store or notification delegate.

The switch reads `Settings.calendarRecordingRemindersEnabled`, whose default is false. Its action awaits `calendarReminders?.setEnabled(newValue)`. Writing the defaults key alone does not enable reminders or request access.

Read `controller.status` and assign `controller.onStatusChange: (() -> Void)?` to refresh the view. The cases are `off`, `requestingAccess`, `ready`, `calendarAccessRequired`, `notificationsRequired`, and `readFailed`. The callback runs on the main actor. Read the initial status and clear the callback when the view no longer needs updates.

Only `setEnabled(true) async` requests Calendar and notification access. `resume() async` restores the saved preference without prompting. `refresh() async` rechecks grants and events. Settings can call it when its window opens or returns from System Settings. The driver also checks every 60 seconds. Denied Calendar access requires a grant in System Settings. Enable does not repeat a denied Calendar prompt.

Suggested explanation text is "Calendar events offer recording reminders. Ku-Ka never starts or stops recording automatically." The Settings window's **Calendar reminders** switch ([#43](https://github.com/ChristianVilen/ku-ka/issues/43)) uses this explanation and follows this contract. `AppDelegate` awaits `setEnabled(_:)` for the switch, shows each status change in the window, and calls `refresh()` when Settings opens.

## Ownership and shared files

`EventKitCalendarSource` is the only production EventKit reader. It requests full access and calls no save or remove API. It converts identity, title, dates, recurrence, availability, cancellation, and the current user's decline status. It reads no notes, locations, or attendee names.

`CalendarReminderController` owns policy, receipts, event revisions, tokens, and recording associations. `CalendarReminderNotifications` builds native requests and categories through injectable `Calls`. `SystemNotifier` remains the only delegate. Its `onCalendarReminder` callback awaits the controller before the delegate completes the response. Existing file and Check Words routes remain available.

The controller holds one optional offer whose kind carries the event and, for an end offer, the recording session. Its recording link is either validating Start or associated. The association's end reminder is waiting, offered at a deadline, or continued. The notification adapter owns pending-add cancellation and failed-add cleanup. Removing a token prevents an in-flight add from leaving a visible request. An old add failure can clear only its own controller offer.

`CalendarReminderDriver` owns EventKit-change, wake, clock-change, and time-zone-change observers. It owns a 60-second safety timer and one replaceable next-boundary timer. `schedule(at: nil)` cancels only the boundary. `stop()` removes all resources. Tests replace the observers and timers through `Calls`.

`AppDelegate` constructs the integration outside its test-host guard only. Its existing `meetingNotes.onStateChange` updates the status icon and forwards `recorderDidChange()`. It does not replace recorder callbacks. Quit cancels startup and shuts down calendar watchers before meeting processing. The notification adapter removes stale pending and delivered requests with the `calendar-recording.` prefix at launch, while preserving other requests and categories.

The Settings work in #43 reconciled `AppDelegate.swift` and `Settings.swift` with this integration. `MeetingNotesController.swift` adds a title to its existing disabled recording line. The visible suffix is limited to 48 characters. The tooltip and accessibility label retain the full title. Manual recording keeps its existing status. `Info.plist` adds `NSCalendarsFullAccessUsageDescription`. Source folders remain synchronized with Xcode, with no project-file entries.

## Eligibility and limits

The controller queries from two minutes before now through 24 hours ahead and reads its associated occurrence separately. All-day, cancelled, declined, explicitly free, and nonpositive-duration events are excluded. Tentative events and events without attendees are eligible. Overlapping starts yield one offer. A starting, recording, or paused session consumes due starts without replaying them later.

Recurring identities include the original recurrence date, including detached occurrences whose start moved. Nonrecurring identities never use the mutable start date. Exact recurrence reads use fresh predicates around the original date and last observed start. They never accept the first series occurrence merely because its identifier matches.

Within one source lifetime, an external identifier can preserve identity across a calendar move or local identifier change. The alias includes the provider account and original recurrence date. The previous calendar and item must no longer resolve before a new locator can take its identity. Duplicate external identities permanently disable that alias for this source instance. Narrow exact reads cannot establish aliases. A different account never inherits an alias. No match uses a title.

`CalendarEventFields` requires an explicit provider source. Native mapping supplies `calendar.source.sourceIdentifier`. Only test fixtures use `"synthetic"`.

Provider identity changes after restart, a cache reset beyond 4,096 observed identities, and detached events moved outside both exact-read windows can lose the association. A series that still resolves under its old identifier can prevent a detached alias from moving. These cases fail closed. They can miss a reminder or treat a changed identifier as a new occurrence. Ku-Ka cannot prove identity across a full provider resync. Provider sync delays can also delay edits. The app must be running. A long sleep can miss starts outside the two-minute grace period.

Accepted Start fixes the normalized title for that recording and its documents. End-time changes move the end offer. Continue suppresses later end offers for that session. Recording remains manual if its association becomes unsafe.

## Verification

Tests use synthetic calendar fields, fake timer signals, injected notification-center calls, isolated defaults, and temporary generated notes. No test constructs a real EventKit store or posts a real notification. See the [synthetic evidence record](superpowers/evidence/2026-10-29-calendar-reminders.md).

Native banner layout, action expansion, VoiceOver announcement and action order, actual grants, real recurrence edits, sleep and wake, provider sync, and System Settings navigation remain manual checks. They were not run because this task forbids real calendar access, recording, and notification delivery. Settings UI checks belong to #43.
