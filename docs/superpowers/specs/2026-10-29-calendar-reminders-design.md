# Calendar recording reminders

Issue [#28](https://github.com/ChristianVilen/ku-ka/issues/28) adds reminders for events available through Apple Calendar. The user chooses when recording starts and stops. Calendar changes never stop audio.

## Chosen behavior

The integration is off by default. The Settings window from [#43](https://github.com/ChristianVilen/ku-ka/issues/43) owns its switch and permission status. This branch supplies the preference, controller interface, and app wiring. It adds no settings menu item or second Settings window.

Eligible events are timed events with a positive duration from all readable calendars. All-day, cancelled, declined-by-current-user, and explicitly free events are excluded. Tentative events and events without attendees are included. A blank title becomes "Calendar meeting". The adapter reads no event notes, locations, or attendee names. It reads only the current user's participation status.

Ku-Ka offers Start Recording at the event start. A two-minute grace period allows a short delay after wake. Events that ended or started more than two minutes ago do not get a new start reminder. Once shown, Start remains valid until the event ends, provided the event has not changed. This separates delivery timing from the time the user has to act.

Only one start reminder is offered when events overlap at the same refresh. The earliest start wins, with occurrence identity as a stable tie-breaker. Other due events are consumed without a reminder. While that start offer remains valid, later overlapping starts are also consumed without another banner. A starting, recording, or paused meeting consumes due starts without offering them. Stopping later does not replay them.

At the associated event's end, an active or paused recording gets Stop Recording and Continue Recording. Continue leaves a paused meeting paused and prevents further end reminders for that recording. Default clicks and dismissals never start or stop audio. A default end click can show the existing meeting controls.

An event edit invalidates old actions and removes obsolete notifications. An already offered start is not offered again after an edit. For an active association, an end-time edit moves the reminder. A title-only edit invalidates the old end action without posting another end banner for the same deadline. Deletion, cancellation, decline, or loss of a safe identity suppresses the end reminder without changing recording. The title captured at Start stays fixed. After Continue, later edits do not ask again.

## Approaches

| Approach | Benefit | Cost |
| --- | --- | --- |
| App-owned reconciliation with immediate native notifications | Reads current event and recording state before delivery. No future OS request can outlive the recording. | Requires Ku-Ka to run. Sleep delays reminders. Long sleeps miss start reminders. |
| Future native notification requests | macOS can deliver while Ku-Ka is absent. | Unseen calendar edits and stopped recordings can leave obsolete banners. Adds OS request bookkeeping. |

Use app-owned reconciliation. Both independent design candidates preferred it for this task's obsolete-reminder requirement. The cross-judge, gpt-6-sol, also selected it. Its required change was a fresh event read for Stop and Continue, not only Start. The user delegated routine design choices.

## Identity and ownership

`CalendarOccurrence.ID` identifies an occurrence independently of its current start or title. Use an EventKit item identifier plus its calendar and original occurrence date for recurring instances. Never use a mutable start date for a non-recurring event. The adapter may retain an unambiguous external-identifier alias to handle local identifier changes. Never guess identity from a title. Ambiguous provider identity changes fail closed and are a documented platform limit.

`CalendarOccurrence` is a value snapshot. Its revision consists of the fields that affect the reminder, including title, start, end, and eligibility. The adapter owns EventKit objects. The controller owns one optional typed offer. Its Start kind carries an occurrence revision. Its End kind also carries the recording session. Notification data contains the token only. Unrecognized tokens do nothing, including after relaunch.

One recording link distinguishes Start validation from an established association. The association has one end-reminder state, either waiting, offered at a deadline, or continued. The notification adapter owns cancellation of pending adds and cleanup after failed adds. Removing a token prevents an in-flight add from leaving a visible request. Calendar field construction requires the provider source. Only tests supply a synthetic source.

`MeetingRecorder` owns a unique session ID through Starting, Recording, and Paused. A calendar action calls explicit Start, never toggle. Stop checks the session ID and stops in the same main-actor operation. A title snapshot is passed at Start. The calendar controller owns the event-to-session link and must discard it when that session ends. It must not associate a returned start result with a newer session.

`MeetingFolder` remains a value identified only by its canonical URL. A versioned, bounded `meeting.json` file stores the optional display title. It does not affect the stage rule or folder discovery. Missing, invalid, or oversized metadata falls back to the existing date title. New folder names remain `yyyy-MM-dd_HH-mm` with the existing collision suffix. Metadata is written under the recording lock before capture starts. Calendar title text is normalized to one bounded line and safely encoded in Markdown headings. Transcript utterances, summary input, known words, and meeting context remain unchanged.

## Boundaries

- `CalendarEventSource` supplies authorization and immutable occurrence snapshots. `EventKitCalendarSource` is the only production adapter that reads EventKit.
- `CalendarReminderController` owns enablement, typed pending reminders, occurrence receipts, session association, refresh, and action validation. Inject its source, wall clock, wake/timer driver, reminder notification sink, recorder, and preference storage.
- `CalendarReminderNotifications` registers native Start and Stop/Continue actions and removes only this feature's pending and delivered notifications. `SystemNotifier` remains the single notification delegate and routes these actions.
- `MeetingRecorder.startRecording(title:)` reserves an idle recorder before awaiting grants or capture. It returns that session only if it became active. `stopRecording(ifSession:)` rejects another session. `activeSessionID` and `displayTitle` are read-only.
- `Settings.calendarRecordingRemindersEnabled` stores the default-off preference. A separate bounded receipt store remembers consumed occurrences across refreshes and restarts without storing event titles.

One main-actor controller handles mutations. Calendar snapshots may be synchronous, since EventKit's bounded predicate API is synchronous. Async permission and notification operations carry generation checks. A stale notification add is removed after completion. Disable, shutdown, revocation, event edits, and recorder changes invalidate affected tokens before any await.

Action handling re-reads the exact occurrence before Start, Stop, or Continue. After a read that suspends, recheck enablement, authorization, token, event revision, due time, and session identity. An end that moved into the future invalidates the old Stop action even when the store-change signal has not reached Ku-Ka yet. Refresh triggers share one reconciliation worker rather than competing notification mutations.

Refresh on launch without prompting, explicit enable, EventKit changes, wake, wall-clock changes, recorder state changes, and a periodic safety timer. Arm the next due event boundary so start reminders are not limited to periodic polling. A timer requests a fresh read, never an unconditional notification. Query the next 24 hours and the current association separately when needed. An empty successful snapshot and a failed read must be distinguishable. A failed read removes interactive reminders and leaves manual recording alone.

Consume a start before posting or invoking Start. Keep receipts for seven days after the last known event end, with a bounded count. A crash between receipt storage and delivery may miss one reminder, which is preferable to duplicate prompts. Receipt identity and active-session association are separate.

## Permission and Settings contract

The implemented API, ownership boundaries, provider identity limits, and pending manual checks are recorded in [the integration reference](../../calendar-recording-reminders.md). The retained fixture values are in [the synthetic evidence record](../evidence/2026-10-29-calendar-reminders.md).

`CalendarReminderController.setEnabled(_:) async` persists the preference. Only an explicit enable requests Calendar and notification permission. `resume()` reads saved preference and authorization without prompting. `status` and `onStatusChange` let #43 render Off, Requesting Access, Ready, Calendar Access Required, Notifications Required, and read failures. `refresh()` rechecks revoked grants. Disable removes reminders and leaves recording alone.

The minimal #43 integration is one switch under Meeting Notes that calls `setEnabled`, reads the saved preference, and observes status. Its explanation says that calendar events offer recording reminders and that Ku-Ka never starts or stops automatically. Denial can link to the Calendar or Notifications pane in System Settings. This branch documents the exact implemented signatures after review. Do not merge the sibling branch here.

AppDelegate owns the optional real controller outside XCTest and `--uitesting`. It forwards `MeetingNotesController.onStateChange` to the controller without taking over the recorder's existing callbacks. It connects the existing notification delegate and shuts down watchers before meeting shutdown.

## Verification and evidence

TDD is required at injected calendar, clock, notification, and recorder boundaries. Test late actions, double Start, paused Stop/Continue, overlapping events, edits, cancellation, revocation, late permission completions, late notification adds, wake, recurring occurrence identity, and restart receipts. Test recorder shutdown during permission and capture awaits. No test accesses real calendar events or starts real capture.

Title tests use temporary meeting folders and fake processing. Prove that title metadata survives recovery, does not change folder equality or stage, appears in transcript and summary headings, and never enters spoken summary content. Existing recording-clock and pause tests stay unchanged.

Frontend evidence uses synthetic notification requests and temporary note documents before and after the change. Native notification screenshots require actual notification delivery, which automated tests must not do. Record that visual and VoiceOver check as pending. No custom reminder window is added. The #43 Settings UI and its screenshots belong to its owner.

Baseline at `5ee18b6` passed 45 selected MeetingFolder, MeetingRecorder, and Notifier tests. Xcode printed existing CoreDevice/CoreSimulator version warnings, but macOS tests succeeded. `docs/superpowers/best-practices.md` is absent.

## Platform evidence

Apple's [EventKit access documentation](https://developer.apple.com/documentation/eventkit/accessing-the-event-store) requires full access to read events. The [request method](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents(completion:)) requests that access asynchronously. Ku-Ka never calls event save or remove APIs.

The installed macOS SDK documents `EKEvent.occurrenceDate` as the original recurrence date, retained when a detached occurrence moves. It also warns that local identifiers can change after sync. Native notification actions use [UNNotificationAction](https://developer.apple.com/documentation/usernotifications/unnotificationaction) and the existing notification delegate.
