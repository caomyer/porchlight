#!/bin/zsh
# Measures idle CPU on the wall iPad, screen by screen, with Instruments' Activity Monitor.
#
# For each screen it launches Porchlight there, records every process for a while, and
# prints the app's CPU and wakeups and the render server's (backboardd) CPU. The first
# 10 s of each recording are skipped, so launch work doesn't count as idle.
#
# Needs a Debug build on the iPad, since -startScreen is a Debug-only launch argument:
# run scripts/deploy-ipad.sh --debug first, and deploy-ipad.sh again afterwards.
# Uses your real data; it never loads samples.
#
# Usage: scripts/idle-cpu.sh [seconds] [screen...]   (default: 60 s; today calendar glow photos companion-1)
#
# Reference, iPad Pro 10.5" (120 Hz), Nov 2026, after moving idle motion off SwiftUI loops:
#   today 2.2%, calendar 1.5%, glow 2.3%, companion-1 4.8%, photos 11.9% (app + render server,
#   one core = 100%). Before: glow 58%, companion-1 58%, photos 69%.
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

secs=${1:-60}
(( $# )) && shift
screens=("$@")
(( ${#screens} )) || screens=(today calendar glow photos companion-1)

json="$(mktemp)"
xcrun devicectl list devices --json-output "$json" >/dev/null
read -r device udid <<<"$(/usr/bin/python3 -c '
import json, sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    if d["hardwareProperties"].get("deviceType") == "iPad" and d["connectionProperties"].get("tunnelState") == "connected":
        print(d["identifier"], d["hardwareProperties"]["udid"]); break
' "$json")"
rm -f "$json"
if [[ -z "${device:-}" ]]; then
  echo "No connected iPad found. Unlock it and check that it's paired with this Mac." >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
for screen in $screens; do
  xcrun devicectl device process launch --terminate-existing --device "$device" com.mingyucao.porchlight -- -startScreen "$screen" >/dev/null
  sleep 3
  xcrun xctrace record --template "Activity Monitor" --device "$udid" --all-processes \
    --time-limit "${secs}s" --output "$work/$screen.trace" >/dev/null 2>&1
  xcrun xctrace export --input "$work/$screen.trace" \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="activity-monitor-process-live"]' > "$work/$screen.xml"
  /usr/bin/python3 - "$work/$screen.xml" "$screen" <<'EOF'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
ids = {}

def resolve(el):
    """xctrace writes each repeated value once with an id, then refers to it."""
    if 'ref' in el.attrib:
        return ids[el.attrib['ref']]
    if 'id' in el.attrib:
        ids[el.attrib['id']] = el
    for child in el:
        resolve(child)
    return el

cols = [c.findtext('mnemonic') for c in root.iter('col')]
samples = {}
for row in root.iter('row'):
    rec = dict(zip(cols, (resolve(c) for c in row)))
    name = rec['process'].get('fmt', '').split(' (')[0]
    wake = rec.get('idle-wakeups')
    samples.setdefault(name, []).append((
        int(rec['start'].text), int(rec['cpu-total'].text or 0), int(wake.text) if wake is not None and wake.text else 0,
    ))

def usage(name):
    rows = sorted(samples.get(name, []))
    rows = [r for r in rows if r[0] - rows[0][0] >= 10e9] if rows else []
    if len(rows) < 2:
        return 0.0, 0.0
    (t0, c0, w0), (t1, c1, w1) = rows[0], rows[-1]
    return (c1 - c0) / (t1 - t0) * 100, (w1 - w0) / ((t1 - t0) / 1e9)

app, wakeups = usage('Porchlight')
render, _ = usage('backboardd')
print(f'{sys.argv[2]:<14} app {app:5.1f}%  {wakeups:6.1f} wakeups/s   render server {render:5.1f}%   total {app + render:5.1f}%')
EOF
done
xcrun devicectl device process launch --terminate-existing --device "$device" com.mingyucao.porchlight >/dev/null
