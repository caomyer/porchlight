# Whether a UI test run ended before any test started, from xcodebuild's log: the test
# runner never came up, so nothing was tested and the run can be made again without hiding
# anything. Strict on purpose: the log must say the runner failed to start, and must not
# hold a single "Test Case ... started" line. A runner that crashes in the middle of a suite
# has started tests, is a real failure, and is never retried by this rule.
#
#   porchlight_runner_never_started <log>
#
# Source it with zsh. scripts/ci/check-runner-start.sh checks it against sample logs.
porchlight_runner_never_started() {
  local log=$1
  [[ -f "$log" ]] || return 1
  grep -qE "The test runner crashed while preparing to run tests|failed to initialize for UI testing|crashed before establishing connection" "$log" || return 1
  ! grep -qE "^Test Case '.*' started" "$log"
}
