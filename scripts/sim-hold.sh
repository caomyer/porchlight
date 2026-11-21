#!/bin/zsh
# Holds this checkout's test simulators while you drive them by hand, so a test run from
# this checkout waits for you instead of shutting them down, and other runs see a test
# slot taken (scripts/lib/simulators.sh).
#
#   scripts/sim-hold.sh ipad            hold this checkout's iPad simulator, and boot it
#   scripts/sim-hold.sh iphone          the iPhone
#   scripts/sim-hold.sh ipad iphone     both, when the Mac has two test slots free
#   scripts/sim-hold.sh --runtime com.apple.CoreSimulator.SimRuntime.iOS-27-2 iphone
#
# It prints each simulator's id and then waits; Ctrl-C (or ending the process) lets go.
# The simulators stay booted afterwards: shut them down yourself when you are done
# (xcrun simctl shutdown <id>), or the next test run from this checkout does.
#
# Another checkout's run never shuts your simulators down, held or not; it waits for a
# test slot. Holding is what keeps your own checkout's runs off them, and what tells
# everyone who is using the slot.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
source scripts/lib/simulators.sh

kinds=()
while (( $# )); do
  case "$1" in
    --runtime) shift; porchlight_sim_runtime="$1" ;;
    ipad|iphone) kinds+=("$1") ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1 (ipad, iphone or --runtime <id>)" >&2; exit 1 ;;
  esac
  shift
done
(( ${#kinds} )) || { echo "Which simulator: ipad, iphone or both" >&2; exit 1; }

held=()
for kind in $kinds; do
  udid=$(porchlight_simulator "$kind")
  porchlight_hold_simulator "$udid"
  held+=("$kind $udid")
done
porchlight_take_slots ${#kinds}
(( porchlight_slots >= ${#kinds} )) || echo "Only $porchlight_slots test slot was free for ${#kinds} simulators: the Mac may swap with both booted" >&2
for entry in $held; do
  porchlight_boot_simulator "${entry#* }"
  echo "Holding the ${entry% *} simulator ${entry#* }"
done
echo "Held until this ends (Ctrl-C)."
while true; do sleep 3600; done
