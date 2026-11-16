#!/bin/zsh
# Copies the wall iPad's Porchlight data (database and photos) to this Mac.
#
# Run before anything that could change the wall's data. deploy-ipad.sh runs it
# before every install. The copy is checked before the script reports success:
# the database must open, pass SQLite's integrity check and hold a household.
#
#   scripts/backup-ipad.sh [--bundle <bundle id>]
#
# Backups land in ~/Library/Application Support/Porchlight/Backups/<date-time>/,
# and the path is printed on the last line. The newest 30 are kept.
#
# Optional: PORCHLIGHT_DEVICE=<device identifier from `xcrun devicectl list devices`>
set -euo pipefail

bundle="com.porchlight.porchlight"
[[ "${1:-}" == "--bundle" ]] && bundle="$2"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
root="${0:A:h:h}"
source "$root/scripts/lib/device.sh"
device="$(porchlight_device)"

backups="$HOME/Library/Application Support/Porchlight/Backups"
target="$backups/$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$target"

# Everything the app stores lives under one folder (see AppFiles.swift).
if ! xcrun devicectl device copy from \
    --device "$device" \
    --domain-type appDataContainer \
    --domain-identifier "$bundle" \
    --source "Library/Application Support/Porchlight" \
    --destination "$target/Porchlight" >"$target/copy.log" 2>&1; then
  cat "$target/copy.log" >&2
  echo "Backup failed: could not copy the data of $bundle from the iPad." >&2
  rm -rf "$target"
  exit 1
fi

database="$target/Porchlight/porchlight.sqlite"
if [[ ! -f "$database" ]]; then
  echo "Backup failed: no database in the copy at $target." >&2
  exit 1
fi

# Verify on a scratch copy, so opening it never changes the backup itself.
check="$(mktemp -d)"
trap 'rm -rf "$check"' EXIT
cp "$target/Porchlight"/porchlight.sqlite* "$check/"
integrity="$(sqlite3 "$check/porchlight.sqlite" 'PRAGMA integrity_check;')"
households="$(sqlite3 "$check/porchlight.sqlite" 'SELECT COUNT(*) FROM household;')"
if [[ "$integrity" != "ok" || "$households" -lt 1 ]]; then
  echo "Backup failed its check (integrity: $integrity, households: $households). Kept at $target for a look." >&2
  exit 1
fi

# Keep the newest 30.
ls -1d "$backups"/*/ 2>/dev/null | sort -r | tail -n +31 | while read -r old; do rm -rf "$old"; done

echo "Backed up the wall's data ($(du -sh "$target" | cut -f1 | tr -d ' '), $households household)."
echo "$target"
