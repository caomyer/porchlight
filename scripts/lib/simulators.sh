# Simulators for test runs: each checkout gets its own, and a run holds the ones it uses.
#
# Two agents (or a person and an agent) testing from different worktrees used to share
# one iPad and one iPhone simulator behind a lock folder in /private/tmp. A run that was
# killed left the folder behind, and every other run waited on it for hours.
# Now each checkout creates its own simulators, so runs from different checkouts never
# wait on each other, and a run holds a simulator with a kernel file lock, which the
# system lets go the moment the process holding it ends, however it ends.
#
# Source it with zsh from the repository root.

zmodload zsh/system

# The wall iPad and the oldest phones run iOS 17, so tests run on iOS 17.5.
porchlight_sim_runtime=com.apple.CoreSimulator.SimRuntime.iOS-17-5
typeset -gA porchlight_sim_types=(
  ipad com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB
  iphone com.apple.CoreSimulator.SimDeviceType.iPhone-15
)
porchlight_sim_locks=/private/tmp/porchlight-simulator-locks

# This checkout's simulator of a kind (ipad or iphone), made the first time it is asked
# for. Prints its udid.
porchlight_simulator() {
  local kind=$1
  local name="Porchlight $(basename "$PWD") $kind"
  local udid
  udid=$(xcrun simctl list devices -j | python3 -c '
import json, sys
name, runtime = sys.argv[1], sys.argv[2]
for device in json.load(sys.stdin)["devices"].get(runtime, []):
    if device["name"] == name and device["isAvailable"]:
        print(device["udid"])
        break
' "$name" "$porchlight_sim_runtime")
  if [[ -z "$udid" ]]; then
    udid=$(xcrun simctl create "$name" "${porchlight_sim_types[$kind]}" "$porchlight_sim_runtime") || {
      echo "Could not create the $kind simulator. Install iOS 17.5: xcodebuild -downloadPlatform iOS -buildVersion 17.5" >&2
      return 1
    }
  fi
  print -r -- "$udid"
}

# Holds `udid` for this shell until it exits, waiting while another run holds it.
# Who holds it is written beside the lock, never into it: the lock is an fcntl lock, and
# the shell closing any file it opened on the lock file would let it go.
porchlight_hold_simulator() {
  local udid=$1 file="$porchlight_sim_locks/$1.lock" fd
  mkdir -p "$porchlight_sim_locks"
  touch "$file"
  if ! zsystem flock -t 0 -f fd "$file" 2>/dev/null; then
    echo "Waiting for $udid, held by: $(cat "$file.holder" 2>/dev/null)" >&2
    zsystem flock -f fd "$file" || return 1
  fi
  print -r -- "$$ $(ps -o command= -p $$)" >| "$file.holder"
}

# Takes `count` of the Mac's test slots for this shell until it exits, waiting while they
# are taken. A booted simulator under test needs 1.5 to 3 GB; with more of them than the
# Mac has memory for, everything swaps and UI tests time out. So a run boots simulators
# only into slots: one for each 8 GB of memory, or PORCHLIGHT_TEST_SLOTS.
porchlight_take_slots() {
  local count=$1 total slot fd waited=0
  local -a held
  total=${PORCHLIGHT_TEST_SLOTS:-$(( $(sysctl -n hw.memsize) / (8 * 1024 * 1024 * 1024) ))}
  (( total >= 1 )) || total=1
  (( count <= total )) || count=$total
  mkdir -p "$porchlight_sim_locks"
  while (( ${#held} < count )); do
    for slot in {1..$total}; do
      # fcntl locks belong to the process, so asking again for one it holds would succeed.
      (( ${held[(Ie)$slot]} )) && continue
      touch "$porchlight_sim_locks/slot-$slot.lock"
      if zsystem flock -t 0 -f fd "$porchlight_sim_locks/slot-$slot.lock" 2>/dev/null; then
        print -r -- "$$ $(ps -o command= -p $$)" >| "$porchlight_sim_locks/slot-$slot.lock.holder"
        held+=($slot)
        (( ${#held} < count )) || break
      fi
    done
    if (( ${#held} < count )); then
      (( waited )) || echo "Waiting for a free test slot ($total on this Mac): $(cat "$porchlight_sim_locks"/slot-*.lock.holder 2>/dev/null | cut -c1-120 | tr '\n' ';')" >&2
      waited=1
      sleep 5
    fi
  done
}

# Boots `udid` if it isn't booted, and waits until it is ready.
porchlight_boot_simulator() {
  xcrun simctl boot "$1" 2>/dev/null || true
  xcrun simctl bootstatus "$1" -b >/dev/null
}
