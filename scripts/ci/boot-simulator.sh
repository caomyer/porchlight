#!/bin/zsh
# Boots this checkout's simulator of a kind (ipad or iphone) on $RUNTIME, the one
# scripts/test.sh then picks up already booted, so the log shows the boot's time apart.
#
# A brand-new iOS 27 simulator keeps setting itself up for minutes after it says it has
# booted, and the first thing asked of it (installing, or uninstalling an app) waits for
# that; asking here keeps that wait out of the tests' time too.
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/simulators.sh
porchlight_sim_runtime=$RUNTIME

step=$SECONDS
udid=$(porchlight_simulator "$1")
porchlight_boot_simulator "$udid"
echo "Booted $1 $udid in $(( SECONDS - step ))s"
step=$SECONDS
xcrun simctl uninstall "$udid" com.porchlight.porchlight 2>/dev/null || true
echo "Ready for installs in $(( SECONDS - step ))s more"

# An experiment, begun November 21, 2026 (docs/design/testing.md, "Infrastructure
# failures"): the first test class after a boot has twice had its test runner crash before
# any test started, and twice had a keyboard that took no keys. So before the tests, an app
# is launched and quit once and the simulator is given a quarter of a minute, to let launch
# services, the keyboard's and SpringBoard's first-time work happen before a test depends
# on them. PORCHLIGHT_SETTLE_SECONDS=0 turns it off. It stays only if those failures stop
# over a few weeks of runs; this line's seconds are its cost for each job.
settle=${PORCHLIGHT_SETTLE_SECONDS:-15}
if (( settle > 0 )); then
  step=$SECONDS
  xcrun simctl launch "$udid" com.apple.Preferences >/dev/null 2>&1 || true
  sleep "$settle"
  xcrun simctl terminate "$udid" com.apple.Preferences >/dev/null 2>&1 || true
  echo "Settled in $(( SECONDS - step ))s more: Settings launched and quit"
fi
