#!/bin/zsh
# Checks the rules of scripts/lib/simulators.sh without a simulator: which booted
# simulators a run may shut down (only its own checkout's, and only when no run holds
# them), which ones take a test slot, and that a run waits for a slot other people's
# simulators hold instead of taking it from them. `simctl` and the list of booted
# simulators are stand-ins, so this runs anywhere in a second.
#
#   zsh scripts/ci/check-simulator-rules.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/simulators.sh

porchlight_sim_locks=$(mktemp -d)
trap 'rm -rf "$porchlight_sim_locks"' EXIT

# Stand-ins. `booted` is what is booted, "udid name" a line; `held` the udids a run holds.
booted=()
held=()
shut=()
porchlight_booted_simulators() { (( ${#booted} )) && print -l -- $booted; return 0 }
porchlight_is_held() { (( ${held[(Ie)$1]} )) }
porchlight_own_prefix() { print -r -- "Porchlight mine " }
porchlight_free_gb() { print 16 }
xcrun() {
  if [[ "$1 $2" == "simctl shutdown" ]]; then
    print -r -- "$3" >> "$porchlight_sim_locks/shut"
    return 0
  fi
  echo "unexpected: xcrun $*" >&2
  return 1
}
shut_down() { [[ -f "$porchlight_sim_locks/shut" ]] && tr '\n' ' ' < "$porchlight_sim_locks/shut" | sed 's/ $//' || true }

failures=0
expect() {
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
  else
    echo "FAILED: $1"
    echo "  expected: $3"
    echo "  got:      $2"
    failures=$(( failures + 1 ))
  fi
}

# 1. Only this checkout's own simulators, and only those no run holds, are shut down.
booted=(
  "A1 Porchlight mine ipad"
  "A2 Porchlight mine iphone"
  "B1 Porchlight agent-other iphone"
  "B2 Porchlight agent-other ipad"
  "C1 iPhone 16 Pro"
)
held=(A2 B2)   # a run of this checkout holds A2; a run of the other holds B2
porchlight_shut_down_own_unheld 2>/dev/null
expect "a run shuts down only its own checkout's simulator that no run holds" "$(shut_down)" "A1"

# 2. Another checkout's simulator that no run holds takes a slot, as does one booted outside
#    the tests; one a run holds does not (its run holds a slot lock), nor does this run's own.
expect "simulators that take a slot without a run" \
  "$(porchlight_slots_taken_outside_runs | tr '\n' ';')" "Porchlight agent-other iphone;iPhone 16 Pro;"

# 3. With every slot taken by other people's simulators, the run waits and says for whom,
#    shuts none of them down, and takes the slot once its owner has shut one down.
rm -f "$porchlight_sim_locks/shut"
booted=("B1 Porchlight agent-other iphone" "C1 iPhone 16 Pro")
held=()
waits=0
sleep() {
  waits=$(( waits + 1 ))
  # The other agent finishes and shuts its simulator down itself.
  (( waits >= 2 )) && booted=("C1 iPhone 16 Pro")
  return 0
}
PORCHLIGHT_TEST_SLOTS=2
message=$(porchlight_take_slots 1 2>&1 >/dev/null; print -r -- "waits=$waits")
porchlight_take_slots 1 2>/dev/null
expect "the run waited while both slots were other people's" "$(( waits >= 2 ))" "1"
expect "and took a slot when one came free" "$porchlight_slots" "1"
expect "and shut down nobody's simulator" "$(shut_down)" ""
case "$message" in
  *"Porchlight agent-other iphone"*"iPhone 16 Pro"*"sim-clear.sh"*) echo "ok: the wait names who holds the slots and how to clear abandoned ones" ;;
  *) echo "FAILED: the wait's message: $message"; failures=$(( failures + 1 )) ;;
esac

# 4. The hosted Macs: one slot, this checkout's simulator booted beforehand and held by the
#    run itself, nothing else booted. The run takes its slot at once and shuts nothing down.
rm -f "$porchlight_sim_locks/shut"
unfunction sleep
booted=("A1 Porchlight mine ipad")
held=()
porchlight_held_simulators=(A1)
PORCHLIGHT_TEST_SLOTS=1
porchlight_slots=0
rm -f "$porchlight_sim_locks"/slot-*.lock*
( porchlight_take_slots 1 2>/dev/null; print -r -- "$porchlight_slots" > "$porchlight_sim_locks/ci" )
expect "a hosted Mac's run takes its one slot" "$(cat "$porchlight_sim_locks/ci")" "1"
expect "and leaves its own held simulator booted" "$(shut_down)" ""

(( failures == 0 )) || { echo "$failures of the simulator rules failed"; exit 1; }
echo "The simulator rules hold."
