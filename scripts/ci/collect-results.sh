#!/bin/zsh
# Gathers a CI job's test logs into ./results, and, unless the job succeeded (its status is
# the first argument), each result bundle zipped, with the screenshots and the failures.
set -uo pipefail

mkdir -p results
for log in "${TMPDIR:-/tmp}"/porchlight-tests-*/*.log(N); do cp "$log" results/; done
if [[ "$1" != success ]]; then
  for bundle in "${TMPDIR:-/tmp}"/porchlight-tests-*/*.xcresult(N); do
    ditto -c -k --keepParent "$bundle" "results/${bundle:t}.zip"
  done
fi
ls -l results
