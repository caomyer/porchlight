#!/bin/zsh
# Gathers a CI job's test logs into ./results, and, unless the job succeeded (its status is
# the first argument), each result bundle zipped, with the screenshots and the failures.
#
# In a job that succeeded, one kind of result bundle is kept all the same: that of a suite
# in which a test ran past the ceiling or waited on an app that would not go idle
# (scripts/lib/slow_tests.py leaves `<suite>.keep` beside its log). The bundle has the
# app's own log for that launch, which is what explains it; with it go the simulator's logs
# of the app for those tests, which scripts/test.sh wrote beside the suite's.
set -uo pipefail

mkdir -p results
for log in "${TMPDIR:-/tmp}"/porchlight-tests-*/*.log(N) "${TMPDIR:-/tmp}"/porchlight-tests-*/*-simulator.log.gz(N); do cp "$log" results/; done
for bundle in "${TMPDIR:-/tmp}"/porchlight-tests-*/*.xcresult(N); do
  if [[ "$1" != success || -s "${bundle%.xcresult}.keep" ]]; then
    ditto -c -k --keepParent "$bundle" "results/${bundle:t}.zip"
  fi
done
ls -l results
