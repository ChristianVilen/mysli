#!/bin/bash
set -eu

cd "$(dirname "$0")/.."
task_output=${1:?Pass a temporary directory for build output and native images.}
shift
mkdir -p "$task_output/notes-ui" "$task_output/panel-after"

TEST_RUNNER_KUKA_TYPED_NOTES_SNAPSHOTS="$task_output/notes-ui" \
TEST_RUNNER_KUKA_PANEL_SNAPSHOTS="$task_output/panel-after" \
xcodebuild -project KuKa.xcodeproj -scheme KuKa -destination 'platform=macOS' \
    -derivedDataPath "$task_output/build" "$@" test \
    -only-testing:KuKaTests/MeetingTypedNotesWindowTests \
    -only-testing:KuKaTests/MeetingTypedNotesFileTests \
    -only-testing:KuKaTests/MeetingTypedNotesLifecycleTests \
    -only-testing:KuKaTests/MeetingTypedNotesProcessorTests \
    -only-testing:KuKaTests/MeetingControlsPanelTests
