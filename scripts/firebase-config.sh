#!/bin/zsh
# Puts the character relay's Firebase project into this checkout's build settings, so a
# build made here can draw companion characters (docs/design/companion-characters.md,
# "The relay's client").
#
#   scripts/firebase-config.sh              from ~/.config/porchlight/GoogleService-Info.plist
#   scripts/firebase-config.sh <plist>      from another copy
#   scripts/firebase-config.sh --check      says whether this checkout has it; changes nothing
#   scripts/firebase-config.sh --remove     takes it out again
#
# The project's ids are not secrets, but the repository is public, so they are never
# committed: the plist stays outside the repository, and this writes Config/Firebase.xcconfig,
# which is git-ignored and which Config/Base.xcconfig includes when it is there. A build
# without it works as before and never offers to draw a character.
#
# Run `xcodegen generate` (or any scripts/ build, which does) afterwards.
set -euo pipefail

root="${0:A:h:h}"
out="$root/Config/Firebase.xcconfig"
plist="${PORCHLIGHT_FIREBASE_PLIST:-$HOME/.config/porchlight/GoogleService-Info.plist}"

case "${1:-}" in
  --check)
    if [[ -f "$out" ]]; then echo "This checkout has the relay's Firebase project."; exit 0; fi
    echo "This checkout has no Firebase project: builds here cannot draw characters." >&2
    exit 1
    ;;
  --remove) rm -f "$out"; echo "Removed $out"; exit 0 ;;
  -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) plist="$1" ;;
esac

if [[ ! -f "$plist" ]]; then
  echo "No GoogleService-Info.plist at $plist." >&2
  echo "Download it from the Firebase console (Project settings, the iOS app) and save it there, or give its path." >&2
  exit 1
fi

read_key() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || true
}
app_id="$(read_key GOOGLE_APP_ID)"
api_key="$(read_key API_KEY)"
project_id="$(read_key PROJECT_ID)"
sender_id="$(read_key GCM_SENDER_ID)"
bundle_id="$(read_key BUNDLE_ID)"

for pair in "GOOGLE_APP_ID=$app_id" "API_KEY=$api_key" "PROJECT_ID=$project_id" "GCM_SENDER_ID=$sender_id"; do
  if [[ -z "${pair#*=}" ]]; then
    echo "$plist has no ${pair%%=*}: it is not a complete GoogleService-Info.plist." >&2
    exit 1
  fi
done
# An xcconfig value ends at "//", and none of these may hold a space or a quote.
for value in "$app_id" "$api_key" "$project_id" "$sender_id"; do
  if [[ "$value" == *"//"* || "$value" == *" "* || "$value" == *'"'* || "$value" == *'$'* ]]; then
    echo "A value in $plist cannot be written to an xcconfig file." >&2
    exit 1
  fi
done
if [[ -n "$bundle_id" && "$bundle_id" != "com.mingyucao.porchlight" ]]; then
  echo "$plist is for the app $bundle_id, not Porchlight." >&2
  exit 1
fi

cat > "$out" <<CONFIG
// Written by scripts/firebase-config.sh. Git-ignored: never commit it.
PORCHLIGHT_FIREBASE_APP_ID = $app_id
PORCHLIGHT_FIREBASE_API_KEY = $api_key
PORCHLIGHT_FIREBASE_PROJECT_ID = $project_id
PORCHLIGHT_FIREBASE_SENDER_ID = $sender_id
CONFIG
echo "Wrote Config/Firebase.xcconfig: builds from this checkout can reach the character relay."
