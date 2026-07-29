#!/usr/bin/env bash
#
# generate-brewfile.sh
# Snapshot all installed apps and emit a Brewfile for easy migration to a new Mac.
#
# Usage:
#   ./generate-brewfile.sh [output-path]
#   output-path defaults to ~/Brewfile
#
# Covers:
#   • Homebrew taps / formulae / casks
#   • Mac App Store apps     (requires: brew install mas)
#   • Setapp apps            (commented — reinstall via Setapp UI after migration)
#   • Browser extensions     (commented — Chrome, Brave, Edge, Arc, Firefox)
#   • Manually installed apps (commented — download from vendor websites)
#   • WebCatalog pinned apps  (commented — reinstall via WebCatalog app)
#   • ~/Applications apps     (Autodesk, etc. — compared against all known sources)
#
# Restore on a new Mac:
#   1. Install Homebrew  → https://brew.sh
#   2. brew install mas
#   3. brew bundle install --file=Brewfile

set -uo pipefail

OUTPUT="${1:-$HOME/Brewfile}"
SETAPP_DIR="/Applications/Setapp"
WEBCATALOG_DIR="$HOME/Applications/WebCatalog Apps"

# ── Colour helpers ─────────────────────────────────────────────────────────────
_tput() { tput "$@" 2>/dev/null || printf ''; }
BOLD=$(_tput bold); GREEN=$(_tput setaf 2); YELLOW=$(_tput setaf 3)
RED=$(_tput setaf 1); RESET=$(_tput sgr0)

log()  { printf '%s==>%s %s\n'      "${GREEN}${BOLD}" "$RESET" "$*"; }
ok()   { printf '%s  ✔%s %s\n'      "$GREEN"          "$RESET" "$*"; }
warn() { printf '%s  ⚠  %s%s\n'     "$YELLOW"         "$RESET" "$*" >&2; }
err()  { printf '%sError:%s %s\n'   "${RED}${BOLD}"   "$RESET" "$*" >&2; }

has()  { command -v "$1" &>/dev/null; }

sec()  {                                              # write a section header
  printf '\n# ── %s %s\n' "$1" \
    "$(printf '%0.s─' $(seq 1 $((74 - ${#1}))))" >> "$OUTPUT"
}

# ── Back up existing Brewfile ─────────────────────────────────────────────────
if [[ -f "$OUTPUT" ]]; then
  BACKUP="${OUTPUT}.$(date '+%Y%m%d_%H%M%S').bak"
  cp "$OUTPUT" "$BACKUP"
  warn "Existing Brewfile backed up → $BACKUP"
fi

# ── Header ────────────────────────────────────────────────────────────────────
log "Generating Brewfile → $OUTPUT"
cat > "$OUTPUT" <<EOF
# Brewfile — generated $(date '+%Y-%m-%d')
#
# Restore all apps on a new Mac:
#   1. Install Homebrew:  /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
#   2. Install mas:       brew install mas
#   3. Sign in App Store app (required for mas to work)
#   4. Run:               brew bundle install --file="$(basename "$OUTPUT")"
#
# Setapp apps (marked with "# setapp") must be reinstalled manually
# through the Setapp desktop app after subscribing at https://setapp.com
#
# Browser extensions (marked with "# <browser>-extension") must be reinstalled
# manually from each browser's extension store.
#
# Manually installed apps (marked with "# manual") were not installed via
# any package manager and must be downloaded from the vendor's website.
#
# WebCatalog apps (marked with "# webcatalog") are pinned web apps managed
# by WebCatalog (https://webcatalog.io). Reinstall via the WebCatalog desktop app.
EOF

# ── Homebrew ──────────────────────────────────────────────────────────────────
if ! has brew; then
  warn "Homebrew not found — skipping taps, formulae, and casks."
else

  # Taps -----------------------------------------------------------------------
  log "Collecting Homebrew taps…"
  sec "Taps"
  tap_count=0
  while IFS= read -r tap; do
    printf 'tap "%s"\n' "$tap" >> "$OUTPUT"
    (( tap_count++ )) || true
  done < <(brew tap | sort)
  ok "$tap_count tap(s)"

  # Formulae -------------------------------------------------------------------
  log "Collecting Homebrew formulae…"
  sec "Formulae"
  formula_count=0
  while IFS= read -r formula; do
    printf 'brew "%s"\n' "$formula" >> "$OUTPUT"
    (( formula_count++ )) || true
  done < <(brew list --formula --full-name 2>/dev/null | sort)
  ok "$formula_count formula(e)"

  # Casks ----------------------------------------------------------------------
  log "Collecting Homebrew casks…"
  sec "Casks"
  cask_count=0
  while IFS= read -r cask; do
    printf 'cask "%s"\n' "$cask" >> "$OUTPUT"
    (( cask_count++ )) || true
  done < <(brew list --cask --full-name 2>/dev/null | sort)
  ok "$cask_count cask(s)"

