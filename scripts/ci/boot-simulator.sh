#!/bin/zsh
# Boots this checkout's simulator of a kind (ipad or iphone) on $RUNTIME, the one
# scripts/test.sh then picks up already booted, so the log shows the boot's time apart.
#
# A brand-new iOS 27 simulator keeps setting itself up for minutes after it says it has
# booted, and the first thing asked of it (installing, or uninstalling an app) waits for
# that; asking here keeps that wait out of the tests' time too.
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/simulators.sh
porchlight_sim_runtime=$RUNTIME

step=$SECONDS
udid=$(porchlight_simulator "$1")
porchlight_boot_simulator "$udid"
echo "Booted $1 $udid in $(( SECONDS - step ))s"
step=$SECONDS
xcrun simctl uninstall "$udid" com.porchlight.porchlight 2>/dev/null || true
echo "Ready for installs in $(( SECONDS - step ))s more"
