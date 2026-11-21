#!/bin/zsh
# A test job's two preparations at once: boots its simulator (scripts/ci/boot-simulator.sh)
# while the build is fetched, checked and unpacked (scripts/ci/unpack-build.sh). Booting a
# new simulator takes three to seven minutes and fetching the build up to one and a half,
# so doing the second during the first saves the second.
#
#   zsh scripts/ci/boot-and-fetch.sh <ipad|iphone> <sha256> <bytes>
#
# Each keeps its own words when it fails, so a download that could not be put right still
# reads "The build's download was corrupted", never as a boot that failed, and a boot that
# stalled twice still names its stage. The fetch's output is printed after the boot's, under
# its own heading.
set -uo pipefail
here="${0:A:h}"
log=$(mktemp)

zsh "$here/unpack-build.sh" "$2" "$3" > "$log" 2>&1 &
fetching=$!
zsh "$here/boot-simulator.sh" "$1"
booted=$?
wait "$fetching"
fetched=$?

echo "The build, fetched while the simulator booted:"
cat "$log"
rm -f "$log"
(( fetched == 0 )) || echo "The build was not fetched: see \"The build's download was corrupted\" above. The simulator's boot is not what failed."
(( booted == 0 )) || echo "The simulator did not boot: see the stage named above. The build's download is not what failed."
(( booted == 0 && fetched == 0 ))
