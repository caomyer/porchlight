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
# A newer Xcode may not have these models: PORCHLIGHT_SIM_IPAD_TYPE and
# PORCHLIGHT_SIM_IPHONE_TYPE name another of the same size (.github/workflows/tests.yml).
typeset -gA porchlight_sim_types=(
  ipad "${PORCHLIGHT_SIM_IPAD_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB}"
  iphone "${PORCHLIGHT_SIM_IPHONE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-15}"
)
porchlight_sim_locks=/private/tmp/porchlight-simulator-locks
# The simulators this shell holds.
typeset -ga porchlight_held_simulators=()

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
  porchlight_held_simulators+=("$udid")
}

# The booted simulators, one "udid name" per line.
porchlight_booted_simulators() {
  xcrun simctl list devices booted -j | python3 -c '
import json, sys
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device["state"] == "Booted":
            print(device["udid"], device["name"])
'
}

# Whether a run holds `udid`: some other process has its lock. Never ask about a simulator
# this shell holds itself: fcntl locks belong to the process, so asking would succeed, and
# letting go again would drop the hold.
porchlight_is_held() {
  local file="$porchlight_sim_locks/$1.lock" fd
  mkdir -p "$porchlight_sim_locks"
  touch "$file"
  if zsystem flock -t 0 -f fd "$file" 2>/dev/null; then
    zsystem flock -u "$fd"
    return 1
  fi
  return 0
}

# This checkout's name in its simulators' names: "Porchlight <checkout> ipad".
porchlight_own_prefix() {
  print -r -- "Porchlight $(basename "$PWD") "
}

# Shuts down this checkout's own booted simulators that no run holds: ones a run of this
# checkout left behind when it was killed outright. Only its own, ever: another checkout's
# simulator with no run holding it may be one a person or an agent is driving by hand, and
# "no lock" is not evidence that it was abandoned. (A run of November 21, 2026 shut down
# another agent's two simulators in the middle of its work that way.) To drive this
# checkout's own simulator by hand while its tests may run, hold it: scripts/sim-hold.sh.
porchlight_shut_down_own_unheld() {
  local udid name own
  own=$(porchlight_own_prefix)
  porchlight_booted_simulators | while read -r udid name; do
    [[ "$name" == "$own"* ]] || continue
    (( ${porchlight_held_simulators[(Ie)$udid]} )) && continue
    porchlight_is_held "$udid" && continue
    echo "Shutting down $name: this checkout's own, booted, and no run holds it" >&2
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  done
}

# The booted simulators that take a test slot without a run holding one for them, one name
# per line: any simulator that isn't a test simulator (opened by hand, another project's),
# and another checkout's test simulator that no run holds (driven by hand, or left behind).
# A simulator a run holds is not listed: its run holds a slot lock for it. Nor are this
# shell's own.
porchlight_slots_taken_outside_runs() {
  local udid name own
  own=$(porchlight_own_prefix)
  porchlight_booted_simulators | while read -r udid name; do
    (( ${porchlight_held_simulators[(Ie)$udid]} )) && continue
    if [[ "$name" == "Porchlight "* ]]; then
      [[ "$name" == "$own"* ]] && continue
      porchlight_is_held "$udid" && continue
    fi
    print -r -- "$name"
  done
}

# Takes up to `want` of the Mac's free test slots for this shell until it exits, waiting
# only while none is free, and sets `porchlight_slots` to how many it took. A booted
# simulator under test needs 1.5 to 3 GB; with more of them than the Mac has memory for,
# everything swaps and UI tests time out. So a run boots simulators only into slots: one
# for each 8 GB of memory, or PORCHLIGHT_TEST_SLOTS. Never waiting for a second slot while
# holding a first means two runs can't each hold one and wait for the other.
# This checkout's own simulators that no run holds are shut down first. Every other booted
# simulator that no run holds takes a slot of its own, whoever booted it: the run waits for
# it and says which it is waiting for, and never shuts it down. A run also takes a second
# slot only when the memory free right now has room for a second simulator (4 GB each, with its app and test runner):
# the Mac's other apps can leave too little for two, and two then swap each other into
# timeouts, as two UI suites did on a 16 GB Mac with a browser and chat apps open.
porchlight_take_slots() {
  local want=$1 total slots others slot fd waited=0 room outside
  total=${PORCHLIGHT_TEST_SLOTS:-$(( $(sysctl -n hw.memsize) / (8 * 1024 * 1024 * 1024) ))}
  (( total >= 1 )) || total=1
  if (( want > 1 )) && [[ -z "${PORCHLIGHT_TEST_SLOTS:-}" ]]; then
    room=$(( $(porchlight_free_gb) / 4 ))
    if (( room < want )); then
      want=$(( room > 1 ? room : 1 ))
      (( want > 1 )) || echo "Only $(porchlight_free_gb) GB of memory is free: the iPad and the iPhone run one after the other" >&2
    fi
  fi
  typeset -g porchlight_slots=0
  mkdir -p "$porchlight_sim_locks"
  while (( porchlight_slots == 0 )); do
    porchlight_shut_down_own_unheld
    outside=$(porchlight_slots_taken_outside_runs)
    others=$(print -r -- "$outside" | grep -c . || true)
    slots=$(( total - others ))
    if (( slots < 1 )); then
      (( waited )) || echo "Every test slot is taken by simulators no test run holds, so this run waits for them: ${outside//$'\n'/; }. One driven by hand goes when its owner shuts it down; scripts/sim-clear.sh lists them and shuts down abandoned ones." >&2
      waited=1
      sleep 5
      continue
    fi
    for slot in {1..$slots}; do
      (( porchlight_slots < want )) || break
      touch "$porchlight_sim_locks/slot-$slot.lock"
      if zsystem flock -t 0 -f fd "$porchlight_sim_locks/slot-$slot.lock" 2>/dev/null; then
        print -r -- "$$ $(ps -o command= -p $$)" >| "$porchlight_sim_locks/slot-$slot.lock.holder"
        (( ++porchlight_slots ))
      fi
    done
    if (( porchlight_slots == 0 )); then
      (( waited )) || echo "Waiting for a free test slot ($slots of $total free of other simulators), held by: $(cat "$porchlight_sim_locks"/slot-*.lock.holder 2>/dev/null | cut -c1-100 | tr '\n' ';')" >&2
      waited=1
      sleep 5
    fi
  done
}

# Memory free now, or free to take without swapping (inactive, speculative and purgeable
# pages), in whole GB.
porchlight_free_gb() {
  vm_stat | python3 -c '
import re, sys
text = sys.stdin.read()
page = int(re.search(r"page size of (\d+)", text).group(1))
pages = sum(int(re.search(name + r":\s+(\d+)", text).group(1)) for name in ("Pages free", "Pages inactive", "Pages speculative", "Pages purgeable"))
print(pages * page // 2**30)
'
}

# Boots `udid` if it isn't booted, and waits until it is ready.
porchlight_boot_simulator() {
  xcrun simctl boot "$1" 2>/dev/null || true
  xcrun simctl bootstatus "$1" -b >/dev/null
}
