#!/bin/zsh
# Lists the booted test simulators ("Porchlight <checkout> ipad|iphone") that no test run
# and no scripts/sim-hold.sh holds, from every checkout, and shuts them down when asked.
#
#   scripts/sim-clear.sh         list them, and change nothing
#   scripts/sim-clear.sh --yes   shut them down
#
# A test run never does this to another checkout's simulators by itself: one with no
# holder may be abandoned (its run was killed) or may be someone driving it by hand, and
# only a person, or an agent that has asked, can tell which. Run it when a test run says
# it is waiting for simulators no run holds and you know they are nobody's.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
source scripts/lib/simulators.sh

yes=0
case "${1:-}" in
  --yes) yes=1 ;;
  "") ;;
  -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "Unknown argument: $1 (--yes to shut them down)" >&2; exit 1 ;;
esac

porchlight_booted_simulators | while read -r udid name; do
  [[ "$name" == "Porchlight "* ]] || continue
  if porchlight_is_held "$udid"; then
    echo "Held, left alone: $name ($(cat "$porchlight_sim_locks/$udid.lock.holder" 2>/dev/null | cut -c1-80))"
    continue
  fi
  if (( yes )); then
    echo "Shutting down $name ($udid)"
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  else
    echo "Not held by any run: $name ($udid)"
  fi
done
(( yes )) || echo "Nothing was changed. scripts/sim-clear.sh --yes shuts down the ones not held."
