#!/bin/zsh
# Checks scripts/lib/stage.sh and scripts/ci/boot-simulator.sh without a simulator: a stage
# that finishes says so; one that stalls is ended at its limit and named; a boot that
# stalls fails the job naming the stage, and is not tried again; a boot that fails outright
# is erased and booted once more, and fails plainly the second time; and the daemons a
# simulator is told not to start are written where launchd reads them before the boot.
# `xcrun` is a stand-in on the PATH. Runs anywhere in about fifteen seconds.
#
#   zsh scripts/ci/check-boot-simulator.sh
set -uo pipefail
repo="${0:A:h:h:h}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
expect() {
  if [[ "$2" == "$3" ]]; then echo "ok: $1"; else echo "FAILED: $1 (expected $3, got $2)"; failures=$(( failures + 1 )); fi
}
says() {
  if grep -q -- "$2" "$work/out"; then echo "ok: $1"; else echo "FAILED: $1: no \"$2\" in:"; cat "$work/out"; failures=$(( failures + 1 )); fi
}

# 1. The stage itself.
source "$repo/scripts/lib/stage.sh"
porchlight_stage "a quick stage" 5 true > "$work/out" 2>&1; expect "a stage that finishes passes" $? 0
says "and says how long it took" 'Done: "a quick stage" in'
porchlight_stage "a failing stage" 5 false > "$work/out" 2>&1; expect "a stage's own failure comes through" $? 1
began=$SECONDS
porchlight_stage "a stalled stage" 2 sleep 60 > "$work/out" 2>&1; expect "a stage still running at its limit is ended" $? 124
expect "within a few seconds of the limit" "$(( SECONDS - began <= 5 ))" 1
says "and named" 'Stalled: "a stalled stage" had not finished after 2s'

# 2. The boot script, with a stand-in simctl: `bootstatus` hangs while $work/hang-boot
#    exists and fails while $work/fail-boot does, and `erase` removes those files when
#    $work/erase-cures exists.
mkdir -p "$work/bin"
cat > "$work/bin/xcrun" <<'EOF'
#!/bin/zsh
[[ "$1" == simctl ]] || exit 1
print -r -- "$2" >> "$FAKE/calls"
case "$2" in
  list) print -r -- "{\"devices\": {\"$RUNTIME\": [{\"name\": \"Porchlight $FAKE_CHECKOUT ipad\", \"udid\": \"FAKE-UDID\", \"isAvailable\": true, \"state\": \"Shutdown\"}]}}" ;;
  boot) ;;
  bootstatus) [[ -e "$FAKE/hang-boot" ]] && sleep 60; [[ -e "$FAKE/fail-boot" ]] && exit 1; exit 0 ;;
  uninstall) [[ -e "$FAKE/hang-ready" ]] && sleep 60; exit 1 ;;
  erase) [[ -e "$FAKE/erase-cures" ]] && rm -f "$FAKE/hang-boot" "$FAKE/hang-ready" "$FAKE/fail-boot"; exit 0 ;;
  shutdown) ;;
esac
EOF
chmod +x "$work/bin/xcrun"
export FAKE="$work" FAKE_CHECKOUT="${repo:t}" RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-27-2
export PORCHLIGHT_BOOT_SECONDS=2 PORCHLIGHT_READY_SECONDS=2
boot() {
  rm -f "$work/calls"
  PATH="$work/bin:$PATH" zsh "$repo/scripts/ci/boot-simulator.sh" ipad > "$work/out" 2>&1
}
calls() { tr '\n' ' ' < "$work/calls" | sed 's/ $//' }

unset PORCHLIGHT_SIM_DISABLED_DAEMONS
rm -f "$work/hang-boot" "$work/hang-ready" "$work/fail-boot" "$work/erase-cures"
boot; expect "a boot that answers passes" $? 0
says "and says it is ready" "Booted ipad FAKE-UDID and ready for installs"
expect "without erasing anything" "$(calls)" "list boot bootstatus uninstall"

touch "$work/hang-boot" "$work/erase-cures"
boot; expect "a boot that stalls fails the job" $? 1
says "naming the stage that stalled" 'stalled at "boot the ipad": it had not finished after 2 seconds'
says "and that no test ran" "No test ran"
expect "and is not erased and tried again" "$(calls)" "list boot bootstatus"

rm -f "$work/hang-boot"
touch "$work/hang-ready"
boot; expect "a simulator that never answers installs fails the job" $? 1
says "naming that stage" 'stalled at "ready for installs"'
expect "and is not erased and tried again either" "$(calls)" "list boot bootstatus uninstall"

rm -f "$work/hang-ready"
touch "$work/fail-boot" "$work/erase-cures"
boot; expect "a boot that fails outright is put right" $? 0
says "saying it booted on the second try" "booted on the second try"
expect "by shutting down, erasing and booting again" "$(calls)" "list boot bootstatus shutdown erase boot bootstatus uninstall"

rm -f "$work/erase-cures"
touch "$work/fail-boot"
boot; expect "a boot that fails outright twice fails the job" $? 1
says "saying so" "failed to boot, twice"
rm -f "$work/fail-boot"

# 3. The daemons a simulator is not to start: in launchd's disabled list for that
#    simulator, before `boot` is asked; "none" and nothing at all write nothing.
disabled="/private/var/tmp/com.apple.CoreSimulator.SimDevice.FAKE-UDID"
rm -rf "$disabled"
PORCHLIGHT_SIM_DISABLED_DAEMONS="com.apple.PosterBoard com.apple.example" boot
expect "a boot told not to start two daemons passes" $? 0
expect "and names the first in the simulator's disabled list" "$(plutil -extract 'com\.apple\.PosterBoard' raw "$disabled/disabled.plist" 2>/dev/null)" true
expect "and the second" "$(plutil -extract 'com\.apple\.example' raw "$disabled/disabled.plist" 2>/dev/null)" true
says "and says so" "Not starting in this simulator: com.apple.PosterBoard com.apple.example"
rm -rf "$disabled"
PORCHLIGHT_SIM_DISABLED_DAEMONS=none boot
expect "\"none\" writes no list" "$([[ -e "$disabled" ]] && echo there || echo absent)" absent
boot
expect "and neither does nothing at all" "$([[ -e "$disabled" ]] && echo there || echo absent)" absent
rm -rf "$disabled"

(( failures == 0 )) || { echo "$failures checks of the boot's stages failed"; exit 1; }
echo "A boot that stalls fails by name, one that fails outright is tried once more, and the disabled daemons are written before the boot."
