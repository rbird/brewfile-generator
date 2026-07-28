# brewfile-generator

A shell script that snapshots every installed app on macOS and emits a `Brewfile`
for one-command restoration on a new Mac.

## What it captures

| Source | Brewfile entry | Restore method |
|---|---|---|
| Homebrew taps | `tap "..."` | `brew bundle install` |
| Homebrew formulae | `brew "..."` | `brew bundle install` |
| Homebrew casks | `cask "..."` | `brew bundle install` |
| Mac App Store | `mas "...", id: ...` | `brew bundle install` |
| Setapp | `# setapp "..."` | Manual — open Setapp app |
| Browser extensions | `# <browser>-extension "..."` | Manual — browser extension store |
| Manually installed | `# manual "..."` | Manual — vendor website |

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

Installs all Homebrew taps, formulae, casks, and Mac App Store apps automatically.
Expect **20–60 minutes** depending on your internet speed and app count.

> **Tip:** `brew bundle install` is idempotent — if anything fails, fix the issue
> and re-run. Already-installed entries are skipped automatically.
> Add `--verbose` for per-package output if something appears stuck.

### Step 5 — Reinstall Setapp apps

Print your Setapp checklist:

```bash
grep "^# setapp" ~/brewfile-generator/Brewfile | sed 's/# setapp "//;s/"//'
```

Open the **Setapp** desktop app, search for each app by name, and install.
All apps are included in your subscription — no individual purchases needed.

### Step 6 — Reinstall browser extensions

Print extensions per browser:

```bash
grep "^# chrome-extension"  ~/brewfile-generator/Brewfile | sed 's/# chrome-extension "//;s/".*//'
grep "^# brave-extension"   ~/brewfile-generator/Brewfile | sed 's/# brave-extension "//;s/".*//'
grep "^# edge-extension"    ~/brewfile-generator/Brewfile | sed 's/# edge-extension "//;s/".*//'
grep "^# arc-extension"     ~/brewfile-generator/Brewfile | sed 's/# arc-extension "//;s/".*//'
grep "^# firefox-extension" ~/brewfile-generator/Brewfile | sed 's/# firefox-extension "//;s/"//'
```

Each Chrome/Brave/Edge/Arc entry includes the extension ID — use it to jump directly
to the install page:

```
https://chromewebstore.google.com/detail/<ID>
```

### Step 7 — Reinstall manually installed apps

Print your manual checklist:

```bash
grep "^# manual" ~/brewfile-generator/Brewfile | sed 's/# manual "//;s/"//'
```

For each app:
1. Check `brew search <name>` first — it may now be available as a cask
2. If not, download the installer from the vendor's website
3. Re-enter any license keys (check your email or password manager)

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

## Automating with a Launch Agent (recommended)

A macOS Launch Agent runs the script weekly and auto-commits changes to GitHub.

**1. Create the plist**

Save to `~/Library/LaunchAgents/com.user.brewfile-generator.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.user.brewfile-generator</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-c</string>
    <string>
      /Users/rbird/brewfile-generator/generate-brewfile.sh \
        /Users/rbird/brewfile-generator/Brewfile &amp;&amp; \
      cd /Users/rbird/brewfile-generator &amp;&amp; \
      git add Brewfile &amp;&amp; \
      git diff --cached --quiet || \
        git commit -m "chore: refresh Brewfile $(date +%Y-%m-%d)" &amp;&amp; \
        git push
    </string>
  </array>

  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>HOME</key>
    <string>/Users/rbird</string>
  </dict>

  <!-- Run every Monday at 09:00 -->
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key>
    <integer>1</integer>
    <key>Hour</key>
    <integer>9</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>

  <key>StandardOutPath</key>
  <string>/tmp/brewfile-generator.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/brewfile-generator.log</string>

  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
```

**2. Load and enable**

```bash
launchctl load ~/Library/LaunchAgents/com.user.brewfile-generator.plist
```

**3. Verify it loaded**

```bash
launchctl list | grep brewfile-generator
```

**4. Test immediately**

```bash
launchctl start com.user.brewfile-generator
tail -f /tmp/brewfile-generator.log
```

**To disable:**

```bash
launchctl unload ~/Library/LaunchAgents/com.user.brewfile-generator.plist
```

> **Note:** The Launch Agent approach is preferred over cron — it respects sleep/wake
> cycles and won't be skipped if your Mac is asleep at the scheduled time.

---

## How manual-install detection works

The script scans `/Applications` and excludes:
1. Apps inside `/Applications/Setapp/` → Setapp
2. Apps with a `Contents/_MASReceipt/` bundle → App Store
3. Apps with a `com.apple.*` bundle ID → Apple system apps
4. Apps whose `.app` name appears in `brew info --cask --json=v2` output → Homebrew cask

Everything remaining is flagged as `# manual`.

---

## License

MIT — see [LICENSE](LICENSE)
