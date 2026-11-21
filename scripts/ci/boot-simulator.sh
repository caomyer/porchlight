#!/bin/zsh
# Boots this checkout's simulator of a kind (ipad or iphone) on $RUNTIME, the one
# scripts/test.sh then picks up already booted, so the log shows the boot's time apart.
#
# A brand-new iOS 27 simulator keeps setting itself up for minutes after it says it has
# booted, and the first thing asked of it (installing, or uninstalling an app) waits for
# that; asking here keeps that wait out of the tests' time too.
#
# Each stage has a time limit of its own (scripts/lib/stage.sh), and a stage that stalls is
# named in the log and fails the job, saying that no test ran. A stall is not tried again:
# a simulator that is slow is slow because the Mac is short of memory or of processor, and
# erasing it and booting it once more makes it do all of its first-boot work a second time
# on that same Mac (measured on November 21, 2026; docs/design/testing.md, "Infrastructure
# failures"). Only a boot that fails outright, with an error rather than by running out of
# time, is shut down, erased and tried once more.
#
#   PORCHLIGHT_BOOT_SECONDS    the limit for booting (default 600: a new iOS 27 simulator
#                              has taken up to eight and a half minutes)
#   PORCHLIGHT_READY_SECONDS   the limit for the first uninstall to answer (default 420: it
#                              has taken up to four minutes)
set -uo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/simulators.sh
source scripts/lib/stage.sh
porchlight_sim_runtime=$RUNTIME

boot_limit=${PORCHLIGHT_BOOT_SECONDS:-600}
ready_limit=${PORCHLIGHT_READY_SECONDS:-420}
kind=$1

udid=$(porchlight_simulator "$kind") || exit 1

# The first uninstall on a new simulator waits for it to finish setting itself up; there
# being no such app to uninstall is its usual answer, and fine.
ready_for_installs() {
  xcrun simctl uninstall "$1" com.porchlight.porchlight 2>/dev/null
  return 0
}

stalled() {
  echo "::error::The $kind simulator stalled at \"$1\": it had not finished after $2 seconds. No test ran: this is the Mac or the simulator, not a test. Run the job again."
  exit 1
}

started=$SECONDS
porchlight_stage "boot the $kind" "$boot_limit" porchlight_boot_simulator "$udid"
booted=$?
(( booted == 124 )) && stalled "boot the $kind" "$boot_limit"
if (( booted != 0 )); then
  echo "::warning::The $kind simulator failed to boot. Shutting it down, erasing it and booting it once more."
  xcrun simctl shutdown "$udid" >/dev/null 2>&1
  porchlight_stage "erase the $kind" 120 xcrun simctl erase "$udid" || true
  porchlight_stage "boot the $kind" "$boot_limit" porchlight_boot_simulator "$udid"
  booted=$?
  (( booted == 124 )) && stalled "boot the $kind" "$boot_limit"
  if (( booted != 0 )); then
    echo "::error::The $kind simulator failed to boot, twice. No test ran: this is the Mac or the simulator, not a test. Run the job again."
    exit 1
  fi
  echo "The $kind simulator booted on the second try"
fi
porchlight_stage "ready for installs" "$ready_limit" ready_for_installs "$udid" || stalled "ready for installs" "$ready_limit"
echo "Booted $kind $udid and ready for installs in $(( SECONDS - started ))s"
