# brewfile-generator

A shell script that snapshots every installed app on macOS and emits a `Brewfile`
for one-command restoration on a new Mac.

## Getting Started

```bash
# 1. Clone the repo
git clone https://github.com/rbird/brewfile-generator ~/brewfile-generator
cd ~/brewfile-generator

# 2. Install mas (required for App Store entries)
brew install mas

# 3. Run the script
./generate-brewfile.sh ~/brewfile-generator/Brewfile

# 4. Commit and push the snapshot
git add Brewfile && git commit -m "chore: initial Brewfile snapshot" && git push

# 5. (Optional) Set up weekly automation
./setup-launchagent.sh
```

That's it. The script scans your Mac, writes the Brewfile, and runs 14 validation
checks automatically. See the sections below for full details on each step.

---

## What it captures

| Source | Brewfile entry | Restore method |
|---|---|---|
| Homebrew taps | `tap "..."` | `brew bundle install` |
| Homebrew formulae | `brew "..."` | `brew bundle install` |
| Homebrew casks | `cask "..."` | `brew bundle install` |
| Mac App Store | `mas "...", id: ...` | `brew bundle install` |
| MAS apps w/ cask equivalent | `cask "..."  # adopted from MAS` | `brew bundle install` — no App Store sign-in needed |
| Setapp | `# setapp "..."` | Manual — open Setapp app |
| WebCatalog pinned apps | `# webcatalog "..."` | Manual — open WebCatalog app |
| Browser extensions | `# <browser>-extension "..."` | Manual — browser extension store |
| Manually installed | `# manual "..."` | Manual — vendor website |

During generation the script automatically checks every App Store app against
Homebrew. Any that have a matching cask are written as `cask` entries so they
install via Homebrew on restore — no App Store sign-in required for those apps.

---

## Generating the Brewfile

```bash
# Write to ~/Brewfile (default)
./generate-brewfile.sh

# Or specify a custom path
./generate-brewfile.sh ~/brewfile-generator/Brewfile
```

Re-run any time you install something new. An existing Brewfile is automatically
backed up with a timestamp (`Brewfile.YYYYMMDD_HHMMSS.bak`) before each run.

### Built-in verification

After every generation the script automatically runs 14 checks and prints a
pass/fail summary:

```
==> Verifying Brewfile…
  ✔ File exists and is non-empty
  ✔ Header contains today's date
  ✔ Section present: Taps
  ✔ Section present: Formulae
  ✔ Section present: Casks
  ✔ Section present: Mac App Store
  ✔ Section present: Setapp
  ✔ Section present: Browser Extensions
  ✔ Section present: Manually Installed
  ✔ Section present: WebCatalog Apps
  ✔ Formula count matches (125)
  ✔ Cask count matches (111, incl. 18 adopted)
  ✔ MAS count matches (69)
  ✔ brew bundle check skipped (18 adopted casks not yet Homebrew-managed on this Mac)

✔  Verification passed — 14 checks, 0 failures
```

> The `brew bundle check` step is automatically skipped when MAS apps have been
> adopted as casks. Those apps are currently installed via the App Store on this
> machine and would cause false failures — they will satisfy on a new Mac.

If any check fails the script prints `✘ Verification failed` with specific
warnings. Review those before committing the Brewfile.

## Requirements

