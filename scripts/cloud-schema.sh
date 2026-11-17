#!/bin/zsh
# Teaches CloudKit the app's schema and keeps a reviewed copy of it in the repo
# (docs/design/sync-icloud.md, "Deploying the CloudKit schema").
#
#   scripts/cloud-schema.sh seed [--simulator UDID]   write one record of every type to Development
#   scripts/cloud-schema.sh uninstall-seed            remove the seeding app from the iPhone
#   scripts/cloud-schema.sh export                    Development's schema -> Config/cloudkit-schema.ckdb
#   scripts/cloud-schema.sh diff                      the checked-in schema against Development
#   scripts/cloud-schema.sh check                     the checked-in schema against Production
#
# seed builds a Debug build as its own app, "Porchlight Seed" (bundle id
# com.mingyucao.porchlight.schemaseed), signed for the same iCloud container, installs it
# on a real iPhone (PORCHLIGHT_SEED_DEVICE, else the first paired iPhone) or with
# --simulator on a simulator signed in to iCloud, and launches it with -seedCloudSchema.
# Being its own app, it never replaces or opens the Porchlight install beside it: that
# app's data, its sync switch and its Release build stay exactly as they were. The seed
# works in a throwaway database, in its own iCloud zone, and removes both when done.
#
# export, diff and check need a CloudKit management token saved once with
#   xcrun cktool save-token --type management
# (create it in the CloudKit Console: Settings, Tokens & Keys, Management Tokens).
# Production can't be changed from here: deploying is a button in the CloudKit Console,
# and check prints the steps.
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
root="${0:A:h:h}"
cd "$root"

container=iCloud.com.mingyucao.porchlight
seed_bundle=com.mingyucao.porchlight.schemaseed
schema_file=Config/cloudkit-schema.ckdb

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

team_id() {
  if [[ ! -f Config/Local.xcconfig ]]; then
    echo "Missing Config/Local.xcconfig. Copy Config/Local.example.xcconfig and set DEVELOPMENT_TEAM." >&2
    exit 1
  fi
  local team
  team="$(sed -n 's/^ *DEVELOPMENT_TEAM *= *\([A-Z0-9]*\).*/\1/p' Config/Local.xcconfig | head -1)"
  if [[ -z "$team" ]]; then
    echo "Config/Local.xcconfig has no DEVELOPMENT_TEAM." >&2
    exit 1
  fi
  echo "$team"
}

# The first paired iPhone, or PORCHLIGHT_SEED_DEVICE.
iphone() {
  if [[ -n "${PORCHLIGHT_SEED_DEVICE:-}" ]]; then
    echo "$PORCHLIGHT_SEED_DEVICE"
    return
  fi
  local json device
  json="$(mktemp)"
  xcrun devicectl list devices --json-output "$json" >/dev/null
  device="$(/usr/bin/python3 -c '
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
hardware = lambda d: d.get("hardwareProperties", {})
phones = [d for d in devices if hardware(d).get("deviceType") == "iPhone" and hardware(d).get("reality", "physical") == "physical"]
print(phones[0]["identifier"] if phones else "")
' "$json")"
  rm -f "$json"
  if [[ -z "$device" ]]; then
    echo "No iPhone found. Connect it with a cable, unlock it and tap Trust, or set PORCHLIGHT_SEED_DEVICE." >&2
    exit 1
  fi
  echo "$device"
}

what_to_watch() {
  cat <<'EOF'

On the screen, "CloudKit schema seed" walks through:
  Writing one row to every table
  Sending every row to iCloud (Development)
  Sharing the seed household
  Checking what reached iCloud
  Removing the seed
and ends with "Schema seeded: 24 record types, 23 records sent, household shared."
followed by "The seed is removed from iCloud and from this device."
"Schema seed failed" means nothing was deployed anywhere; the message says why
(most often: the device isn't signed in to iCloud, or the build isn't signed).

Next: scripts/cloud-schema.sh export, review and commit Config/cloudkit-schema.ckdb,
then deploy it to Production (scripts/cloud-schema.sh check prints the steps).
EOF
}