fi

# ── Mac App Store ─────────────────────────────────────────────────────────────
log "Collecting Mac App Store apps…"
sec "Mac App Store"
mas_count=0
mas_adopted=0

if ! has mas; then
  warn "'mas' not found — App Store entries skipped."
  printf '# Skipped: install mas with "brew install mas" then re-run this script.\n' >> "$OUTPUT"
else
  # Cache mas list to a temp file (reused for cask-adoption check and writing)
  _mas_list_tmp=$(mktemp)
  mas list 2>/dev/null | sort -f -k2 > "$_mas_list_tmp"

  # Build a MAS-id → cask-slug map using parallel Homebrew lookups (10 threads).
  # Checks every MAS app to see if a matching cask exists.
  log "  Checking for Homebrew cask alternatives for MAS apps…"
  _mas_cask_map=$(mktemp)
  python3 -c "
import sys, subprocess, re
from concurrent.futures import ThreadPoolExecutor, as_completed

def to_slug(name):
    name = re.sub(r'\s*[-\u2013]\s*\S.*$', '', name)
    name = re.sub(r'\s+\d+$', '', name)
    name = name.lower().strip()
    name = re.sub(r'[^a-z0-9]+', '-', name)
    return name.strip('-')

def check(app_id, slug):
    r = subprocess.run(['brew', 'info', '--cask', slug],
                       capture_output=True, text=True)
    return (app_id, slug) if r.returncode == 0 else None

entries = []
with open('$_mas_list_tmp') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        m = re.match(r'^\s*(\d+)\s+(.+?)\s*(?:\([^)]+\))?\s*$', line)
        if m:
            slug = to_slug(m.group(2).strip())
            if slug:
                entries.append((m.group(1), slug))

with ThreadPoolExecutor(max_workers=10) as ex:
    futures = {ex.submit(check, *e): e for e in entries}
    for f in as_completed(futures):
        r = f.result()
        if r:
            print(r[0] + '\t' + r[1])
" > "$_mas_cask_map" 2>/dev/null || true

  # Write entries: cask for adopted apps, mas for the rest
  while IFS= read -r line; do
    [[ -z "${line// }" ]] && continue
    app_id=$(awk '{print $1}' <<< "$line")
    app_name=$(awk '{
      sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "")
      sub(/[[:space:]]+\([^)]+\)[[:space:]]*$/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
    }' <<< "$line")
    [[ -z "$app_id" || -z "$app_name" ]] && continue

    # Check if a cask equivalent was found for this app
    cask_slug=$(awk -F'\t' -v id="$app_id" '$1==id{print $2}' "$_mas_cask_map" 2>/dev/null)
    if [[ -n "$cask_slug" ]]; then
      printf 'cask "%s"  # adopted from MAS: "%s" (id: %s)\n' \
        "$cask_slug" "$app_name" "$app_id" >> "$OUTPUT"
      (( mas_adopted++ )) || true
    else
      printf 'mas "%s", id: %s\n' "$app_name" "$app_id" >> "$OUTPUT"
      (( mas_count++ )) || true
    fi
  done < "$_mas_list_tmp"

  rm -f "$_mas_list_tmp" "$_mas_cask_map"
  ok "$mas_count App Store app(s), $mas_adopted adopted as Homebrew casks"
fi

# ── Setapp ────────────────────────────────────────────────────────────────────
log "Collecting Setapp apps…"
sec "Setapp — reinstall manually via the Setapp desktop app"
printf '# These apps require an active Setapp subscription (https://setapp.com).\n' >> "$OUTPUT"
printf '# After "brew bundle install", open Setapp and reinstall each one.\n' >> "$OUTPUT"
setapp_count=0

if [[ ! -d "$SETAPP_DIR" ]]; then
  warn "No Setapp directory found at $SETAPP_DIR — skipping."
  printf '# (Setapp not installed or no apps found at %s)\n' "$SETAPP_DIR" >> "$OUTPUT"
