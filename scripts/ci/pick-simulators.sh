#!/bin/zsh
# Picks this Xcode's models for the test simulators, of the same sizes as the local ones,
# for scripts/lib/simulators.sh: a hosted Mac's newer Xcode may not have the local models.
# Writes them to $GITHUB_ENV for the steps after.
set -euo pipefail

types=$(xcrun simctl list devicetypes)
pick() {
  local found
  found=$(print -r -- "$types" | sed -n "s/.*(\(com\.apple\.CoreSimulator\.SimDeviceType\.$1\)).*/\1/p" | head -1)
  [[ -n "$found" ]] || { echo "No simulator model matches $1 in:" >&2; print -r -- "$types" >&2; return 1; }
  print -r -- "$found"
}
# The wall: a 13-inch iPad Pro, as on the local Mac.
ipad=$(pick 'iPad-Pro-13-inch[^)]*')
# The phone: the local iPhone 15 if this Xcode still has it, else the plainest newer iPhone.
iphone=$(pick 'iPhone-15' 2>/dev/null || pick 'iPhone-1[6-9]' || pick 'iPhone-[2-9][0-9]')
echo "iPad: $ipad"
echo "iPhone: $iphone"
print -r -- "PORCHLIGHT_SIM_IPAD_TYPE=$ipad" >> "$GITHUB_ENV"
print -r -- "PORCHLIGHT_SIM_IPHONE_TYPE=$iphone" >> "$GITHUB_ENV"
