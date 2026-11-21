# Runs one stage of a longer job with a time limit of its own, so a stage that stalls says
# which it was and how long it was given, and fails, well before whatever limit sits
# around the whole job cancels it without a word.
#
#   porchlight_stage "<name>" <seconds> <command> [arguments...]
#
# Returns the command's own status, or 124 when it was still running at the limit (it is
# ended first). Source it with zsh. scripts/ci/check-boot-simulator.sh checks it.
porchlight_stage() {
  local name=$1 limit=$2
  shift 2
  local start=$SECONDS pid stage_status
  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if (( SECONDS - start >= limit )); then
      kill "$pid" 2>/dev/null
      sleep 1
      kill -9 "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      echo "Stalled: \"$name\" had not finished after ${limit}s"
      return 124
    fi
    sleep 1
  done
  wait "$pid"
  stage_status=$?
  echo "Done: \"$name\" in $(( SECONDS - start ))s"
  return $stage_status
}
