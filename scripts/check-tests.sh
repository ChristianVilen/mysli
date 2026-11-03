#!/bin/bash
# Run after a full test run. Fails when a test takes more than the limit and
# scripts/slow-tests-allowed.txt gives no reason for it, or when AGENTS.md
# is over 150 lines.
#
# Usage: scripts/check-tests.sh [result.xcresult]
# Without an argument, it reads the newest test result in the DerivedData
# folder of this checkout.
set -eu

cd "$(dirname "$0")/.."
# The goal is 0.1 s, but XCTest adds up to about 0.12 s to some async tests at
# random in this test host. A 0.1 s limit would fail one run and pass the next.
limit=0.15
allowed=scripts/slow-tests-allowed.txt
failed=0

result=${1:-}
if [ -z "$result" ]; then
    project="$PWD/KuKa.xcodeproj"
    for info in ~/Library/Developer/Xcode/DerivedData/KuKa-*/info.plist; do
        if [ "$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$info" 2>/dev/null)" = "$project" ]; then
            result=$(/bin/ls -dt "$(dirname "$info")"/Logs/Test/*.xcresult 2>/dev/null | head -1)
        fi
    done
fi
[ -n "$result" ] || { echo "No test result found. Run the tests, or pass a .xcresult path." >&2; exit 2; }

# Every test that ran, slowest first, as "Class/testName() seconds".
durations=$(xcrun xcresulttool get test-results tests --path "$result" | jq -r '
    [.. | objects | select(.nodeType == "Test Case" and .result != "Skipped")]
    | sort_by(-.durationInSeconds)[] | "\(.nodeIdentifier) \(.durationInSeconds * 1000 | round / 1000)"')
slow=$(awk -v limit="$limit" '$2 > limit' <<< "$durations")

while read -r test seconds; do
    [ -n "$test" ] || continue
    if ! grep -q "^$test[[:space:]]" "$allowed"; then
        echo "Slow test without a reason in $allowed: $test ($seconds s)"
        failed=1
    fi
done <<< "$slow"

# An entry for a test that now meets the 0.1 s goal only makes the list longer.
while read -r test _; do
    case "$test" in ''|'#'*) continue ;; esac
    seconds=$(awk -v t="$test" '$1 == t { print $2 }' <<< "$durations")
    if [ -z "$seconds" ] || awk -v s="$seconds" 'BEGIN { exit !(s < 0.1) }'; then
        echo "No longer slow, remove it from $allowed: $test"
    fi
done < "$allowed"

lines=$(wc -l < AGENTS.md)
if [ "$lines" -gt 150 ]; then
    echo "AGENTS.md has $lines lines. Keep it at 150 or fewer."
    failed=1
fi

exit $failed
