# Meeting panel review fixes

The user approved fixes for B1, B2, B3, and S1 on 2026-11-03. Keep the approved interface and work in the current checkout.

## B1. One presentation owner

- [x] Remove transcript-open state and setters from `MeetingRecorder`. Expose its live preview on demand.
- [x] Give the panel one typed presentation derived from its content mode and recording state. Render stopped notes as notes rather than a fabricated recorder status.
- [x] Verify collapse, hide, reopen, new recordings, post-Stop editing, and existing panel geometry.

## B2. One document change per row split

- [x] Add session-owned split and inverse operations. Each changes both rows before one save and notification.
- [x] Move structural undo registration to the session's undo manager. Keep native text undo on that same manager.
- [x] Remove whole-document replacement from the view and the timestamp map needed to repair old snapshots. Track only rows waiting for their first content.
- [x] Verify saved snapshots, notifications, undo, redo, timestamps, and failed-save drafts.

## B3. One screenshot boundary

- [x] Add a validated screenshot value for bounded decoding and PNG conversion. Add a meeting-owned store for safe relative files.
- [x] Make paste and drop forward input to that boundary. Remove repeated validation and filesystem calls from the text view and session.
- [x] Verify PNG and TIFF, bounded local files, invalid input, safe names, symlink refusal, and attachment undo without deleting files.

## S1. Keep row views and thumbnails

- [x] Give each note row a retained view with its constraints installed once.
- [x] Update only changed rows. Keep decoded thumbnails by attachment name and decode them at display size through ImageIO.
- [x] Verify row/editor identity, selection, thumbnail dimensions, and cache behavior across insertion and undo.

## Execution and verification

Panel ownership and the screenshot boundary use separate files and workers. The root owns document edits and the shared editor that consumes the screenshot API. Serialize Xcode runs in one task build directory. Use TDD for new behavior, retain the native regression checks, inspect the changed native views, and run the full XCTest suite before completion.
