# Signing from the command line, sourced by the scripts that sign (deploy-ipad.sh,
# testflight.sh).
#
# `xcodebuild -allowProvisioningUpdates` needs an Apple account to create or refresh
# profiles. Xcode's own sign-in isn't always visible to xcodebuild run from a terminal
# ("No Accounts"), so the scripts sign in with an App Store Connect API key instead.
# Its three values come from the environment or from Config/AppStoreConnect.env, which is
# git-ignored (copy Config/AppStoreConnect.example.env); the key file itself stays where
# it is, outside the repository, and is never copied or printed.
#
#   PORCHLIGHT_ASC_KEY_PATH    the .p8 file, e.g. ~/.appstoreconnect/AuthKey_ABC123.p8
#   PORCHLIGHT_ASC_KEY_ID      its key id, ABC123
#   PORCHLIGHT_ASC_ISSUER_ID   the issuer id from App Store Connect › Users and Access › Integrations
#
# Without them, signing falls back to whatever account xcodebuild can see.

porchlight_load_signing() {
  local file="$1/Config/AppStoreConnect.env"
  if [[ -f "$file" ]]; then
    # Only the three names are read; the environment wins over the file.
    local name value
    while IFS='=' read -r name value; do
      [[ "$name" == PORCHLIGHT_ASC_* ]] || continue
      value="${value%\"}"; value="${value#\"}"
      [[ -n "${(P)name:-}" ]] || typeset -g "$name=$value"
    done < "$file"
  fi
  # Unset is fine (the scripts run with set -u): signing then uses Xcode's account.
  PORCHLIGHT_ASC_KEY_PATH="${PORCHLIGHT_ASC_KEY_PATH:-}"
  PORCHLIGHT_ASC_KEY_PATH="${PORCHLIGHT_ASC_KEY_PATH/#\~/$HOME}"
  # The arguments every signing xcodebuild call adds.
  typeset -ga porchlight_signing_args
  porchlight_signing_args=(-allowProvisioningUpdates)
  if [[ -n "${PORCHLIGHT_ASC_KEY_PATH:-}" && -n "${PORCHLIGHT_ASC_KEY_ID:-}" && -n "${PORCHLIGHT_ASC_ISSUER_ID:-}" ]]; then
    if [[ ! -f "$PORCHLIGHT_ASC_KEY_PATH" ]]; then
      echo "The App Store Connect key isn't at $PORCHLIGHT_ASC_KEY_PATH." >&2
      return 1
    fi
    porchlight_signing_args+=(
      -authenticationKeyPath "$PORCHLIGHT_ASC_KEY_PATH"
      -authenticationKeyID "$PORCHLIGHT_ASC_KEY_ID"
      -authenticationKeyIssuerID "$PORCHLIGHT_ASC_ISSUER_ID"
    )
  else
    echo "No App Store Connect key set (Config/AppStoreConnect.env); signing uses Xcode's account, if xcodebuild can see it." >&2
  fi
}

# The team id from Config/Local.xcconfig, which signing already reads.
porchlight_team_id() {
  sed -n 's/^ *DEVELOPMENT_TEAM *= *\([A-Z0-9]*\).*/\1/p' "$1/Config/Local.xcconfig" | head -1
}
