#!/bin/zsh
# Boots this checkout's simulator of a kind (ipad or iphone) on $RUNTIME, the one
# scripts/test.sh then picks up already booted, so the log shows the boot's time apart.
#
# A brand-new iOS 27 simulator keeps setting itself up for minutes after it says it has
# booted, and the first thing asked of it (installing, or uninstalling an app) waits for
# that; asking here keeps that wait out of the tests' time too.
#
# Each stage has a time limit of its own (scripts/lib/stage.sh). A stage that stalls is
# named in the log; the simulator is then shut down, erased and booted once more, and a
# second stall fails the job saying which stage it was. Before this, a boot that stalled
# sat until GitHub cancelled the job with "The operation was canceled" and nothing else
# (three times by November 21, 2026; docs/design/testing.md, "Infrastructure failures").
#
#   PORCHLIGHT_BOOT_SECONDS    the limit for booting (default 540: a new iOS 27 simulator
#                              has taken up to eight minutes)
#   PORCHLIGHT_READY_SECONDS   the limit for the first uninstall to answer (default 150)
set -uo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/simulators.sh
source scripts/lib/stage.sh
porchlight_sim_runtime=$RUNTIME

boot_limit=${PORCHLIGHT_BOOT_SECONDS:-540}
ready_limit=${PORCHLIGHT_READY_SECONDS:-150}
kind=$1

udid=$(porchlight_simulator "$kind") || exit 1

# The first uninstall on a new simulator waits for it to finish setting itself up; there
# being no such app to uninstall is its usual answer, and fine.
ready_for_installs() {
  xcrun simctl uninstall "$1" com.porchlight.porchlight 2>/dev/null
  return 0
}

# Boots and waits until installs are answered. Prints the stage that stalled, if one did.
boot_once() {
  porchlight_stage "boot the $kind" "$boot_limit" porchlight_boot_simulator "$udid" || { stalled="boot the $kind"; return 1 }
  porchlight_stage "ready for installs" "$ready_limit" ready_for_installs "$udid" || { stalled="ready for installs"; return 1 }
}

started=$SECONDS
stalled=""
if ! boot_once; then
  first=$stalled
  echo "::warning::The $kind simulator stalled at \"$first\". Shutting it down, erasing it and booting it once more."
  xcrun simctl shutdown "$udid" >/dev/null 2>&1
  porchlight_stage "erase the $kind" 120 xcrun simctl erase "$udid" || true
  stalled=""
  if ! boot_once; then
    echo "::error::The $kind simulator stalled twice, first at \"$first\" and then at \"$stalled\". No test ran: this is the Mac or the simulator, not a test. Run the job again."
    exit 1
  fi
  echo "The $kind simulator booted on the second try, after stalling at \"$first\""
fi
echo "Booted $kind $udid and ready for installs in $(( SECONDS - started ))s"