seed() {
  local simulator=""
  if [[ "${1:-}" == "--simulator" ]]; then
    simulator="${2:?--simulator needs a simulator id}"
  fi
  team_id >/dev/null
  local derived="$HOME/Library/Developer/Xcode/DerivedData/Porchlight-schemaseed"
  local destination="generic/platform=iOS" products=Debug-iphoneos
  if [[ -n "$simulator" ]]; then
    destination="id=$simulator"
    products=Debug-iphonesimulator
  fi
  xcodegen generate --quiet
  # Its own bundle id and name: the seeding app installs beside Porchlight, never over it.
  xcodebuild build \
    -project Porchlight.xcodeproj \
    -scheme Porchlight \
    -configuration Debug \
    -destination "$destination" \
    -derivedDataPath "$derived" \
    -allowProvisioningUpdates \
    -skipMacroValidation \
    PORCHLIGHT_BUNDLE_ID="$seed_bundle" \
    PORCHLIGHT_DISPLAY_NAME="Porchlight Seed" \
    | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
  local app="$derived/Build/Products/$products/Porchlight.app"
  if [[ -n "$simulator" ]]; then
    xcrun simctl install "$simulator" "$app"
    xcrun simctl launch "$simulator" "$seed_bundle" -seedCloudSchema
    echo "Launched Porchlight Seed on simulator $simulator."
  else
    local device
    device="$(iphone)"
    xcrun devicectl device install app --device "$device" "$app"
    xcrun devicectl device process launch --terminate-existing --device "$device" "$seed_bundle" -seedCloudSchema
    echo "Launched Porchlight Seed on $device. Keep the iPhone unlocked until it finishes."
  fi
  what_to_watch
}

uninstall_seed() {
  local device
  device="$(iphone)"
  xcrun devicectl device uninstall app --device "$device" "$seed_bundle"
  echo "Removed Porchlight Seed from $device. Porchlight itself is untouched."
}

export_schema() {
  local environment="$1" file="$2"
  xcrun cktool export-schema --team-id "$(team_id)" --container-id "$container" --environment "$environment" --output-file "$file"
}

case "${1:-}" in
  seed) shift; seed "$@" ;;
  uninstall-seed) uninstall_seed ;;
  export)
    export_schema development "$schema_file"
    echo "Wrote $schema_file from Development. Review it and commit it."
    ;;
  diff)
    [[ -f "$schema_file" ]] || { echo "No $schema_file yet: run export first." >&2; exit 1; }
    current="$(mktemp -d)/development.ckdb"
    export_schema development "$current"
    if diff -u "$schema_file" "$current"; then
      echo "Development matches $schema_file."
    else
      echo "Development differs from $schema_file (- checked in, + Development)."
      exit 1
    fi
    ;;
  check)
    [[ -f "$schema_file" ]] || { echo "No $schema_file yet: run export first." >&2; exit 1; }
    production="$(mktemp -d)/production.ckdb"
    export_schema production "$production"
    if diff -u "$production" "$schema_file"; then
      echo "Production already has every record type and field in $schema_file."
      exit 0
    fi
    # cktool's validate-schema refuses Production ("endpoint not applicable in the
    # environment 'production'"), so the export above is the whole check.
    echo
    echo "Production lacks what is marked + above (- Production, + checked in)."
    cat <<EOF

Deploy it in the CloudKit Console (cktool can't change Production):
  1. Open https://icloud.developer.apple.com and sign in with the developer account.
  2. CloudKit Database, then pick the container $container.
  3. Make sure the environment at the top is Development.
  4. Click "Deploy Schema Changes..." in the sidebar, check the list shows the record
     types and fields above, and click Deploy.
  5. Run scripts/cloud-schema.sh check again: it should say Production has everything.
EOF
    exit 1
    ;;
  *) usage ;;
esac
