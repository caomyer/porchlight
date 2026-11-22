#!/bin/zsh
# Checks scripts/lib/slow_tests.py against sample logs: a test over the ceiling, or one in
# which XCTest gave up waiting for the app to go idle more than twice, is named with its
# seconds and its count, written to the job's summary, and marked so its suite's result
# bundle and the simulator's log are kept; a suite of ordinary tests says nothing and marks
# nothing. Runs anywhere in a second.
#
#   zsh scripts/ci/check-slow-tests.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
ok() { echo "ok: $1" }
bad() { echo "FAILED: $1"; cat "$work/out" 2>/dev/null; failures=$(( failures + 1 )) }
says() { if grep -qF -- "$2" "$3"; then ok "$1"; else bad "$1: no \"$2\""; fi }

run() {
  rm -f "$work/keep" "$work/summary"
  PORCHLIGHT_SUMMARY_FOR_CHECK=1 env "GITHUB_STEP_SUMMARY=$work/summary" python3 scripts/lib/slow_tests.py "UI wall" "$1" "$work/keep" > "$work/out" 2>&1
}

# As on November 22, 2026: a test that passed after 2,020 seconds, having given up on the
# app going idle before every step; and two ordinary tests beside it.
{
  cat <<'EOF'
Test Suite 'DayAtAGlanceTests' started at 2026-11-22 16:02:50.000.
Test Case '-[PorchlightUITests.DayAtAGlanceTests testMomentsInTheWeek]' started.
    t =     0.00s Start Test at 2026-11-22 16:02:50.000
    t =     7.03s         Wait for com.mingyucao.porchlight to idle
Test Case '-[PorchlightUITests.DayAtAGlanceTests testMomentsInTheWeek]' passed (24.144 seconds).
Test Case '-[PorchlightUITests.FirstRunTests testOnboardingWithRealCalendarAccess]' started.
    t =     0.00s Start Test at 2026-11-22 16:03:14.136
EOF
  for n in {1..33}; do
    echo "    t =   $(( n * 60 )).00s     Wait for com.mingyucao.porchlight to idle"
    echo "    t =   $(( n * 60 + 60 )).00s App animations complete notification not received, will attempt to continue."
  done
  cat <<'EOF'
Test Case '-[PorchlightUITests.FirstRunTests testOnboardingWithRealCalendarAccess]' passed (2019.579 seconds).
Test Case '-[PorchlightUITests.FoodMealsTests testAddingAMeal]' started.
    t =     0.00s Start Test at 2026-11-22 16:36:55.000
    t =    30.00s App animations complete notification not received, will attempt to continue.
Test Case '-[PorchlightUITests.FoodMealsTests testAddingAMeal]' passed (95.000 seconds).
** TEST EXECUTE SUCCEEDED **
EOF
} > "$work/runaway.log"
run "$work/runaway.log"
says "a test of 2,020 seconds is named, with its seconds" "FirstRunTests.testOnboardingWithRealCalendarAccess took 2020 seconds, over the ceiling of 120" "$work/out"
says "and its idle waits given up" "gave up waiting for the app to go idle 33 times (passed)" "$work/out"
[[ "$(grep -c "UI wall: " "$work/out")" == 1 ]] && ok "and it alone: one idle wait given up in a test of 95 seconds is not named" || bad "only the runaway is named"
says "the job's summary has its row" "| FirstRunTests.testOnboardingWithRealCalendarAccess | 2020 | 33 | passed |" "$work/summary"
says "and the suite's count" "Idle waits given up in the whole suite: 34." "$work/summary"
says "its suite is marked to keep, with the test's span in the log's own time" "FirstRunTests testOnboardingWithRealCalendarAccess 2026-11-22 16:03:14|2026-11-22 16:36:58" "$work/keep"

# Over the ceiling with no idle trouble, and idle trouble under the ceiling: each is named.
cat > "$work/each.log" <<'EOF'
Test Case '-[PorchlightUITests.PhoneSetupTests testSettingUp]' started.
    t =     0.00s Start Test at 2026-11-22 10:00:00.000
