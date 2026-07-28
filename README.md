# brewfile-generator

A shell script that snapshots every installed app on macOS and emits a `Brewfile` for one-command restoration on a new Mac.

For a step-by-step guide to restoring apps on a new Mac, see [MIGRATION.md](MIGRATION.md).

## What it captures

| Source | Brewfile entry | Restore method |
|---|---|---|
| Homebrew taps | `tap "..."` | `brew bundle install` |
| Homebrew formulae | `brew "..."` | `brew bundle install` |
| Homebrew casks | `cask "..."` | `brew bundle install` |
| Mac App Store | `mas "...", id: ...` | `brew bundle install` |
| Setapp | `# setapp "..."` | Manual — open Setapp app |
| Manually installed | `# manual "..."` | Manual — vendor website |

## Usage

```bash
# Generate ~/Brewfile (default)
./generate-brewfile.sh

# Or specify a custom output path
./generate-brewfile.sh ~/Desktop/Brewfile
```

Re-run anytime to refresh. An existing `~/Brewfile` is automatically backed up with a timestamp before each run.

## Requirements

- macOS with [Homebrew](https://brew.sh) installed
- [`mas`](https://github.com/mas-cli/mas) for Mac App Store entries — `brew install mas`
- Python 3 (pre-installed on macOS) for cask artifact parsing
- Must be signed into the **App Store** app for `mas` to work

## Restoring on a new Mac

```bash
# 1. Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. Install mas and sign into the App Store app, then:
brew install mas

# 3. Run the restore
brew bundle install --file=~/Brewfile
```

After `brew bundle install` completes:
- Open **Setapp** and reinstall any `# setapp` apps from your subscription
- Download and reinstall any `# manual` apps from the vendor websites

## Automating with a Launch Agent (recommended)

A macOS Launch Agent runs the script on a schedule in the background — no terminal required. The example below regenerates the Brewfile every **Monday at 9 AM** and commits + pushes the result to GitHub automatically.

**1. Create the plist**

Save the following to `~/Library/LaunchAgents/com.user.brewfile-generator.plist`:

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

  <!-- Homebrew requires its bin directory in PATH -->
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

**2. Load and enable it**

```bash
launchctl load ~/Library/LaunchAgents/com.user.brewfile-generator.plist
```

**3. Verify it loaded**

```bash
launchctl list | grep brewfile-generator
```

**4. Run it immediately (optional test)**

```bash
launchctl start com.user.brewfile-generator
tail -f /tmp/brewfile-generator.log
```

**To disable:**

```bash
launchctl unload ~/Library/LaunchAgents/com.user.brewfile-generator.plist
```

## Automating with cron (alternative)

If you prefer cron, note that it does not inherit your shell's `PATH`, so Homebrew tools must be referenced explicitly.

```bash
crontab -e
```

Add this line to run every Monday at 9 AM:

```
0 9 * * 1 PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin HOME=/Users/rbird /Users/rbird/brewfile-generator/generate-brewfile.sh /Users/rbird/brewfile-generator/Brewfile
```

> **Note:** The Launch Agent approach is preferred on macOS — it respects sleep/wake cycles and integrates with the system properly. Cron jobs may be skipped if the Mac is asleep at the scheduled time.

## How manual-install detection works

The script scans `/Applications` and excludes:
1. Apps with a `Contents/_MASReceipt/` bundle → App Store
2. Apps inside `/Applications/Setapp/` → Setapp
3. Apps with a `com.apple.*` bundle ID → Apple system apps
4. Apps whose `.app` name appears in `brew info --cask --json=v2` output → Homebrew cask

Everything remaining is flagged as `# manual`.
