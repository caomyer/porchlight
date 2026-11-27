#!/bin/zsh
# Builds once, then runs the unit tests and both UI suites, the wall's on an iPad and the
# phone's on an iPhone, on iOS 17.5 simulators of this checkout's own.
#
#   scripts/test.sh                 everything: unit and the wall's UI suite on the iPad, the phone's on the iPhone
#   scripts/test.sh --smoke         unit and a few UI tests on each: the gate before installing
#   scripts/test.sh --unit-only     only the unit tests
#   scripts/test.sh --unit Suite ...   just these unit suites, by type name (and no UI tests)
#   scripts/test.sh --ui-only       only the UI suites
#   scripts/test.sh --wall          only the wall's UI suite (with --ui-only, no unit tests)
#   scripts/test.sh --phone         only the phone's UI suite (with --ui-only, no unit tests)
#   scripts/test.sh --only Class/testName ...   just these UI tests (and no unit tests)
#   scripts/test.sh --serial        the iPad and then the iPhone, even with two test slots free
#   scripts/test.sh --tour          also the wall's screen tour, which only takes screenshots for review
#   scripts/test.sh --runtime <id>  another iOS, e.g. com.apple.CoreSimulator.SimRuntime.iOS-26-5
#   scripts/test.sh --workers N     each UI suite on N clones of its simulator
#   scripts/test.sh --no-build      reuse the last build
#   scripts/test.sh --build-only    only build, for every suite
#   scripts/test.sh --shard I/N     only the I-th of N even shares of each UI suite's test classes
#   scripts/test.sh --progress      also print each test as it ends, so a hang shows where
#   scripts/test.sh <udid>          the given simulator instead of this checkout's own (one suite)
#
# Each checkout makes its own simulators ("Porchlight <checkout> ipad" and "... iphone"), so
# runs from different worktrees never share one. A run holds its simulators, and the Mac's
# test slots (one per 8 GB of memory, so simulators never push it into swap), with file locks
# the system releases the moment the run ends, however it ends (scripts/lib/simulators.sh).
# With two slots free the iPad and the iPhone run side by side, else one after the other.
# Prints how long each step took. Result bundles go to $TMPDIR/porchlight-tests-<checkout>.
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# When tests fail, xcodebuild collects diagnostics with `xcrun simctl` in an environment
# without DEVELOPER_DIR; on a Mac whose xcode-select points at the Command Line Tools, xcrun
# then finds simctl only on the PATH.
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
source scripts/lib/simulators.sh
# PosterBoard stays off on a development Mac too, as on the hosted Macs: on iOS 27 it keeps
# its rendered wallpapers in the simulator and adds to them at every boot, and one iPad
# simulator here had 31 GB of them (PRBPosterExtensionDataStore) after a month of runs. The
# wallpaper is black and nothing else differs. PORCHLIGHT_SIM_DISABLED_DAEMONS=none starts it.
export PORCHLIGHT_SIM_DISABLED_DAEMONS="${PORCHLIGHT_SIM_DISABLED_DAEMONS:-com.apple.PosterBoard}"
source scripts/lib/stage.sh
source scripts/lib/runner-start.sh

