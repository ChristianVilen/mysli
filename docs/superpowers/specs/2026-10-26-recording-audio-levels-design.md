# Recording audio levels

## Purpose

Show whether the microphone and Mac audio tracks contain sound while a meeting records. The user can check the sources before losing a meeting to missing audio. This implements the meter portion of issue #36.

The user delegated the product choices and accepted TDD. Keep the meters inside the existing Meeting Notes menu, directly below elapsed time. Label them **Microphone** and **Mac audio**. Silence is normal and has no warning. Each indicator has an accessible label and value. No new window, notifications, automatic stop, or stored preference is part of this change.

## Existing flow

`ScreenCaptureRecording` receives both tracks on its serial sample queue. Each `AudioTrackWriter` converts and writes mono Int16 PCM. `MeetingNotesController` owns the recording and menu. `StatusMenu` updates its sections once per second while open. The audio files, transcription, and summary pipeline retain their current behavior.

## Approaches

| Approach | Benefit | Cost |
|---|---|---|
| Read a small snapshot from the active recording | The UI reads only when visible. The recording owns its freshness and lifecycle. | Requires a short lock around scalar state and a visible-menu timer. |
| Send throttled callbacks to the controller | New values can redraw immediately. | Delivers tasks while the menu is closed and needs stale-session guards and a separate expiry check. |

Choose the snapshot approach. Two independent candidate designs and a cross-judge favored its ownership and visible-only updates. The parent made this choice under the user's delegation. The callback candidate's early-interruption test is retained. Recording identity comes from the active handle, so no new callback identity mechanism is needed.

## Data and ownership

`RecordingAudioLevels` is a value with `microphone` and `system` fractions and a `silent` value. `RecordingAudioMeter` stores the latest RMS measurement and monotonic receipt time for each `MeetingTrack`. A missing reading or a reading at least 0.5 seconds old returns zero. Convert RMS to a fraction with a -60 dB floor and 0 dB ceiling. Clamp the result to 0...1.

`AudioTrackWriter.append` returns optional RMS from the converted samples that it successfully writes. An output with no frames returns nil. Calculate in Double and normalize Int16 by 32768 before squaring. Do not include timeline-padding silence in the measurement. Do not copy audio buffers to the UI.

`ScreenCaptureRecording` owns a small `OSAllocatedUnfairLock<RecordingAudioMeter>`. The sample queue writes scalar readings after the audio write succeeds. Main-actor `ActiveRecording.audioLevels()` copies the meter under the lock and applies freshness outside it. Audio conversion, RMS calculation, and file writes never hold this lock. Do not use a synchronous audio-queue hop for UI reads. Closing the recording clears its meter.

`RecordingAudioMeterView` renders two native level indicators. It owns no recording state or timer. `MeetingNotesController` owns the menu item and a 0.1-second common-mode timer. The timer runs only when the menu is open and the recorder is recording. Opening the menu refreshes immediately. Stop, interruption, shutdown, and menu close invalidate it. A new recording has a new meter. `MenuSection.menuDidClose()` is a protocol requirement with a no-op default, and `StatusMenu` forwards the close event to every section. Other sections keep their current one-second tick.

## Files

- `KuKa/RecordingAudioLevels.swift` owns level and freshness rules.
- `KuKa/RecordingAudioMeterView.swift` owns the native meter view.
- `KuKa/MeetingAudioCapture.swift` measures converted audio and exposes snapshots.
- `KuKa/MeetingNotesController.swift` owns meter visibility and refresh.
- `KuKa/StatusMenu.swift` forwards menu close.
- Tests cover level values, written audio, recording lifecycle, and actual menu values.
- `AGENTS.md` and `README.md` describe the resulting behavior.

## Acceptance

- Synthetic constant positive and negative audio gives the expected RMS. Silence gives zero. Full-scale samples stay finite and bounded.
- Updating one track does not change the other. Each track expires independently, including at the 0.5-second boundary.
- Saved CAF samples, format, and timeline padding remain correct with metering enabled.
- The real menu view shows distinct values for the two tracks, clears stale values, and hides after stop or interruption.
- Opening and closing the real `StatusMenu` starts and stops view updates. Reopening reads the current values immediately.
- An interruption before capture startup returns cannot leave the meters visible.
- Inspect native light and dark renderings with deterministic signals. Verify the actual menu interaction without recording the user's surroundings.

## Tradeoffs and follow-up

Latest-buffer sampling can miss a sound shorter than the refresh interval. This first slice does not add peak hold or speech detection. The rates and expiry are chosen behavior constants, not performance measurements. Physical AirPods changes and display unplugging remain the separate real-device verification in issue #33.

## Implementation reconciliation

The implementation follows the selected snapshot design. The controller's existing title-only assertions now exclude custom-view items, and separate tests inspect the actual meter labels and values. Native `cacheDisplay` preview PNGs contain background artifacts, so live native-window inspection is required for visual verification.
