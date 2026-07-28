#!/usr/bin/env bash
#
# setup-launchagent.sh
# Install and load a macOS Launch Agent that refreshes the Brewfile weekly
# and auto-commits + pushes the result to GitHub.
#
# Usage:
#   ./setup-launchagent.sh          # install and load
#   ./setup-launchagent.sh --unload  # stop and remove
#   ./setup-launchagent.sh --run     # trigger immediately (for testing)
#
# Schedule: every Monday at 09:00 (edit WEEKDAY/HOUR/MINUTE below to change)

set -uo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"   # resolved from script location
BREWFILE="$REPO_DIR/Brewfile"
GENERATOR="$REPO_DIR/generate-brewfile.sh"
LABEL="com.user.brewfile-generator"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG="/tmp/brewfile-generator.log"
WEEKDAY=1   # 1 = Monday (0=Sun, 1=Mon … 7=Sat)
HOUR=9
MINUTE=0

# ── Colour helpers ─────────────────────────────────────────────────────────────
_tput() { tput "$@" 2>/dev/null || printf ''; }
BOLD=$(_tput bold); GREEN=$(_tput setaf 2); YELLOW=$(_tput setaf 3)
RED=$(_tput setaf 1); RESET=$(_tput sgr0)

log()  { printf '%s==>%s %s\n' "${GREEN}${BOLD}" "$RESET" "$*"; }
ok()   { printf '%s  ✔%s %s\n' "$GREEN"          "$RESET" "$*"; }
warn() { printf '%s  ⚠  %s%s\n' "$YELLOW"        "$RESET" "$*" >&2; }
err()  { printf '%sError:%s %s\n' "${RED}${BOLD}" "$RESET" "$*" >&2; exit 1; }

# ── Preflight checks ──────────────────────────────────────────────────────────
[[ ! -f "$GENERATOR" ]] && err "generate-brewfile.sh not found at $GENERATOR"

# ── Subcommands ───────────────────────────────────────────────────────────────
case "${1:-}" in

  --unload)
    log "Unloading Launch Agent…"
    launchctl unload "$PLIST" 2>/dev/null && ok "Unloaded $LABEL" || warn "Was not loaded"
    rm -f "$PLIST" && ok "Removed $PLIST"
    exit 0
    ;;

  --run)
    log "Triggering Brewfile refresh now…"
    launchctl start "$LABEL" 2>/dev/null \
      || err "$LABEL is not loaded. Run ./setup-launchagent.sh first."
    ok "Started — follow logs with: tail -f $LOG"
    exit 0
    ;;

esac

# ── Write the plist ───────────────────────────────────────────────────────────
log "Writing plist → $PLIST"
mkdir -p "$(dirname "$PLIST")"

# Unload first if already loaded, to pick up any changes
launchctl unload "$PLIST" 2>/dev/null || true

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-c</string>
    <string>
      ${GENERATOR} ${BREWFILE} &amp;&amp;
      cd ${REPO_DIR} &amp;&amp;
      git add Brewfile &amp;&amp;
      git diff --cached --quiet ||
        git commit -m "chore: refresh Brewfile \$(date +%Y-%m-%d)" &amp;&amp;
        git push
    </string>
  </array>

  <!-- Homebrew and git require these paths -->
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>HOME</key>
    <string>${HOME}</string>
  </dict>

  <!-- Run every ${WEEKDAY}/${HOUR}:$(printf '%02d' $MINUTE) -->
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key>
    <integer>${WEEKDAY}</integer>
    <key>Hour</key>
    <integer>${HOUR}</integer>
    <key>Minute</key>
    <integer>${MINUTE}</integer>
  </dict>

  <key>StandardOutPath</key>
  <string>${LOG}</string>
  <key>StandardErrorPath</key>
  <string>${LOG}</string>

  <!-- Do not run immediately on load -->
  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
EOF

ok "Plist written"

# ── Load the agent ────────────────────────────────────────────────────────────
log "Loading Launch Agent…"
launchctl load "$PLIST" || err "launchctl load failed — check $PLIST for errors"
ok "Loaded $LABEL"

# ── Verify ────────────────────────────────────────────────────────────────────
log "Verifying…"
if launchctl list | grep -q "$LABEL"; then
  ok "Agent is active"
else
  warn "Agent not found in launchctl list — it may have exited immediately"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
DAY_NAMES=(Sun Mon Tue Wed Thu Fri Sat)
echo ""
printf '%s✔  Launch Agent installed%s\n' "${GREEN}${BOLD}" "$RESET"
printf '   %-14s %s\n' "Label:"    "$LABEL"
printf '   %-14s %s\n' "Schedule:" "Every ${DAY_NAMES[$WEEKDAY]} at $(printf '%02d:%02d' $HOUR $MINUTE)"
printf '   %-14s %s\n' "Repo:"     "$REPO_DIR"
printf '   %-14s %s\n' "Log:"      "$LOG"
echo ""
printf 'Useful commands:\n'
printf '  Test now:   ./setup-launchagent.sh --run && tail -f %s\n' "$LOG"
printf '  Remove:     ./setup-launchagent.sh --unload\n'
printf '  View log:   tail -f %s\n' "$LOG"
