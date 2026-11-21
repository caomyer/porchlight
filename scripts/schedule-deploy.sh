#!/bin/zsh
# Optional: schedules a reinstall of Porchlight on the wall iPad every Sunday and
# Wednesday at 3:00 am, so a wall kept on cable installs stays on the latest commit
# and is backed up twice a week (and a free-Apple-ID install never hits its 7-day
# expiry). The household's own devices update through TestFlight and have no schedule.
#
#   scripts/schedule-deploy.sh            install or update the schedule
#   scripts/schedule-deploy.sh --run-now  install, then run once immediately
#   scripts/schedule-deploy.sh --remove   remove the schedule
#
# macOS does not let background jobs read ~/Documents, so the job builds from a
# private mirror in ~/Library/Application Support/Porchlight:
#   deploy.git  bare mirror; a post-commit hook in this repo pushes main to it after every commit
#   src/        clean checkout the job refreshes and builds
# Output goes to ~/Library/Logs/Porchlight/deploy.log; failures raise a notification.
set -euo pipefail

label="com.mingyucao.porchlight.deploy"
plist="$HOME/Library/LaunchAgents/$label.plist"
root="${0:A:h:h}"
support="$HOME/Library/Application Support/Porchlight"
logs="$HOME/Library/Logs/Porchlight"
domain="gui/$(id -u)"
# Where git keeps this repository's hooks. In a worktree `.git` is a file, and the hooks
# are the main checkout's, so the path is asked for, never built from "$root/.git".
hook="$(git -C "$root" rev-parse --path-format=absolute --git-path hooks)/post-commit"

if [[ "${1:-}" == "--remove" ]]; then
  launchctl bootout "$domain/$label" 2>/dev/null || true
  rm -f "$plist"
  # Only the hook this script wrote: another post-commit hook is left alone.
  if [[ -f "$hook" ]] && grep -q "Porchlight deploy mirror" "$hook"; then rm -f "$hook"; fi
  git -C "$root" remote remove deploy 2>/dev/null || true
  echo "Removed the Porchlight deploy schedule (the mirror in $support is left in place)."
  exit 0
fi

if [[ ! -f "$root/Config/Local.xcconfig" ]]; then
  echo "Missing Config/Local.xcconfig. Copy Config/Local.example.xcconfig and set DEVELOPMENT_TEAM." >&2
  exit 1
fi

mkdir -p "$support" "$logs" "$HOME/Library/LaunchAgents"

# 1. Mirror: bare repo + remote + post-commit hook that keeps it current.
if [[ ! -d "$support/deploy.git" ]]; then
  git init -q --bare "$support/deploy.git"
fi
git -C "$root" remote remove deploy 2>/dev/null || true
git -C "$root" remote add deploy "$support/deploy.git"
mkdir -p "${hook:h}"
cat > "$hook" <<'EOF'
#!/bin/sh
# Keeps the Porchlight deploy mirror current (see scripts/schedule-deploy.sh).
# Only main is mirrored: a commit on another branch or in a worktree must never
# reach the wall through the scheduled install.
git push -q --force deploy refs/heads/main:refs/heads/main >/dev/null 2>&1 || true
EOF
chmod +x "$hook"
git -C "$root" push -q --force deploy refs/heads/main:refs/heads/main

# 2. Signing settings the job needs (git-ignored, so copied separately).
cp "$root/Config/Local.xcconfig" "$support/Local.xcconfig"

# 3. The job itself: refresh the checkout, then run the repo's deploy script.
cat > "$support/run-deploy.sh" <<EOF
#!/bin/zsh
set -euo pipefail
echo "=== \$(date)"
src="$support/src"
if [[ ! -d "\$src/.git" ]]; then
  git clone -q "$support/deploy.git" "\$src"
fi
git -C "\$src" fetch -q origin main
git -C "\$src" reset -q --hard origin/main
cp "$support/Local.xcconfig" "\$src/Config/Local.xcconfig"
"\$src/scripts/deploy-ipad.sh"
EOF
chmod +x "$support/run-deploy.sh"

cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-c</string>
    <string>'$support/run-deploy.sh' || osascript -e 'display notification "See ~/Library/Logs/Porchlight/deploy.log" with title "Porchlight reinstall failed"'</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StartCalendarInterval</key>
  <array>
    <dict><key>Weekday</key><integer>0</integer><key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer></dict>
    <dict><key>Weekday</key><integer>3</integer><key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer></dict>
  </array>
  <key>StandardOutPath</key><string>$logs/deploy.log</string>
  <key>StandardErrorPath</key><string>$logs/deploy.log</string>
</dict>
</plist>
EOF
plutil -lint "$plist" >/dev/null

launchctl bootout "$domain/$label" 2>/dev/null || true
launchctl bootstrap "$domain" "$plist"
echo "Scheduled Porchlight reinstall: Sundays and Wednesdays at 3:00 am."

if [[ "${1:-}" == "--run-now" ]]; then
  launchctl kickstart -k "$domain/$label"
  echo "Started a run now; follow it with: tail -f $logs/deploy.log"
fi
