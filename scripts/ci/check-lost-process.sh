#!/bin/zsh
# Checks scripts/lib/lost_process.py against sample logs: a run whose test process was lost
# partway is failed, with the test it was in named, even when the last thing the log says
# is that the tests passed; and a clean run, an ordinary failed test and a runner that never
# started a test are none of its business. Runs anywhere in a second.
#
#   zsh scripts/ci/check-lost-process.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

# `expect <what> <log> <lost|kept> [words the output must hold]`
expect() {
  local got rc=0
  python3 scripts/lib/lost_process.py Unit "$2" > "$work/out" 2>&1 || rc=$?
  (( rc == 0 )) && got=kept || got=lost
  if [[ "$got" != "$3" ]]; then
    echo "FAILED: $1 (expected $3, got $got)"; cat "$work/out"; failures=$(( failures + 1 )); return
  fi
  if [[ -n "${4:-}" ]] && ! grep -qF -- "$4" "$work/out"; then
    echo "FAILED: $1: no \"$4\" in:"; cat "$work/out"; failures=$(( failures + 1 )); return
  fi
  echo "ok: $1"
}

# A clean run, Swift Testing and XCTest together, with a parameterized test and a skip.
cat > "$work/clean.log" <<'EOF'
Test Suite 'All tests' started at 2026-11-22 05:24:13.124.
Test Suite 'PhoneTests' started at 2026-11-22 05:24:13.124.
Test Case '-[PorchlightUITests.PhoneTests testCareSheet]' started.
Test Case '-[PorchlightUITests.PhoneTests testCareSheet]' passed (21.000 seconds).
Test Case '-[PorchlightUITests.PhoneTests testByHand]' started.
Test Case '-[PorchlightUITests.PhoneTests testByHand]' skipped (0.010 seconds).
Test Suite 'PhoneTests' passed at 2026-11-22 05:24:40.000.
Test Suite 'All tests' passed at 2026-11-22 05:24:40.001.
◇ Test run started.
◇ Suite "Widget timelines" started.
◇ Test "Widgets use the app's time words" started.
✔ Test "Widgets use the app's time words" passed after 0.001 seconds.
◇ Test "Each hour" started.
◇ Test case passing 1 argument hour → 8 to "Each hour" started.
✔ Test case passing 1 argument hour → 8 to "Each hour" passed after 0.001 seconds.
✔ Test "Each hour" with 1 test case passed after 0.002 seconds.
◇ Test theSkyFollowsTheDay() started.
✘ Test theSkyFollowsTheDay() failed after 0.004 seconds with 1 issue.
➜ Test "Only by hand" skipped.
✔ Suite "Widget timelines" passed after 0.009 seconds.
✔ Test run with 3 tests in 1 suite passed after 0.010 seconds.
** TEST EXECUTE SUCCEEDED **
EOF
expect "a run that kept its process, with a parameterized test, a failed test and a skip" "$work/clean.log" kept

# As on November 22, 2026: the process crashed in one test, xcodebuild started it again
# twice, and the last launch said the tests that were left had passed.
cat > "$work/crashed.log" <<'EOF'
◇ Test run started.
◇ Suite "A hosted screen" started.
◇ Test "The screen fits" started.
PorchlightTests/HarnessCrashTests.swift:22: Fatal error: No Observable object of type ToastCenter found
2026-11-22 05:24:26.667085-0800 Porchlight[67319:16462805] PorchlightTests/HarnessCrashTests.swift:22: Fatal error: No Observable object of type ToastCenter found
Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.
◇ Test run started.
◇ Suite "A hosted screen" started.
✔ Suite "A hosted screen" passed after 0.001 seconds.
◇ Suite "Widget timelines" started.
◇ Test "Widgets use the app's time words" started.
✔ Test "Widgets use the app's time words" passed after 0.001 seconds.
✔ Suite "Widget timelines" passed after 0.009 seconds.
✔ Test run with 450 tests in 81 suites passed after 158.237 seconds.
EOF
expect "a process that crashed partway, though the log ends with the tests passing" "$work/crashed.log" lost "the test process was lost once"
expect "and names the test it was in" "$work/crashed.log" lost '1 of the 2 tests that started never reported a result: "The screen fits"'
expect "and says what the log said, once" "$work/crashed.log" lost "the log says: PorchlightTests/HarnessCrashTests.swift:22: Fatal error: No Observable object of type ToastCenter found"