- macOS with [Homebrew](https://brew.sh)
- [`mas`](https://github.com/mas-cli/mas) for App Store entries — `brew install mas`
- Python 3 (pre-installed on macOS) for cask and extension name resolution
- Signed into the **App Store** app for `mas` to work

---

## Restoring on a new Mac

### Step 1 — Install Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

On Apple Silicon, follow the post-install prompt to add Homebrew to your PATH.

### Step 2 — Clone this repo

```bash
git clone https://github.com/rbird/brewfile-generator ~/brewfile-generator
```

### Step 3 — Install `mas` and sign into the App Store

```bash
brew install mas
```

Open the **App Store** app and sign in with your Apple ID before continuing.
`mas` requires an active session — App Store entries will fail silently without it.

### Step 4 — Run the automated restore

```bash
brew bundle install --file=~/brewfile-generator/Brewfile
```

Installs all Homebrew taps, formulae, casks, App Store apps, and any MAS apps
that were adopted as casks. Expect **20–60 minutes** depending on your internet
speed and app count.

> **Tip:** `brew bundle install` is idempotent — if anything fails, fix the issue
> and re-run. Already-installed entries are skipped automatically.
> Add `--verbose` for per-package output if something appears stuck.

### Steps 5–8 — Manual post-restore checklist

These sources require manual reinstallation after `brew bundle install` completes.
Run each command to print the relevant checklist.

**Setapp** — open the Setapp desktop app and reinstall each:

```bash
grep "^# setapp" ~/brewfile-generator/Brewfile | sed 's/# setapp "//;s/"//'
```

**WebCatalog** — open the WebCatalog app and search for each to re-pin it:

```bash
grep "^# webcatalog" ~/brewfile-generator/Brewfile | sed 's/# webcatalog "//;s/"//'
```

> `webcatalog` itself installs via `brew bundle install`. Only the pinned apps
> inside it need to be re-pinned manually through the WebCatalog interface.

**Browser extensions** — reinstall from each browser's extension store:

```bash
grep "^# chrome-extension"  ~/brewfile-generator/Brewfile | sed 's/# chrome-extension "//;s/".*//'
grep "^# edge-extension"    ~/brewfile-generator/Brewfile | sed 's/# edge-extension "//;s/".*//'
grep "^# arc-extension"     ~/brewfile-generator/Brewfile | sed 's/# arc-extension "//;s/".*//'
grep "^# brave-extension"   ~/brewfile-generator/Brewfile | sed 's/# brave-extension "//;s/".*//'
grep "^# firefox-extension" ~/brewfile-generator/Brewfile | sed 's/# firefox-extension "//;s/"//'
```

Chrome/Edge/Arc/Brave entries include the extension ID. Install directly:

```
https://chromewebstore.google.com/detail/<ID>
```

**Manually installed apps** — download from vendor websites:

```bash
grep "^# manual" ~/brewfile-generator/Brewfile | sed 's/# manual "//;s/"//'
```

For each app:
1. Run `brew search <name>` first — it may now be available as a cask
2. If not, download from the vendor's website
3. Re-enter license keys from your email or password manager

---

## Keeping the Brewfile current

Re-run the script any time your app inventory changes:

```bash
cd ~/brewfile-generator
./generate-brewfile.sh ~/brewfile-generator/Brewfile
git add Brewfile && git commit -m "chore: refresh Brewfile $(date +%Y-%m-%d)" && git push
```

Or activate the weekly Launch Agent below to keep it updated automatically.

---

## Adopting manually installed apps as Homebrew casks

Some apps in the `# manual` list may have become available as Homebrew casks
since you first installed them. Adopting them means they restore automatically
via `brew bundle install` and update with `brew upgrade` — no manual downloads.

### Find adoptable apps

Run this to check all `# manual` entries against Homebrew (takes ~15 seconds):

```bash
grep "^# manual" ~/brewfile-generator/Brewfile | sed 's/# manual "//;s/"//' | \
python3 -c "
import sys, subprocess, re
from concurrent.futures import ThreadPoolExecutor, as_completed

def slug(n):
    n = re.sub(r'\s*[-–]\s*\S.*$', '', n)
    n = re.sub(r'\s+\d+$', '', n)
    n = re.sub(r'[^a-z0-9]+', '-', n.lower().strip())
    return n.strip('-')

def check(name):
    s = slug(name)
    r = subprocess.run(['brew','info','--cask',s], capture_output=True)
    return (name, s) if r.returncode == 0 else None

names = [l.strip() for l in sys.stdin if l.strip()]
with ThreadPoolExecutor(max_workers=10) as ex:
    for r in sorted(filter(None, ex.map(check, names))):
        print(f'  brew install --cask {r[1]:<32}  # {r[0]}')
"
```

### Current adoptable apps (as of 2026-07-29)

16 of 64 manually installed apps are available as Homebrew casks:

```bash
brew install --cask app-cleaner              # App Cleaner 8
brew install --cask autodesk-fusion          # Autodesk Fusion
brew install --cask clay                     # Clay
brew install --cask cocktail                 # Cocktail
brew install --cask dante-controller         # Dante Controller
brew install --cask displaycal               # DisplayCAL
brew install --cask dupeguru                 # dupeguru
brew install --cask excire-foto              # Excire Foto
brew install --cask izotope-product-portal   # iZotope Product Portal
brew install --cask qgis                     # QGIS
brew install --cask screenflow               # ScreenFlow
brew install --cask telegram-desktop         # Telegram Desktop
brew install --cask topaz-gigapixel-ai       # Topaz Gigapixel AI
brew install --cask topaz-photo              # Topaz Photo
brew install --cask topaz-photo-ai           # Topaz Photo AI
brew install --cask topaz-video-ai           # Topaz Video AI
```

### Adoption procedure

```bash
# 1. Uninstall the existing app (drag to Trash, or use App Cleaner)

# 2. Install via Homebrew
brew install --cask autodesk-fusion

# 3. After adopting all desired apps, refresh the Brewfile
cd ~/brewfile-generator
./generate-brewfile.sh ~/brewfile-generator/Brewfile
git add Brewfile && git commit -m "chore: adopt manual apps as casks" && git push
```

After refresh, adopted apps will move from `# manual` to `cask "..."` entries
automatically — no Brewfile editing required.

---

## Automating with a Launch Agent (recommended)

`setup-launchagent.sh` handles the full lifecycle — writing the plist,
loading it, and verifying it — in a single command.

### Install

```bash
./setup-launchagent.sh
```

This writes the plist to `~/Library/LaunchAgents/`, loads it with `launchctl`,
and confirms the agent is active. The Brewfile refreshes every **Monday at 09:00**
and auto-commits + pushes only when the content actually changes.

### Test immediately

```bash
./setup-launchagent.sh --run
tail -f /tmp/brewfile-generator.log
```

### Remove

```bash
./setup-launchagent.sh --unload
```

Unloads the agent and deletes the plist.

### Change the schedule

Edit the three variables at the top of `setup-launchagent.sh`, then re-run it:

```bash
WEEKDAY=1   # 0=Sun  1=Mon  2=Tue  3=Wed  4=Thu  5=Fri  6=Sat
HOUR=9
MINUTE=0
```

```bash
./setup-launchagent.sh   # re-run to apply the new schedule
```

> **Note:** Launch Agents are preferred over cron on macOS — they respect
> sleep/wake cycles and won't be skipped if your Mac is asleep at run time.

---

## Verifying the automation is working

### Check the agent is loaded

```bash
launchctl list | grep brewfile-generator
```

A result with a PID (first column) means it is currently running. A `-` means
it is loaded and waiting for its next scheduled time. No output means it is
not loaded — run `./setup-launchagent.sh` to install it.

### Check the last run log

```bash
cat /tmp/brewfile-generator.log
```

Look for the summary block at the end:

```
✔  Brewfile written: …
   Taps:          5
   Formulae:      123
   …
```

If the log is empty or absent the agent has not run yet (it only fires on
schedule unless triggered manually with `--run`).

### Check the git history

```bash
git -C ~/brewfile-generator log --oneline -10
```

Successful runs that detected changes produce a commit like:

```
a1b2c3d chore: refresh Brewfile 2026-07-28
```

No recent `chore: refresh` commits means either the app inventory has not
changed since the last run (expected), or the agent has not fired yet.

### Check the Brewfile date

```bash
head -1 ~/brewfile-generator/Brewfile
```

This prints the generation date. If it matches today (or the last expected
Monday) the agent ran successfully.

### Troubleshooting the automation

| Symptom | Likely cause | Fix |
|---|---|---|
| No log file | Agent hasn't fired yet | Run `./setup-launchagent.sh --run` to test manually |
| Log shows errors | PATH or permission issue | Re-run `./setup-launchagent.sh` to rewrite the plist |
| `git push` fails | SSH key unavailable to agent | `git remote set-url origin https://github.com/rbird/brewfile-generator` |
| Agent not in `launchctl list` | Plist not loaded | Run `./setup-launchagent.sh` to reinstall |
| `mas` errors during run | Not signed into App Store | Open the App Store app and sign in |

---

## Troubleshooting

### Script fails or produces errors

**`✘ Verification failed`** — one or more of the 14 checks did not pass:

```bash
bash generate-brewfile.sh ~/brewfile-generator/Brewfile 2>&1 | grep -E "✔|✘|FAIL"
```

The output names the specific failing check. Most failures are transient (network,
App Store session). Fix the issue and re-run.

**`mas` returns no apps or wrong names** — sign into the App Store app first:

```bash
open -a "App Store"
# sign in, then re-run the script
```

**App appears as `# manual` but should be a cask** — the cask name may differ from
the app filename. Check manually:

```bash
brew search "app name"
```

**WebCatalog apps not showing up** — confirm the directory exists:

```bash
ls ~/Applications/WebCatalog\ Apps/
```

If missing, WebCatalog may not be installed or apps haven't been pinned yet.

### Restore fails on a new Mac

**`brew bundle install` fails midway** — it is safe to re-run; already-installed
entries are skipped automatically. For a verbose view of what failed:

```bash
brew bundle install --file=~/brewfile-generator/Brewfile --verbose
```

**MAS apps fail silently** — the App Store session is required:

```bash
mas account     # should show your Apple ID
mas signin      # if blank, sign in again
```

**Adopted cask not found** — a cask that existed when the Brewfile was generated
may have been renamed. Find the new name:

```bash
brew search "app name"   # then update the cask entry in the Brewfile
```

**Autodesk Fusion or other `.pkg`-installed apps** — these are in the `# manual`
list. Download the installer from [autodesk.com/fusion360](https://www.autodesk.com/products/fusion-360/personal).

---

## How manual-install detection works

The script scans both `/Applications` and `~/Applications` (depth 1 only) and
excludes each app if it matches any of the following:

1. Path is inside `/Applications/Setapp/` → Setapp
2. Path is inside `~/Applications/WebCatalog Apps/` → WebCatalog (own section)
3. Bundle contains `Contents/_MASReceipt/` → App Store
4. Bundle ID starts with `com.apple.` → Apple system app
5. App name appears in `brew info --cask --json=v2` → Homebrew cask
   (checks both direct `app` artifacts and `uninstall.delete` for pkg-based casks)

Everything remaining is flagged as `# manual`.

---

## License

MIT — see [LICENSE](LICENSE)
