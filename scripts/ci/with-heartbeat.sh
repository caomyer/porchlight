#!/bin/zsh
# Runs the command given, and every two minutes says the time and how much memory is free,
# so a job that hangs, or a Mac that runs out of memory, shows in the log.
heartbeat() {
  while sleep 120; do
    echo "[heartbeat] $(date -u +%H:%M:%S) $(memory_pressure 2>/dev/null | tail -1), swap: $(sysctl -n vm.swapusage | sed 's/.*used = \([^ ]*\).*/\1/') used"
  done
}
heartbeat &
beat=$!
# The loop and the sleep it is in the middle of: a sleep left behind keeps the step's output
# open after the command has ended, and GitHub then ends it as an orphan.
trap 'pkill -P $beat 2>/dev/null; kill $beat 2>/dev/null' EXIT
"$@"