Test Case '-[PorchlightUITests.PhoneSetupTests testSettingUp]' passed (132.400 seconds).
Test Case '-[PorchlightUITests.PhoneTests testCareSheet]' started.
    t =     0.00s Start Test at 2026-11-22 10:03:00.000
    t =    60.00s App animations complete notification not received, will attempt to continue.
    t =   120.00s App animations complete notification not received, will attempt to continue.
    t =   180.00s App animations complete notification not received, will attempt to continue.
Test Case '-[PorchlightUITests.PhoneTests testCareSheet]' failed (110.000 seconds).
EOF
run "$work/each.log"
says "a test over the ceiling with no idle trouble" "PhoneSetupTests.testSettingUp took 132 seconds, over the ceiling of 120 (passed)" "$work/out"
says "a test under it that gave up on idle three times" "PhoneTests.testCareSheet took 110 seconds and gave up waiting for the app to go idle 3 times (failed)" "$work/out"
[[ "$(wc -l < "$work/keep" | tr -d ' ')" == 2 ]] && ok "both are marked to keep" || bad "both are marked to keep"

# A test stopped at the time limit has a start and no end: it is named and kept too.
cat > "$work/stopped.log" <<'EOF'
Test Case '-[PorchlightUITests.FirstRunTests testOnboardingWithRealCalendarAccess]' started.
    t =     0.00s Start Test at 2026-11-22 16:03:14.136
    t =    72.91s App animations complete notification not received, will attempt to continue.
Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.
** TEST EXECUTE FAILED **
EOF
run "$work/stopped.log"
says "a test that was stopped and never ended" "FirstRunTests.testOnboardingWithRealCalendarAccess never finished and gave up waiting for the app to go idle 1 time (no result)" "$work/out"
says "is marked to keep" "FirstRunTests testOnboardingWithRealCalendarAccess 2026-11-22 16:03:14|" "$work/keep"

# An ordinary suite: nothing said, nothing kept, nothing in the summary.
cat > "$work/plain.log" <<'EOF'
Test Case '-[PorchlightUITests.PhoneTests testCareSheet]' started.
    t =     0.00s Start Test at 2026-11-22 10:03:00.000
Test Case '-[PorchlightUITests.PhoneTests testCareSheet]' passed (21.000 seconds).
Test Case '-[PorchlightUITests.PhoneTests testYouSheet]' started.
Test Case '-[PorchlightUITests.PhoneTests testYouSheet]' passed (119.900 seconds).
** TEST EXECUTE SUCCEEDED **
EOF
run "$work/plain.log"
[[ ! -s "$work/out" && ! -e "$work/keep" && ! -e "$work/summary" ]] && ok "a suite of ordinary tests says nothing and keeps nothing" || bad "a suite of ordinary tests says nothing and keeps nothing"

# A few idle waits given up across a suite, no test more than twice: counted, not kept.
cat > "$work/few.log" <<'EOF'
Test Case '-[PorchlightUITests.PhoneTests testCareSheet]' started.
    t =    60.00s App animations complete notification not received, will attempt to continue.
    t =   120.00s App animations complete notification not received, will attempt to continue.
Test Case '-[PorchlightUITests.PhoneTests testCareSheet]' passed (118.000 seconds).
EOF
run "$work/few.log"
says "two idle waits given up in a suite are counted" "XCTest gave up waiting for the app to go idle 2 times, no test more than 2" "$work/out"
[[ ! -e "$work/keep" ]] && ok "and nothing is kept for them" || bad "nothing is kept for two"
says "but the summary shows them, green run or not" "| PhoneTests.testCareSheet | 118 | 2 | passed |" "$work/summary"

(( failures == 0 )) || { echo "$failures checks of the slow test report failed"; exit 1; }
echo "A test that runs long or waits on an app that will not go idle is named, counted and kept."