else
  while IFS= read -r -d '' app; do
    app_name=$(basename "$app" .app)
    printf '# setapp "%s"\n' "$app_name" >> "$OUTPUT"
    (( setapp_count++ )) || true
  done < <(find "$SETAPP_DIR" -maxdepth 1 -name "*.app" -print0 | sort -z)
  ok "$setapp_count Setapp app(s)"
fi

# ── Browser Extensions ────────────────────────────────────────────────────────
log "Collecting browser extensions…"
sec "Browser Extensions — reinstall manually from each browser's extension store"
printf '# Safari extensions are bundled with App Store apps and already captured above.\n' >> "$OUTPUT"
ext_count=0

# Helper: scan a Chromium-based browser's Extensions directory
_scan_chromium_exts() {
  local _browser="$1" _ext_dir="$2" _found=0
  [[ ! -d "$_ext_dir" ]] && { echo 0; return; }
  printf '\n# %s\n' "$_browser" >> "$OUTPUT"
  while IFS= read -r -d '' _ext_path; do
    local _id _ver _manifest _name _key
    _id=$(basename "$_ext_path")
    [[ ${#_id} -ne 32 ]] && continue          # extension IDs are always 32 chars
    [[ "$_id" =~ [^a-p] ]] && continue        # valid chars are a–p only
    _ver=$(ls "$_ext_path" 2>/dev/null | sort -V | tail -1)
    [[ -z "$_ver" ]] && continue
    _manifest="$_ext_path/$_ver/manifest.json"
    [[ ! -f "$_manifest" ]] && continue
    # Resolve name, handling __MSG_xxx__ i18n placeholders
    _name=$(MANIFEST="$_manifest" python3 -c "
import json, os, re
try:
    d = json.load(open(os.environ['MANIFEST']))
    n = d.get('name', '')
    m = re.match(r'^__MSG_(\\w+)__$', n)
    if m:
        k = m.group(1)
        base = os.path.dirname(os.environ['MANIFEST'])
        for lang in ('en', 'en_US', 'en_GB'):
            lf = os.path.join(base, '_locales', lang, 'messages.json')
            if os.path.exists(lf):
                msgs = json.load(open(lf))
                n = (msgs.get(k) or msgs.get(k.lower()) or {}).get('message', n)
                break
    print(n.strip())
except Exception:
    print('')
" 2>/dev/null)
    [[ -z "$_name" ]] && _name="Unknown (ID: $_id)"
    _key=$(printf '%s' "$_browser" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    printf '# %s-extension "%s"  # ID: %s\n' "$_key" "$_name" "$_id" >> "$OUTPUT"
    (( _found++ )) || true
  done < <(find "$_ext_dir" -maxdepth 1 -mindepth 1 -type d -print0 | sort -z)
  echo "$_found"
}

# Chromium-based browsers
_n=$(_scan_chromium_exts "Chrome" "$HOME/Library/Application Support/Google/Chrome/Default/Extensions")
(( ext_count += _n )) || true
_n=$(_scan_chromium_exts "Brave"  "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default/Extensions")
(( ext_count += _n )) || true
_n=$(_scan_chromium_exts "Edge"   "$HOME/Library/Application Support/Microsoft Edge/Default/Extensions")
(( ext_count += _n )) || true
_n=$(_scan_chromium_exts "Arc"    "$HOME/Library/Application Support/Arc/User Data/Default/Extensions")
(( ext_count += _n )) || true

# Firefox
printf '\n# Firefox\n' >> "$OUTPUT"
_ff_count=0
while IFS= read -r _ext_json; do
  [[ ! -f "$_ext_json" ]] && continue
  while IFS= read -r _ext_name; do
    [[ -z "$_ext_name" ]] && continue
    printf '# firefox-extension "%s"\n' "$_ext_name" >> "$OUTPUT"
    (( _ff_count++ )) || true
  done < <(EXT_JSON="$_ext_json" python3 -c "
import json, os
try:
    data = json.load(open(os.environ['EXT_JSON']))
    for a in data.get('addons', []):
        aid = a.get('id', '')
        if (a.get('type') == 'extension'
                and not a.get('isSystem', False)
                and not a.get('hidden', False)
                and not any(aid.endswith(s) for s in
                    ('@mozilla.org','@mozilla.com','@firefox.com','@shield.mozilla.org'))):
            name = (a.get('defaultLocale') or {}).get('name') or aid
            if name:
                print(name)
except Exception:
    pass
" 2>/dev/null)
done < <(find "$HOME/Library/Application Support/Firefox/Profiles" \
  -maxdepth 2 -name "extensions.json" 2>/dev/null)
(( ext_count += _ff_count )) || true

ok "$ext_count browser extension(s)"

# ── Manually Installed Apps ───────────────────────────────────────────────────
log "Scanning /Applications for manually installed apps…"
log "  Querying brew info for all cask artifacts (may take ~30s)…"

# Write cask-installed .app names to a temp file (bash 3.2-compatible lookup)
_cask_tmp=$(mktemp)
trap 'rm -f "$_cask_tmp"' EXIT INT TERM

if has brew; then
  _cask_list=()
  while IFS= read -r _c; do
    _cask_list+=("$_c")
  done < <(brew list --cask --full-name 2>/dev/null)

  if [[ ${#_cask_list[@]} -gt 0 ]]; then
    brew info --cask --json=v2 "${_cask_list[@]}" 2>/dev/null | python3 -c "
import json, sys, os
try:
    data = json.load(sys.stdin)
    for cask in data.get('casks', []):
        for artifact in cask.get('artifacts', []):
            if not isinstance(artifact, dict):
                continue
            # Direct .app installs
            if 'app' in artifact:
                apps = artifact['app']
                if isinstance(apps, str):
                    apps = [apps]
                for app in apps:
                    if isinstance(app, str) and app.endswith('.app'):
                        print(os.path.basename(app))
            # pkg-based installs: app path lives in uninstall -> delete
            if 'uninstall' in artifact:
                uninstalls = artifact['uninstall']
                if isinstance(uninstalls, dict):
                    uninstalls = [uninstalls]
                for u in uninstalls:
                    if not isinstance(u, dict):
                        continue
                    deletes = u.get('delete', [])
                    if isinstance(deletes, str):
                        deletes = [deletes]
                    for d in deletes:
                        if isinstance(d, str) and d.endswith('.app'):
                            print(os.path.basename(d))
except Exception:
    pass
" > "$_cask_tmp" 2>/dev/null || true
  fi
fi

sec "Manually Installed — download and reinstall from vendor websites"
printf '# Apps in /Applications or ~/Applications not tracked by any known source.\n' >> "$OUTPUT"
printf '# Reinstall each one manually on a new Mac.\n' >> "$OUTPUT"
manual_count=0

while IFS= read -r -d '' _app_path; do
  _app_name=$(basename "$_app_path")
  _app_stem="${_app_name%.app}"

  # Skip apps inside Setapp folder
  [[ -d "$SETAPP_DIR/$_app_name" ]] && continue

  # Skip apps inside WebCatalog folder (handled in its own section)
  [[ "$_app_path" == "$WEBCATALOG_DIR"* ]] && continue

  # Skip App Store apps — they contain a MAS receipt bundle
  [[ -d "$_app_path/Contents/_MASReceipt" ]] && continue

  # Skip Apple system apps (bundle ID starts with com.apple.)
  _bid=$(defaults read "$_app_path/Contents/Info" CFBundleIdentifier 2>/dev/null || true)
  [[ "$_bid" == com.apple.* ]] && continue

  # Skip apps already accounted for by a Homebrew cask
  grep -Fxq "$_app_name" "$_cask_tmp" 2>/dev/null && continue

  printf '# manual "%s"\n' "$_app_stem" >> "$OUTPUT"
  (( manual_count++ )) || true
done < <(
  # Scan both /Applications (system-wide) and ~/Applications (user-level).
  # -maxdepth 1 naturally excludes browser App dirs (not *.app) and WebCatalog
  # sub-apps (depth 2 inside 'WebCatalog Apps/').
  find /Applications "$HOME/Applications" \
    -maxdepth 1 -name "*.app" -print0 2>/dev/null | sort -z
)
ok "$manual_count manually installed app(s) (across /Applications and ~/Applications)"

# ── WebCatalog Apps ────────────────────────────────────────────────────────────
log "Collecting WebCatalog apps…"
sec "WebCatalog Apps — reinstall via the WebCatalog desktop app"
printf '# WebCatalog (cask "webcatalog") must be installed first.\n' >> "$OUTPUT"
printf '# Open WebCatalog and search for each app to pin it again.\n' >> "$OUTPUT"
webcatalog_count=0

if [[ -d "$WEBCATALOG_DIR" ]]; then
  while IFS= read -r -d '' _wc_app; do
    printf '# webcatalog "%s"\n' "$(basename "$_wc_app" .app)" >> "$OUTPUT"
    (( webcatalog_count++ )) || true
  done < <(find "$WEBCATALOG_DIR" -maxdepth 1 -name "*.app" -print0 | sort -z)
  ok "$webcatalog_count WebCatalog app(s)"
else
  ok "WebCatalog not installed — skipping"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
printf '\n' >> "$OUTPUT"

echo ""
printf '%s✔  Brewfile written:%s %s\n' "${GREEN}${BOLD}" "$RESET" "$OUTPUT"
printf '   %-14s %s\n' "Taps:"      "${tap_count:-0}"
printf '   %-14s %s\n' "Formulae:" "${formula_count:-0}"
printf '   %-14s %s\n' "Casks:"    "${cask_count:-0}"
printf '   %-14s %s\n' "App Store:" "$mas_count"
printf '   %-14s %s\n' "  Adopted:" "$mas_adopted (MAS → cask)"
printf '   %-14s %s\n' "Setapp:"    "$setapp_count"
printf '   %-14s %s\n' "Extensions:" "$ext_count"
printf '   %-14s %s\n' "WebCatalog:" "$webcatalog_count"
printf '   %-14s %s\n' "Manual:"    "$manual_count"
echo ""
printf 'To restore on a new Mac:\n'
printf '  brew bundle install --file="%s"\n' "$OUTPUT"

# ── Verification ──────────────────────────────────────────────────────────────
echo ""
log "Verifying Brewfile…"
_verify_pass=0 _verify_fail=0

_check() {   # _check "description" <exit-code>
  if [[ "$2" -eq 0 ]]; then
    ok "$1"
    (( _verify_pass++ )) || true
  else
    warn "FAIL: $1"
    (( _verify_fail++ )) || true
  fi
}

# 1. File exists and is non-empty
[[ -s "$OUTPUT" ]]; _check "File exists and is non-empty" $?

# 2. Header contains today's date
grep -q "^# Brewfile — generated $(date '+%Y-%m-%d')" "$OUTPUT" 2>/dev/null
_check "Header contains today's date" $?

# 3. All section headers present
for _sec in "Taps" "Formulae" "Casks" "Mac App Store" "Setapp" "Browser Extensions" "Manually Installed" "WebCatalog Apps"; do
  grep -q "^# ── ${_sec}" "$OUTPUT" 2>/dev/null
  _check "Section present: ${_sec}" $?
done

# 4. Entry counts match what was written
_actual_brews=$(grep -c  '^brew '   "$OUTPUT" 2>/dev/null || echo 0)
_actual_casks=$(grep -c  '^cask '   "$OUTPUT" 2>/dev/null || echo 0)
_actual_mas=$( grep -c  '^mas '    "$OUTPUT" 2>/dev/null || echo 0)
[[ "$_actual_brews" -eq "${formula_count:-0}" ]]; _check "Formula count matches (${_actual_brews})" $?
_expected_casks=$(( ${cask_count:-0} + mas_adopted ))
[[ "$_actual_casks" -eq "$_expected_casks" ]]; _check "Cask count matches (${_actual_casks}, incl. ${mas_adopted} adopted)" $?
[[ "$_actual_mas"   -eq "$mas_count" ]];       _check "MAS count matches (${_actual_mas})" $?

# 5. brew bundle check — confirms all Homebrew/MAS entries are satisfied
# Skip when adopted casks are present: those apps are currently MAS-installed
# on this machine and would cause false failures; they'll satisfy on a new Mac.
if has brew; then
  if [[ "$mas_adopted" -gt 0 ]]; then
    ok "brew bundle check skipped (${mas_adopted} adopted casks not yet Homebrew-managed on this Mac)"
    (( _verify_pass++ )) || true
  else
    log "  Running brew bundle check (validates all entries are installed)…"
    brew bundle check --file="$OUTPUT" --no-upgrade 1>/dev/null 2>&1
    _check "brew bundle check passed" $?
  fi
fi

# ── Verification result ───────────────────────────────────────────────────────
echo ""
if [[ "$_verify_fail" -eq 0 ]]; then
  printf '%s✔  Verification passed%s — %d checks, 0 failures\n' \
    "${GREEN}${BOLD}" "$RESET" "$_verify_pass"
else
  printf '%s✘  Verification failed%s — %d passed, %d failed\n' \
    "${RED}${BOLD}" "$RESET" "$_verify_pass" "$_verify_fail"
  err "Review warnings above before using this Brewfile."
fi
