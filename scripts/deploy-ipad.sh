#!/bin/zsh
# Builds Porchlight and installs it on the wall iPad.
#
# Run it by hand, or let scripts/schedule-deploy.sh run it twice a week to keep
# the wall on the latest commit.
#
# Needs: Xcode, `brew install xcodegen`, Config/Local.xcconfig with your
# DEVELOPMENT_TEAM, and the iPad paired with this Mac (USB once, then Wi-Fi).
#
# The wall gets a Release build: it runs all day, and optimised code costs less CPU and
# power per frame. --debug installs a Debug build instead, for the tools that need the
# Debug-only launch arguments (device-tour.sh, idle-cpu.sh); run it again without
# --debug afterwards.
#
# The wall's data is copied to this Mac first (scripts/backup-ipad.sh), and the
# install does not go ahead if that copy fails. --no-backup skips it, for the
# very first install, when the app has no data yet. --no-launch installs without
# opening the app, so a backup can be restored into it first.
#
#   scripts/deploy-ipad.sh [--debug] [--no-backup] [--no-launch]
#
# Optional: PORCHLIGHT_DEVICE=<device identifier from `xcrun devicectl list devices`>
set -euo pipefail

configuration=Release
backup=1
launch=1
for argument in "$@"; do
  case "$argument" in
    --debug) configuration=Debug ;;
    --no-backup) backup=0 ;;
    --no-launch) launch=0 ;;
    *) echo "Unknown option: $argument" >&2; exit 1 ;;
  esac
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
root="${0:A:h:h}"
cd "$root"
# Build outside the repo: this folder may live in iCloud-synced Documents, and
# iCloud's extended attributes make code signing fail.
derived="$HOME/Library/Developer/Xcode/DerivedData/Porchlight-deploy"

if [[ ! -f Config/Local.xcconfig ]]; then
  echo "Missing Config/Local.xcconfig. Copy Config/Local.example.xcconfig and set DEVELOPMENT_TEAM." >&2
  exit 1
fi

source "$root/scripts/lib/device.sh"
device="$(porchlight_device)"

xcodegen generate --quiet
xcodebuild build \
  -project Porchlight.xcodeproj \
  -scheme Porchlight \
  -configuration "$configuration" \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$derived" \
  -allowProvisioningUpdates \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

app="$derived/Build/Products/$configuration-iphoneos/Porchlight.app"
if (( backup )); then
  "$root/scripts/backup-ipad.sh"
fi
porchlight_devicectl device install app --device "$device" "$app"
if (( launch )); then
  # Opening the app fails while the iPad is locked; the install itself is done.
  xcrun devicectl device process launch --device "$device" com.porchlight.porchlight || true
fi
echo "Installed a $configuration build of Porchlight on $device"
