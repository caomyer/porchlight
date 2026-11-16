# Shared by the scripts that talk to the wall iPad. Source it, then call
# porchlight_device to get the device identifier.

# Prints the identifier of the wall iPad: PORCHLIGHT_DEVICE if set, else the
# first real (not simulated) paired iPad. Exits with a message if there is none.
porchlight_device() {
  if [[ -n "${PORCHLIGHT_DEVICE:-}" ]]; then
    echo "$PORCHLIGHT_DEVICE"
    return
  fi
  local json device
  json="$(mktemp)"
  xcrun devicectl list devices --json-output "$json" >/dev/null
  device="$(/usr/bin/python3 -c '
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
# The list also holds simulators; the wall is a real iPad.
hardware = lambda d: d.get("hardwareProperties", {})
ipads = [d for d in devices if hardware(d).get("deviceType") == "iPad" and hardware(d).get("reality", "physical") == "physical"]
print(ipads[0]["identifier"] if ipads else "")
' "$json")"
  rm -f "$json"
  if [[ -z "$device" ]]; then
    echo "No iPad found. Connect it with a cable, unlock it and tap Trust." >&2
    exit 1
  fi
  echo "$device"
}
