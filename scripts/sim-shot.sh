#!/bin/zsh
# Builds Porchlight, launches it in an iPad simulator and saves a landscape screenshot.
#
#   scripts/sim-shot.sh <simulator-udid> <out.png> [launch arguments...]
#
# Debug launch arguments: -sampleHousehold, -resetData, -startScreen <today|calendar|food|chores|lists|settings|companion-<n>> (n-th companion on the rail)
# Env: DERIVED (DerivedData folder name, default Porchlight-main). Builds always go to
# ~/Library/Developer/Xcode/DerivedData because this repo may live in iCloud Documents.
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "${0:A:h:h}"
udid=$1; out=$2; shift 2
derived="$HOME/Library/Developer/Xcode/DerivedData/${DERIVED:-Porchlight-main}"
xcodegen generate --quiet
if ! xcodebuild build -project Porchlight.xcodeproj -scheme Porchlight -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO -skipMacroValidation > "$derived.build.log" 2>&1; then
  grep -E "error:" "$derived.build.log" | head -20
  exit 1
fi
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl install "$udid" "$derived/Build/Products/Debug-iphonesimulator/Porchlight.app"
xcrun simctl terminate "$udid" com.porchlight.porchlight 2>/dev/null || true
xcrun simctl launch "$udid" com.porchlight.porchlight "$@" > /dev/null
/usr/bin/python3 -c "import time; time.sleep(${WAIT:-4})"
timeout 30 xcrun simctl io "$udid" screenshot "$out" > /dev/null 2>&1
# Older simulators save the portrait framebuffer; newer ones save the screen as shown.
# The app is landscape, so turn a portrait shot.
size=($(sips -g pixelWidth -g pixelHeight "$out" | awk '/pixel/ {print $2}'))
if (( size[2] > size[1] )); then
  sips -r 270 "$out" > /dev/null
fi
echo "$out"
