#!/bin/zsh
# Runs the unit tests, then the UI tests, on an iOS 17.5 iPad simulator (the wall
# iPad runs iPadOS 17).
#
# The screen tour (WallTourTests.testScreens) only takes screenshots for review,
# so it is skipped unless --tour is given; run it before deploying.
#
# --workers N runs UI tests on N simulator clones. On a 10-core, 16 GB Mac two
# clones were no faster than one simulator and made timing-sensitive tests flaky,
# so it is off by default; try it on an idle, bigger machine.
#
# Usage: scripts/test.sh [--tour] [--unit-only | --ui-only] [--workers N] [simulator-udid]
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

tour=0
unit=1
ui=1
workers=1
udid=""
while (( $# )); do
  case "$1" in
    --tour) tour=1 ;;
    --unit-only) ui=0 ;;
    --ui-only) unit=0 ;;
    --workers) shift; workers="$1" ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) udid="$1" ;;
  esac
  shift
done

if [[ -z "$udid" ]]; then
  udid=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
ipads = [d for runtime, list in devices.items() if "iOS-17-5" in runtime for d in list if "iPad" in d["name"]]
# Prefer one that is shut down: a booted one may be busy with a run from another checkout.
# (It gets booted for the run, and the next run reuses it.)
ipads.sort(key=lambda d: d["state"] == "Booted")
if not ipads: sys.exit(1)
print(ipads[0]["udid"])
') || { echo "No iOS 17.5 iPad simulator. Install the runtime: xcodebuild -downloadPlatform iOS -buildVersion 17.5" >&2; exit 1; }
fi

# One build folder per checkout, so worktrees don't overwrite each other's builds.
checkout=$(basename "$PWD")
derived="$HOME/Library/Developer/Xcode/DerivedData/Porchlight-${checkout}"
results="${TMPDIR:-/tmp}/porchlight-tests-${checkout}"
mkdir -p "$results"
common=(-project Porchlight.xcodeproj -destination "id=$udid" -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO)

# Keep only results, failures and the summary from xcodebuild's output.
summarize() {
  grep -E "error:|warning:|passed \(|failed \(|\*\* TEST|✘" | grep -v "Run script\|appintents\|strip-bitcode" || true
}

xcodegen generate --quiet
failed=0

if (( unit )); then
  echo "Unit tests on $udid"
  rm -rf "$results/unit.xcresult"
  xcodebuild test "${common[@]}" -scheme Porchlight -resultBundlePath "$results/unit.xcresult" 2>&1 | summarize || true
  xcrun xcresulttool get test-results summary --path "$results/unit.xcresult" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("Unit: %d/%d passed" % (d["passedTests"], d["totalTestCount"]))
sys.exit(0 if d["result"] == "Passed" else 1)
' || failed=1
fi

if (( ui )); then
  echo "UI tests on $udid$( (( workers > 1 )) && echo " ($workers clones)")$( (( tour )) && echo ', with the screen tour')"
  # The first-run test needs the calendar prompt, and resetting it needs a booted
  # simulator (clones copy this state too).
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl privacy "$udid" reset calendar com.mingyucao.porchlight
  skip=()
  (( tour )) || skip=(-skip-testing:PorchlightUITests/WallTourTests/testScreens)
  parallel=()
  (( workers > 1 )) && parallel=(-parallel-testing-enabled YES -parallel-testing-worker-count "$workers")
  rm -rf "$results/ui.xcresult"
  xcodebuild test "${common[@]}" -scheme PorchlightUI "${skip[@]}" "${parallel[@]}" \
    -resultBundlePath "$results/ui.xcresult" 2>&1 | summarize || true
  xcrun xcresulttool get test-results summary --path "$results/ui.xcresult" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("UI: %d/%d passed" % (d["passedTests"], d["totalTestCount"]))
sys.exit(0 if d["result"] == "Passed" else 1)
' || failed=1
fi

echo "Result bundles: $results"
exit $failed
