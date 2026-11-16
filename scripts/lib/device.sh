# Shared by the scripts that talk to the wall iPad. Source it, then call
# porchlight_device to get the device identifier and porchlight_devicectl to
# run a devicectl command on it.

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

# Runs `xcrun devicectl "$@"`, trying up to three times. Over Wi-Fi the iPad
# often drops a connection right after it opens ("The device disconnected
# immediately after connecting"), and the next attempt goes through.
porchlight_devicectl() {
  local attempt
  for attempt in 1 2 3; do
    xcrun devicectl "$@" && return 0
    (( attempt < 3 )) && echo "The iPad did not answer; trying again ($attempt of 3)." >&2
  done
  return 1
}
