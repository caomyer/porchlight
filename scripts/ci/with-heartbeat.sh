#!/bin/zsh
# Runs the command given, and every two minutes says the time and how much memory is free,
# so a job that hangs, or a Mac that runs out of memory, shows in the log.
#
#   PORCHLIGHT_HEARTBEAT_SECONDS   how often (default 120)
#   PORCHLIGHT_HEARTBEAT_TOP       set to 1 to add the load and the five processes holding
#                                  the most memory, for a measurement
#
# The time in the line is taken before the memory is read: on a Mac that is swapping, the
# reading itself has taken minutes, and the line then reaches the log long after its time.
heartbeat() {
  local line
  while sleep "${PORCHLIGHT_HEARTBEAT_SECONDS:-120}"; do
    line="[heartbeat] $(date -u +%H:%M:%S) $(memory_pressure 2>/dev/null | tail -1), swap: $(sysctl -n vm.swapusage | sed 's/.*used = \([^ ]*\).*/\1/') used"
    if [[ "${PORCHLIGHT_HEARTBEAT_TOP:-}" == 1 ]]; then
      line+=", load: $(sysctl -n vm.loadavg | awk '{print $2}'), most memory: $(ps -axo rss=,comm= | sort -rn | head -5 | awk '{rss=$1; sub(/^ *[0-9]+ +/, ""); n=split($0,p,"/"); printf "%s %dM; ", p[n], rss/1024}')"
    fi
    echo "$line"
  done
}
heartbeat &
beat=$!
# The loop and the sleep it is in the middle of: a sleep left behind keeps the step's output
# open after the command has ended, and GitHub then ends it as an orphan.
trap 'pkill -P $beat 2>/dev/null; kill $beat 2>/dev/null' EXIT
"$@"
