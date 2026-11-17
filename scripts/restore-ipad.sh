#!/bin/zsh
# Puts a backup made by backup-ipad.sh back on the wall iPad, replacing the
# app's current data.
#
# Use it to undo a bad change, or to move the household into a freshly
# installed app (for example after the app's bundle id changed).
#
#   scripts/restore-ipad.sh <backup folder> [--bundle <bundle id>]
#
# The app must be installed and must not be running: quit it on the iPad first
# (swipe it away in the app switcher), or the running app keeps the old
# database open. Whatever data the app has now is backed up before it is
# replaced, when there is any.
#
# Optional: PORCHLIGHT_DEVICE=<device identifier from `xcrun devicectl list devices`>
set -euo pipefail

if [[ $# -lt 1 || ! -f "$1/Porchlight/porchlight.sqlite" ]]; then
  echo "Usage: scripts/restore-ipad.sh <backup folder> [--bundle <bundle id>]" >&2
  echo "The folder must hold Porchlight/porchlight.sqlite, as backup-ipad.sh makes it." >&2
  exit 1
fi
backup="${1:A}"
bundle="com.mingyucao.porchlight"
[[ "${2:-}" == "--bundle" ]] && bundle="$3"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
root="${0:A:h:h}"
source "$root/scripts/lib/device.sh"
device="$(porchlight_device)"

# Keep what is there now. A fresh install has no data yet, which is fine.
if "$root/scripts/backup-ipad.sh" --bundle "$bundle" >/dev/null 2>&1; then
  echo "Backed up the app's current data first."
else
  echo "The app has no data to back up yet; continuing."
fi

# Send one consistent database file: fold the write-ahead log into it on a
# scratch copy, so no stale -wal or -shm file is left beside it on the iPad.
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$backup/Porchlight" "$staging/Porchlight"
sqlite3 "$staging/Porchlight/porchlight.sqlite" 'PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE;' >/dev/null
rm -f "$staging/Porchlight/porchlight.sqlite-wal" "$staging/Porchlight/porchlight.sqlite-shm"
if [[ "$(sqlite3 "$staging/Porchlight/porchlight.sqlite" 'PRAGMA integrity_check;')" != "ok" ]]; then
  echo "Restore stopped: the backup's database does not pass its integrity check." >&2
  exit 1
fi

porchlight_devicectl device copy to \
  --device "$device" \
  --domain-type appDataContainer \
  --domain-identifier "$bundle" \
  --source "$staging/Porchlight" \
  --destination "Library/Application Support/Porchlight" \
  --remove-existing-content true >/dev/null

echo "Restored $backup to $bundle on the iPad. Open the app to check it."