# The process ends without a word and is not started again: the log just stops.
cat > "$work/stopped.log" <<'EOF'
◇ Test run started.
◇ Suite "Sync" started.
◇ Test "Two devices agree" started.
✔ Test "Two devices agree" passed after 0.100 seconds.
◇ Test "A third joins" started.
EOF
expect "a log that stops in the middle of a test" "$work/stopped.log" lost '"A third joins"'
expect "and in the middle of its suite" "$work/stopped.log" lost '1 suite began and never finished: "Sync"'

# A UI shard whose runner died after tests had passed.
cat > "$work/shard.log" <<'EOF'
Test Suite 'PhoneTests' started at 2026-11-21 06:10:00.000.
Test Case '-[PorchlightUITests.PhoneTests testCareSheet]' started.
Test Case '-[PorchlightUITests.PhoneTests testCareSheet]' passed (21.000 seconds).
Test Case '-[PorchlightUITests.PhoneTests testCheckingChores]' started.
Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.
Test Suite 'PhoneTests' started at 2026-11-21 06:12:00.000.
Test Case '-[PorchlightUITests.PhoneTests testYouSheet]' started.
Test Case '-[PorchlightUITests.PhoneTests testYouSheet]' passed (30.000 seconds).
Test Suite 'PhoneTests' passed at 2026-11-21 06:13:00.000.
** TEST EXECUTE SUCCEEDED **
EOF
expect "a UI shard whose runner died after some tests had passed" "$work/shard.log" lost "-[PorchlightUITests.PhoneTests testCheckingChores]"

# Not this rule's business: an ordinary failure, and a runner that never started a test
# (scripts/lib/runner-start.sh runs that once more).
cat > "$work/failed.log" <<'EOF'
Test Suite 'PhoneTests' started at 2026-11-21 06:10:00.000.
Test Case '-[PorchlightUITests.PhoneTests testCareSheet]' started.
/Users/runner/work/porchlight/PhoneTests.swift:80: error: -[PorchlightUITests.PhoneTests testCareSheet] : XCTAssertTrue failed
Test Case '-[PorchlightUITests.PhoneTests testCareSheet]' failed (21.000 seconds).
Test Suite 'PhoneTests' failed at 2026-11-21 06:10:21.000.
** TEST EXECUTE FAILED **
EOF
expect "an ordinary failed test" "$work/failed.log" kept
cat > "$work/preparing.log" <<'EOF'
Testing started
PorchlightUITests-Runner (5230) encountered an error (The test runner crashed while preparing to run tests: PorchlightUITests-Runner at -[XCTWaiter(StallHandling) handleStalledWait:])
** TEST EXECUTE FAILED **
EOF
expect "a runner that never started a test" "$work/preparing.log" kept

# The app writes into the same log, and a stray character before a result must not make a
# good run look like one that lost a test.
printf '◇ Suite "Sync v1 migration" started.\n◇ Test "Rows move" started.\n\xe2\x80\x8b✔ Test "Rows move" passed after 0.300 seconds.\n\xe2\x80\x8b✔ Suite "Sync v1 migration" passed after 0.396 seconds.\n' > "$work/stray.log"
expect "a result line with a stray character before it" "$work/stray.log" kept
expect "no log at all" "$work/missing.log" kept

(( failures == 0 )) || { echo "$failures checks of the lost process rule failed"; exit 1; }
echo "A run that loses its process is failed, and names the test it was in."