unit=1
ui=1
wall_asked=0
phone_asked=0
serial=0
smoke=0
tour=0
build=1
workers=1
udid=""
only=()
unit_suites=()
build_only=0
shard=""
progress=0
while (( $# )); do
  case "$1" in
    --build-only) build_only=1; ui=0 ;;
    --shard) shift; shard="$1" ;;
    --progress) progress=1 ;;
    --unit-only) ui=0 ;;
    --unit) shift; ui=0; while (( $# )) && [[ "$1" != -* ]]; do unit_suites+=("$1"); shift; done; continue ;;
    --ui-only) unit=0 ;;
    --wall) wall_asked=1 ;;
    --phone) phone_asked=1 ;;
    --parallel) serial=0 ;;
    --serial) serial=1 ;;
    --smoke) smoke=1 ;;
    --tour) tour=1 ;;
    --no-build) build=0 ;;
    --workers) shift; workers="$1" ;;
    --runtime) shift; porchlight_sim_runtime="$1" ;;
    --only) shift; while (( $# )) && [[ "$1" != -* ]]; do only+=("$1"); shift; done; continue ;;
    -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) udid="$1" ;;
  esac
  shift
done

# The phone's UI test classes are the ones named Phone…Tests; a list kept by hand missed new
# ones, which then went to the iPad and skipped themselves there.
phone_classes=(PorchlightUITests/Phone*Tests.swift(:t:r))

# Which UI suites: both unless one was named. Named tests go to the suite they belong to.
wall=1 phone=1
if (( wall_asked || phone_asked )); then
  wall=$wall_asked
  phone=$phone_asked
fi
wall_only=()
phone_only=()
if (( ${#only} )); then
  unit=0
  for test in $only; do
    if (( ${phone_classes[(Ie)${test%%/*}]} )); then phone_only+=("$test"); else wall_only+=("$test"); fi
  done
  wall=$(( ${#wall_only} > 0 ))
  phone=$(( ${#phone_only} > 0 ))
fi
(( ui )) || { wall=0; phone=0; }

# The smoke set: one journey for each major area on each shell, about ten minutes of tests
# in all. It is the gate before installing, and what a push to a working branch runs on
# GitHub (docs/design/testing.md, "Tiers"). This is the one place it is defined; when a
# journey's test is renamed or merged, change it here, and keep one per area.
smoke_wall=(
  DayAtAGlanceTests/testCheckingOffAChoreOnToday                  # Today and chores
  DayAtAGlanceTests/testMomentsInTheWeek                          # the calendar
  LoggedEntryTests/testFixingAWalkFromToday                       # care: log, celebrate, fix
  WallDishEditorTests/testHomeMealTypedWithASuggestion            # food: a meal and its dishes
  HouseholdTests/testFamilyAndDevicesShowsEveryoneAndBothWaysIn   # the household and inviting
  SyncSettingsTests/testAFullICloudPausesSync                     # sync's states in Settings
  FirstRunTests/testOnboardingWithRealCalendarAccess              # first run, with the real prompt
)
smoke_phone=(
  PhoneTests/testOneTapLogAndUndo                                 # Today: care in one tap
  PhoneTabsTests/testPitchInAndAddingAChore                       # chores
  PhoneTabsTests/testListsAndDinners                              # lists
  PhoneFoodTests/testSnappingAMeal                                # food: the camera to the diary
  PhoneHouseholdTests/testJoiningFromAnInvite                     # joining a household
  PhoneSetupTests/testStartingAHouseholdOnThisPhone               # starting one, and every tab empty
)

# One build folder per checkout, so worktrees don't overwrite each other's builds.
checkout=$(basename "$PWD")
derived="$HOME/Library/Developer/Xcode/DerivedData/Porchlight-${checkout}"
results="${TMPDIR:-/tmp}/porchlight-tests-${checkout}"
mkdir -p "$results"
# Simulators on this Mac are arm64; a generic destination would build Intel too.
flags=(-derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO -skipMacroValidation ARCHS=arm64)

# Keep only results, failures and the summary from xcodebuild's output.
summarize() {
  grep -E "error:|passed \(|failed \(|\*\* (TEST|BUILD)|✘" | grep -v "Run script\|appintents\|strip-bitcode" || true
}

# Keeps xcodebuild's whole output in the log `$1`; with --progress also prints each test as
# it ends, so a run that hangs shows where.
record() {
  if (( progress )); then
    tee "$1" | grep --line-buffered -E "^Test Case .*(passed|failed|skipped)|Test .*(passed after|failed after|skipped\.)" | sed -l "s/^/[${1:t:r}] /" || true
  else
    cat > "$1"
  fi
}

started=$SECONDS
timings=()
# Each step's time, said as it ends and again at the end (a background job's list stays
# with it, so side by side only the overall times are repeated).
took() {
  local line=$(printf '%-12s %5ds' "$1" $(( SECONDS - $2 )))
  timings+=("$line")
  echo "Took: $line"
}

# Simulators: the one given, else this checkout's own.
ipad="" iphone=""
if (( (unit || wall) && ! build_only )); then
  if [[ -n "$udid" ]] && ! (( phone )); then ipad=$udid; else ipad=$(porchlight_simulator ipad); fi
fi
if (( phone )); then
  if [[ -n "$udid" ]] && ! (( unit || wall )); then iphone=$udid; else iphone=$(porchlight_simulator iphone); fi
fi
for sim in $ipad $iphone; do porchlight_hold_simulator "$sim"; done
both=$(( ${#ipad} && ${#iphone} ))

# Shut the simulators down on every way out this shell sees, to give the memory back. A run
# killed outright leaves its simulators booted but no longer held, and the next run from
# this checkout shuts them down (never another checkout's: scripts/lib/simulators.sh).
cleanup() {
  for sim in $ipad $iphone; do xcrun simctl shutdown "$sim" >/dev/null 2>&1 || true; done
}
trap cleanup EXIT INT TERM HUP
boot() { porchlight_boot_simulator "$1"; }
shut() { xcrun simctl shutdown "$1" >/dev/null 2>&1 || true; }

if (( build )); then
  step=$SECONDS
  xcodegen generate --quiet
  echo "Building for testing"
  # The UI scheme builds the app and the UI tests; the unit scheme adds the unit tests.
  xcodebuild build-for-testing -project Porchlight.xcodeproj -scheme PorchlightUI \
    -destination 'generic/platform=iOS Simulator' "${flags[@]}" 2>&1 | summarize
  if (( unit )); then
    xcodebuild build-for-testing -project Porchlight.xcodeproj -scheme Porchlight \
      -destination 'generic/platform=iOS Simulator' "${flags[@]}" 2>&1 | summarize
  fi
  took build $step
fi
(( build_only )) && exit 0

# The Mac's test slots: one per simulator booted at a time. Two free means side by side.
step=$SECONDS
porchlight_take_slots $(( both && ! serial ? 2 : 1 ))
(( SECONDS - step < 2 )) || took "waiting" $step
parallel=$(( porchlight_slots >= 2 ))

xctestrun() {
  local found=("$derived"/Build/Products/${1}_iphonesimulator*.xctestrun(Nom))
  (( ${#found} )) || { echo "No build of $1 to test: run without --no-build" >&2; return 1; }
  print -r -- "${found[1]}"
}

# Prints "<name>: passed/total", and how many failed, from a result bundle, and fails unless
# it passed; "did not finish" only when the run left no results.
report() {
  local summary
  # Tests run a second time after their app never launched count by that second run.
  if [[ -e "${2%.xcresult}-retry.xcresult" ]]; then
    python3 scripts/lib/launch_retry.py report "$1" "$2" "${2%.xcresult}-retry.xcresult"
    return
  fi
  summary=$(xcrun xcresulttool get test-results summary --path "$2" 2>/dev/null) || true
  if [[ -z "$summary" ]]; then
    echo "$1: did not finish, see $results/${2:t:r}.log"
    return 1
  fi
  print -r -- "$summary" | python3 -c '
import json, sys
d = json.load(sys.stdin)
skipped = " (%d skipped)" % d["skippedTests"] if d["skippedTests"] else ""
failed = ", %d failed" % d["failedTests"] if d["failedTests"] else ""
print("%s: %d/%d passed%s%s" % (sys.argv[1], d["passedTests"], d["totalTestCount"], failed, skipped))
# A suite that was asked for and ran nothing (a test name that matched none, or only tests
# that skipped themselves) is no pass.
if d["passedTests"] + d["failedTests"] == 0:
    print("%s: no tests ran" % sys.argv[1])
    sys.exit(1)
sys.exit(0 if d["result"] == "Passed" else 1)
' "$1"
}

# A suite's verdict: `verdict <name> <result bundle> <log>`. What the result bundle says
# (`report`), and then two things a result bundle can miss. A test process that crashes or
# exits partway is started again by xcodebuild, and the last launch then prints "Test run
# with N tests passed" for the tests that were left: the log is read for a process that was
# lost, a test that started and never reported, and a suite that never finished
# (scripts/lib/lost_process.py). And xcodebuild's own status, kept beside the log, must
# agree with a pass. Either one fails the suite, whatever its totals say.
verdict() {
  local name=$1 bundle=$2 log=$3 bad=0 xcode
  report "$name" "$bundle" || bad=1
  python3 scripts/lib/lost_process.py "$name" "$log" || bad=1
  [[ -e "${log%.log}-retry.log" ]] && { python3 scripts/lib/lost_process.py "$name, again" "${log%.log}-retry.log" || bad=1 }
  # With tests run a second time, the first run's status is a failure by design.
  if (( ! bad )) && [[ ! -e "${bundle%.xcresult}-retry.xcresult" ]]; then
    xcode=$(cat "${log%.log}.status" 2>/dev/null) || xcode=""
    if [[ "$xcode" != 0 ]]; then
      echo "$name: xcodebuild ended with status ${xcode:-unknown} though every test it reported passed, so this run is failed: see $log"
      bad=1
    fi
  fi
  return $bad
}

# The longest one UI test may run, in seconds, before xcodebuild stops it and fails it. The
# ceiling a test is written to is 120 (docs/design/testing.md, "Budgets"); this is the hard
# stop, which no healthy test comes near on the slowest hosted Mac seen (164 seconds), and
# which a test that has run away meets: on November 22, 2026 one passed after 2,020
# seconds. xcodebuild counts in whole minutes.
test_limit=${PORCHLIGHT_TEST_LIMIT_SECONDS:-420}
limits=(-test-timeouts-enabled YES -default-test-execution-time-allowance "$test_limit" -maximum-test-execution-time-allowance "$test_limit")

# After a UI suite: names the tests that took longer than the ceiling or waited on an app
# that would not go idle (scripts/lib/slow_tests.py), and for each keeps the simulator's
# own log of the app over the test's span, beside the suite's log. The suite's whole result
# bundle is then kept too (scripts/ci/collect-results.sh), green run or not.
slow_tests() {
  local name=$1 sim=$2 log=$3 keep="${3%.log}.keep" class test span from to
  rm -f "$keep"
  python3 scripts/lib/slow_tests.py "$name" "$log" "$keep" || true
  [[ -s "$keep" ]] || return 0
  while read -r class test span; do
    from=${span%%|*} to=${span##*|}
    [[ -n "$from" && -n "$to" ]] || continue
    # Bounded twice: two minutes to read the log, and 40 MB of it before it is packed.
    porchlight_stage "the simulator's log for $class.$test" 120 zsh -c \
      'xcrun simctl spawn "$1" log show --start "$2" --end "$3" --style compact --predicate "process == \"Porchlight\"" 2>/dev/null | head -c 40000000 | gzip > "$4"' \
      - "$sim" "$from" "$to" "${log%.log}-$class-$test-simulator.log.gz" || true
  done < "$keep"
}

# Runs one UI suite: `ui_suite <name> <udid> <selection...>`, into $results/<name>.xcresult.
ui_suite() {
  local name=$1 sim=$2
  shift 2
  local clones=()
  (( workers > 1 )) && clones=(-parallel-testing-enabled YES -parallel-testing-worker-count "$workers")
  local attempt
  for attempt in 1 2; do
    rm -rf "$results/$name.xcresult"
    { xcodebuild test-without-building -xctestrun "$(xctestrun PorchlightUI)" -destination "id=$sim" \
      "$@" "${clones[@]}" "${limits[@]}" -resultBundlePath "$results/$name.xcresult"; echo $? > "$results/$name.status" } 2>&1 | record "$results/$name.log" || true
    # A simulator under memory pressure can fail to start the test runner at all ("Timed out
    # while loading Accessibility", the runner crashing before it connects, or "The test
    # runner crashed while preparing to run tests"). No test started, so the whole run is
    # made once more; a second time is a failure that says so. A runner that dies after a
    # test has started is never run again here: that is a real failure
    # (scripts/lib/runner-start.sh).
    porchlight_runner_never_started "$results/$name.log" || break
    if (( attempt == 2 )); then
      echo "[$name] The test runner crashed before any test started, twice. No test ran: this is the Mac or the simulator, not a test (docs/design/testing.md, \"Infrastructure failures\")."
      break
    fi
    echo "[$name] The test runner crashed before any test started; running the suite once more"
    cp "$results/$name.log" "$results/$name-never-started.log"
  done
  summarize < "$results/$name.log" | grep -v "passed (" | sed "s/^/[$name] /"
  slow_tests "$name" "$sim" "$results/$name.log"
  # A test XCTest could not start the app for, on a busy simulator, runs once more on its own; any
  # other failure stands (scripts/lib/launch_retry.py).
  local again test
  local -a retry=()
  rm -rf "$results/$name-retry.xcresult" "$results/$name-retry.log"
  again=$(python3 scripts/lib/launch_retry.py failures "$results/$name.xcresult" 2>/dev/null) || again=""
  for test in ${(f)again}; do retry+=(-only-testing:PorchlightUITests/$test); done
  (( ${#retry} )) || return 0
  echo "[$name] XCTest could not start the app for ${(j:, :)${(f)again}}; running them once more"
  xcodebuild test-without-building -xctestrun "$(xctestrun PorchlightUI)" -destination "id=$sim" \
    "${retry[@]}" "${limits[@]}" -resultBundlePath "$results/$name-retry.xcresult" 2>&1 | record "$results/$name-retry.log" || true
  summarize < "$results/$name-retry.log" | grep -v "passed (" | sed "s/^/[$name, again] /"
}

# With --shard I/N, a suite's classes go to N shares of about equal time, each class,
# longest first, to the share with the least so far; prints share I's classes. Times are
# measured ones (scripts/lib/ui-test-seconds), else 30 seconds a test.
shard_of() {
  local i=${shard%/*} n=${shard#*/} class k least seconds
  local -a weights=() mine=()
  for (( k = 1; k <= n; k++ )); do weights[k]=0; done
  # The unit tests run on the Mac that runs the wall's first share, so that share starts
  # with their seconds already counted (the `UnitTests` line), in every job's sums alike.
  if [[ "$1" == --with-unit-tests ]]; then
    shift
    weights[1]=$(awk '$1 == "UnitTests" { print $2 }' scripts/lib/ui-test-seconds)
    weights[1]=${weights[1]:-0}
  fi
  for seconds class in $(for class in "$@"; do
      seconds=$(awk -v c="$class" '$1 == c { print $2 }' scripts/lib/ui-test-seconds)
      print -r -- "${seconds:-$(( 30 * $(grep -c 'func test' PorchlightUITests/$class.swift) ))} $class"
    done | sort -k1,1nr -k2,2); do
    least=1
    for (( k = 2; k <= n; k++ )); do
      if (( weights[k] < weights[least] )); then least=$k; fi
    done
    (( weights[least] += seconds ))
    if (( least == i )); then mine+=("$class"); fi
  done
  (( ${#mine} )) || { echo "Shard $shard has no test classes" >&2; return 1; }
  print -r -- $mine
}

wall_args=()
phone_args=()
if (( wall )); then
  if (( ${#wall_only} )); then
    for test in $wall_only; do wall_args+=(-only-testing:PorchlightUITests/$test); done
  elif (( smoke )); then
    for test in $smoke_wall; do wall_args+=(-only-testing:PorchlightUITests/$test); done
  elif [[ -n "$shard" ]]; then
    wall_classes=(PorchlightUITests/*Tests.swift(:t:r))
    wall_classes=(${wall_classes:|phone_classes})
    classes=$(shard_of --with-unit-tests $wall_classes) || exit 1
    for class in ${=classes}; do wall_args+=(-only-testing:PorchlightUITests/$class); done
    (( tour )) || wall_args+=(-skip-testing:PorchlightUITests/WallTourTests/testScreens -skip-testing:PorchlightUITests/WallTourTests/testRecipeScreens -skip-testing:PorchlightUITests/WallTourTests/testCalendarScreens)
  else
    for class in $phone_classes; do wall_args+=(-skip-testing:PorchlightUITests/$class); done
    (( tour )) || wall_args+=(-skip-testing:PorchlightUITests/WallTourTests/testScreens -skip-testing:PorchlightUITests/WallTourTests/testRecipeScreens -skip-testing:PorchlightUITests/WallTourTests/testCalendarScreens)
  fi
fi
if (( phone )); then
  if (( ${#phone_only} )); then
    for test in $phone_only; do phone_args+=(-only-testing:PorchlightUITests/$test); done
  elif (( smoke )); then
    for test in $smoke_phone; do phone_args+=(-only-testing:PorchlightUITests/$test); done
  elif [[ -n "$shard" ]]; then
    classes=$(shard_of $phone_classes) || exit 1
    for class in ${=classes}; do phone_args+=(-only-testing:PorchlightUITests/$class); done
  else
    for class in $phone_classes; do phone_args+=(-only-testing:PorchlightUITests/$class); done
  fi
fi

failed=0

run_ipad() {
  local step=$SECONDS
  boot "$ipad"
  took "boot ipad" $step
  # An app from before the rename must never sit beside this one.
  xcrun simctl uninstall "$ipad" com.porchlight.porchlight 2>/dev/null || true
  if (( unit )); then
    step=$SECONDS
    echo "Unit tests on $ipad"
    rm -rf "$results/unit.xcresult"
    unit_args=()
    for suite in $unit_suites; do unit_args+=(-only-testing:PorchlightTests/$suite); done
    { xcodebuild test-without-building -xctestrun "$(xctestrun Porchlight)" -destination "id=$ipad" $unit_args \
      -resultBundlePath "$results/unit.xcresult"; echo $? > "$results/unit.status" } 2>&1 | record "$results/unit.log" || true
    summarize < "$results/unit.log" | grep -v "passed ("
    verdict Unit "$results/unit.xcresult" "$results/unit.log" || failed=1
    took unit $step
  fi
  if (( wall )); then
    step=$SECONDS
    echo "Wall UI tests on $ipad"
    ui_suite ui-wall "$ipad" "${wall_args[@]}"
    verdict "UI wall" "$results/ui-wall.xcresult" "$results/ui-wall.log" || failed=1
    took "ui wall" $step
  fi
}

run_iphone() {
  local step=$SECONDS
  boot "$iphone"
  took "boot phone" $step
  step=$SECONDS
  echo "Phone UI tests on $iphone"
  ui_suite ui-phone "$iphone" "${phone_args[@]}"
  verdict "UI phone" "$results/ui-phone.xcresult" "$results/ui-phone.log" || failed=1
  took "ui phone" $step
}

if (( parallel )); then
  step=$SECONDS
  # The two report through files, since a background job's variables stay with it.
  ( run_ipad; exit $failed ) & ipad_job=$!
  ( run_iphone; exit $failed ) & iphone_job=$!
  wait $ipad_job || failed=1
  wait $iphone_job || failed=1
  took "side by side" $step
else
  if [[ -n "$ipad" ]] && (( unit || wall )); then
    run_ipad
    shut "$ipad"
  fi
  if [[ -n "$iphone" ]]; then
    run_iphone
    shut "$iphone"
  fi
fi

took total $started
print -l -- "Time:" "  "${^timings}
echo "Result bundles: $results"
exit $failed
