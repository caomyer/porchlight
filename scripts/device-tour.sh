#!/bin/zsh
# Captures every wall screen on the real iPad with sample data, then copies the
# PNGs to an output folder. Sample launches use a separate storage sandbox, so the
# household's real data and photos are never touched. Run scripts/deploy-ipad.sh first.
#
#   scripts/device-tour.sh [out-dir]
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
out="${1:-/tmp/porchlight-device-tour}"
app=com.mingyucao.porchlight
device="${PORCHLIGHT_DEVICE:-}"
if [[ -z "$device" ]]; then
  json="$(mktemp)"
  xcrun devicectl list devices --json-output "$json" >/dev/null
  device="$(/usr/bin/python3 -c '
import json, sys
ds = json.load(open(sys.argv[1]))["result"]["devices"]
print(next((d["identifier"] for d in ds if d.get("hardwareProperties", {}).get("deviceType") == "iPad"), ""))
' "$json")"
  rm -f "$json"
fi
[[ -n "$device" ]] || { echo "No iPad found." >&2; exit 1; }

shots=(
  "01-today|-startScreen today"
  "02-calendar-week|-startScreen calendar"
  "03-calendar-month|-startScreen calendar -calendarMode month"
  "04-companion|-startScreen companion-1"
  "05-log-walk|-startScreen today -debugCompanionSheet log"
  "06-food-week|-startScreen food"
  "07-food-month|-startScreen food -debugFoodView month"
  "08-write-day|-startScreen food -debugFoodView write"
  "09-chores|-startScreen chores"
  "10-lists|-startScreen lists"
  "11-ambient|-startScreen photos -ambient.nightEnabled NO"
  "12-settings|-startScreen settings"
  "13-onboarding-companions|-onboardingStep companions"
)
for entry in "${shots[@]}"; do
  name="${entry%%|*}"; args=(${=entry#*|})
  echo "capturing $name"
  xcrun devicectl device process launch --device "$device" --terminate-existing "$app" -- \
    -sampleHousehold -debugSnapshot "$name" -debugSnapshotDelay 25 "${args[@]}" >/dev/null
  /usr/bin/python3 -c "import time; time.sleep(45)"
done

rm -rf "$out"; mkdir -p "$out"
xcrun devicectl device copy from --device "$device" --domain-type appDataContainer --domain-identifier "$app" \
  --source "Library/Application Support/PorchlightSample/Snapshots" --destination "$out" >/dev/null
# Leave the wall on the household's real data.
xcrun devicectl device process launch --device "$device" --terminate-existing "$app" >/dev/null
ls "$out"
