#!/bin/zsh
# Writes a UI test run's named screenshots out of its result bundle, upright, for review.
#
#   scripts/review-shots.sh <result bundle> <folder>
#   scripts/review-shots.sh "$TMPDIR/porchlight-tests-<checkout>/ui-wall.xcresult" shots
#
# A UI test's `snapshot("63-glow")` attaches the screen as the device holds it. The wall runs
# in landscape on an iPad, and on some iOS versions (17.5 among them) the screen's picture
# is still the device's upright, portrait buffer, so the wall comes out a quarter turn on its
# side. Nothing is wrong in the app or the test host: the same test reads the wall's frames
# in landscape. This turns such a picture back, and leaves upright ones alone: a wall shot
# (from an iPad, by its size) that is taller than it is wide is turned a quarter turn.
# Each file is named after its snapshot: 63-glow.png.
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if (( $# != 2 )); then
  sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
fi
bundle="$1"
out="$2"
[[ -d "$bundle" ]] || { echo "No result bundle at $bundle" >&2; exit 1; }
mkdir -p "$out"
raw=$(mktemp -d)
trap 'rm -rf "$raw"' EXIT

xcrun xcresulttool export attachments --path "$bundle" --output-path "$raw" > /dev/null

# The manifest names each exported file; a snapshot's name is everything before "_0_".
python3 -I "$(dirname "$0")/lib/review_shots.py" "$raw" "$out" | while IFS=$'\t' read -r file width height; do
  # An iPad's screen is at least 1488 pixels on its short side; a phone's is narrower.
  if (( height > width && width >= 1488 )); then
    sips -r 270 "$file" > /dev/null
    echo "$(basename "$file") (turned upright)"
  else
    echo "$(basename "$file")"
  fi
done
