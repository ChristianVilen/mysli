#!/bin/bash
set -eu

cd "$(dirname "$0")/.."
task_output=${1:?Pass a temporary directory for build output and native images.}
shift
mkdir -p "$task_output/notes-ui" "$task_output/panel-after"

TEST_RUNNER_MYSLI_TYPED_NOTES_SNAPSHOTS="$task_output/notes-ui" \
TEST_RUNNER_MYSLI_PANEL_SNAPSHOTS="$task_output/panel-after" \
xcodebuild -project Mysli.xcodeproj -scheme Mysli -destination 'platform=macOS' \
    -derivedDataPath "$task_output/build" "$@" test \
    -only-testing:MysliTests/MeetingTypedNotesWindowTests \
    -only-testing:MysliTests/MeetingTypedNotesFileTests \
    -only-testing:MysliTests/MeetingTypedNotesLifecycleTests \
    -only-testing:MysliTests/MeetingTypedNotesProcessorTests \
    -only-testing:MysliTests/MeetingControlsPanelTests
