#!/bin/zsh
# Builds Porchlight for TestFlight and uploads it, so family phones get new builds without
# a cable. The wall iPad stays on cable installs (scripts/deploy-ipad.sh).
#
#   scripts/testflight.sh               archive, export, validate, then upload
#   scripts/testflight.sh --no-upload   everything up to the upload: a validated .ipa
#   scripts/testflight.sh --upload-only upload the .ipa the last --no-upload made
#
# The build is a Release archive of the Porchlight scheme for any iOS device, signed
# automatically for App Store Connect, using CloudKit's Production environment and
# production push (as cable Release builds do for CloudKit). Its version is the
# MARKETING_VERSION in project.yml, and its build number comes from the commit
# (scripts/lib/version.sh), so a commit can be uploaded once, and a later one is higher.
#
# Needs: Xcode, `brew install xcodegen`, Config/Local.xcconfig (DEVELOPMENT_TEAM) and
# Config/AppStoreConnect.env (the App Store Connect API key; see scripts/lib/signing.sh).
# Builds outside the repository, in ~/Library/Developer/Xcode/DerivedData/Porchlight-testflight,
# whose newest build is also where --upload-only looks.
set -euo pipefail

mode=all
for argument in "$@"; do
  case "$argument" in
    --no-upload) mode=build ;;
    --upload-only) mode=upload ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $argument" >&2; exit 1 ;;
  esac
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
root="${0:A:h:h}"
cd "$root"
source "$root/scripts/lib/signing.sh"
source "$root/scripts/lib/version.sh"
porchlight_load_signing "$root"
if [[ -z "${PORCHLIGHT_ASC_KEY_ID:-}" ]]; then
  echo "TestFlight needs the App Store Connect key: copy Config/AppStoreConnect.example.env to Config/AppStoreConnect.env and fill it in." >&2
  exit 1
fi
# altool reads the same key.
altool_auth=(--api-key "$PORCHLIGHT_ASC_KEY_ID" --api-issuer "$PORCHLIGHT_ASC_ISSUER_ID" --p8-file-path "$PORCHLIGHT_ASC_KEY_PATH")

work="$HOME/Library/Developer/Xcode/DerivedData/Porchlight-testflight"
latest="$work/latest-ipa"

upload() {
  local ipa="$1"
  echo "Uploading $ipa"
  xcrun altool --upload-app -f "$ipa" --platform ios "${altool_auth[@]}"
  echo "Uploaded. It shows in App Store Connect › TestFlight once Apple has processed it (usually 10 to 30 minutes)."
}

if [[ "$mode" == upload ]]; then
  [[ -f "$latest" ]] || { echo "Nothing to upload: run scripts/testflight.sh --no-upload first." >&2; exit 1; }
  ipa="$(cat "$latest")"
  [[ -f "$ipa" ]] || { echo "The last build's .ipa is gone: $ipa" >&2; exit 1; }
  upload "$ipa"
  exit 0
fi

if [[ ! -f Config/Local.xcconfig ]]; then
  echo "Missing Config/Local.xcconfig. Copy Config/Local.example.xcconfig and set DEVELOPMENT_TEAM." >&2
  exit 1
fi
# A build is a commit: what is uploaded can always be found again.
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "The working tree has uncommitted changes. Commit them first, so the build is a commit." >&2
  exit 1
fi

team="$(porchlight_team_id "$root")"
version="$(porchlight_marketing_version)"
build="$(porchlight_build_number)"
commit="$(git rev-parse --short HEAD)"
out="$work/$version-$build"
archive="$out/Porchlight.xcarchive"
export_dir="$out/export"
rm -rf "$out"
mkdir -p "$out"
echo "Porchlight $version ($build), commit $commit"

xcodegen generate --quiet

echo "Archiving"
xcodebuild archive \
  -project Porchlight.xcodeproj \
  -scheme Porchlight \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$work/DerivedData" \
  -archivePath "$archive" \
  -skipMacroValidation \
  "${porchlight_signing_args[@]}" \
  CURRENT_PROJECT_VERSION="$build" \
  > "$out/archive.log" 2>&1 || { grep -E "error:" "$out/archive.log" | head -20; echo "Archive failed; see $out/archive.log" >&2; exit 1; }

echo "Exporting for App Store Connect"
cat > "$out/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$team</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
xcodebuild -exportArchive \
  -archivePath "$archive" \
  -exportPath "$export_dir" \
  -exportOptionsPlist "$out/ExportOptions.plist" \
  "${porchlight_signing_args[@]}" \
  > "$out/export.log" 2>&1 || { grep -E "error:" "$out/export.log" | head -20; echo "Export failed; see $out/export.log" >&2; exit 1; }
ipa="$(ls "$export_dir"/*.ipa | head -1)"

echo "Validating with App Store Connect"
xcrun altool --validate-app "$ipa" --platform ios "${altool_auth[@]}" 2>&1 | tee "$out/validate.log"
grep -qiE "No errors validating|Validation Succeeded|validated successfully" "$out/validate.log" || { echo "Validation failed; see $out/validate.log" >&2; exit 1; }
echo "$ipa" > "$latest"
echo "Validated: $ipa"

if [[ "$mode" == build ]]; then
  echo "Upload it with: scripts/testflight.sh --upload-only"
  exit 0
fi
upload "$ipa"
