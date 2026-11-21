#!/bin/zsh
# Checks scripts/lib/runner-start.sh against sample logs: a run whose test runner crashed
# before any test is seen as never started, and a runner that crashed after a test had
# started, or an ordinary failed test, is not. Runs anywhere in a second.
#
#   zsh scripts/ci/check-runner-start.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/runner-start.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0
expect() {
  local got
  if porchlight_runner_never_started "$2"; then got=yes; else got=no; fi
  if [[ "$got" == "$3" ]]; then echo "ok: $1"; else echo "FAILED: $1 (expected $3, got $got)"; failures=$(( failures + 1 )); fi
}

# As on November 20 and 21, 2026: the runner died while preparing, and no test started.
cat > "$work/preparing.log" <<'EOF'
Testing started
PorchlightUITests-Runner (5230) encountered an error (The test runner crashed while preparing to run tests: PorchlightUITests-Runner at -[XCTWaiter(StallHandling) handleStalledWait:]. If you believe this error represents a bug, please attach the result bundle.)
** TEST EXECUTE FAILED **
EOF
expect "a runner that crashed while preparing, with no test started" "$work/preparing.log" yes

cat > "$work/accessibility.log" <<'EOF'
Testing started
PorchlightUITests-Runner failed to initialize for UI testing: Timed out while loading Accessibility.
** TEST EXECUTE FAILED **
EOF
expect "a runner that never loaded Accessibility" "$work/accessibility.log" yes

# The same words after a test had started: a crash in the middle of the suite stands.
cat > "$work/midway.log" <<'EOF'
Test Suite 'PhoneTests' started at 2026-11-21 06:10:00.000.
Test Case '-[PorchlightUITests.PhoneTests testCareSheet]' started.
Test Case '-[PorchlightUITests.PhoneTests testCareSheet]' passed (21.000 seconds).
Test Case '-[PorchlightUITests.PhoneTests testCheckingChores]' started.
PorchlightUITests-Runner (5230) encountered an error (The test runner crashed while preparing to run tests: PorchlightUITests-Runner at -[XCTWaiter(StallHandling) handleStalledWait:])
** TEST EXECUTE FAILED **
EOF
expect "a runner that crashed after a test had started" "$work/midway.log" no

cat > "$work/failed.log" <<'EOF'
Test Case '-[PorchlightUITests.PhoneTests testCareSheet]' started.
/Users/runner/work/porchlight/PhoneTests.swift:80: error: -[PorchlightUITests.PhoneTests testCareSheet] : XCTAssertTrue failed
Test Case '-[PorchlightUITests.PhoneTests testCareSheet]' failed (21.000 seconds).
** TEST EXECUTE FAILED **
EOF
expect "an ordinary failed test" "$work/failed.log" no

cat > "$work/passed.log" <<'EOF'
Test Case '-[PorchlightUITests.PhoneTests testCareSheet]' started.
Test Case '-[PorchlightUITests.PhoneTests testCareSheet]' passed (21.000 seconds).
** TEST EXECUTE SUCCEEDED **
EOF
expect "a run that passed" "$work/passed.log" no
expect "no log at all" "$work/missing.log" no

(( failures == 0 )) || { echo "$failures checks of the runner's start failed"; exit 1; }
echo "A run in which no test started is told apart from a failure."
