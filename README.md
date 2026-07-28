# brewfile-generator

A shell script that snapshots every installed app on macOS and emits a `Brewfile` for one-command restoration on a new Mac.

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

## How manual-install detection works

The script scans `/Applications` and excludes:
1. Apps with a `Contents/_MASReceipt/` bundle → App Store
2. Apps inside `/Applications/Setapp/` → Setapp
3. Apps with a `com.apple.*` bundle ID → Apple system apps
4. Apps whose `.app` name appears in `brew info --cask --json=v2` output → Homebrew cask

Everything remaining is flagged as `# manual`.
