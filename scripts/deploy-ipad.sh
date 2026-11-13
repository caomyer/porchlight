#!/bin/zsh
# Builds Porchlight and installs it on the wall iPad.
#
# Run it once by hand for the first install. With a free Apple ID the install
# expires after 7 days, so the Mac mini runs this weekly to keep it alive.
#
# Needs: Xcode, `brew install xcodegen`, Config/Local.xcconfig with your
# DEVELOPMENT_TEAM, and the iPad paired with this Mac (USB once, then Wi-Fi).
#
# The wall gets a Release build: it runs all day, and optimised code costs less CPU and
# power per frame. --debug installs a Debug build instead, for the tools that need the
# Debug-only launch arguments (device-tour.sh, idle-cpu.sh); run it again without
# --debug afterwards.
#
#   scripts/deploy-ipad.sh [--debug]
#
# Optional: PORCHLIGHT_DEVICE=<device identifier from `xcrun devicectl list devices`>
set -euo pipefail

configuration=Release
[[ "${1:-}" == "--debug" ]] && configuration=Debug

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

device="${PORCHLIGHT_DEVICE:-}"
if [[ -z "$device" ]]; then
  json="$(mktemp)"
  xcrun devicectl list devices --json-output "$json" >/dev/null
  device="$(/usr/bin/python3 -c '
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
ipads = [d for d in devices if d.get("hardwareProperties", {}).get("deviceType") == "iPad"]
print(ipads[0]["identifier"] if ipads else "")
' "$json")"
  rm -f "$json"
fi
if [[ -z "$device" ]]; then
  echo "No iPad found. Connect it with a cable, unlock it and tap Trust." >&2
  exit 1
fi

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
xcrun devicectl device install app --device "$device" "$app"
xcrun devicectl device process launch --device "$device" com.mingyucao.porchlight || true
echo "Installed a $configuration build of Porchlight on $device"
