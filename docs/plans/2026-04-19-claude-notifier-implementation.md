# claude-notifier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a cross-platform, one-line installable Claude Code hook set that plays a system sound and shows a desktop toast when Claude finishes a task or asks a question.

**Architecture:** Two layers — installer scripts (one-shot, patch `~/.claude/settings.json`, drop a helper) and runtime helpers (invoked by hooks, read env vars, dispatch to OS sound + toast APIs). Windows uses PowerShell + WinRT; macOS uses bash + osascript/afplay; Linux uses bash + notify-send/paplay.

**Tech Stack:** PowerShell 5.1+, POSIX bash, native OS notification APIs, no runtime dependencies.

**Spec:** `docs/specs/2026-04-19-claude-notifier-design.md`

**Project root:** `C:\Users\mrt_b\claude-notifier\`

---

## File Inventory

| Path | Purpose | Approx size |
|---|---|---|
| `install.ps1` | Windows installer + uninstaller | 150 lines |
| `install.sh` | macOS/Linux installer + uninstaller | 130 lines |
| `scripts/notify.ps1` | Windows runtime helper | 60 lines |
| `scripts/notify.sh` | macOS/Linux runtime helper | 80 lines |
| `README.md` | EN documentation | 120 lines |
| `README.tr.md` | TR documentation | 120 lines |
| `LICENSE` | MIT | 21 lines |
| `.gitignore` | Git ignore | 5 lines |
| `.github/workflows/lint.yml` | shellcheck + PSScriptAnalyzer CI | 30 lines |

---

## Local testing convention

Installers support a `CLAUDE_NOTIFIER_SOURCE` env var. When set to a local path, the installer copies the helper from that path instead of downloading from GitHub. This lets us integration-test before publishing.

**Test harness pattern used in multiple tasks:**

```bash
# bash
TMPHOME=$(mktemp -d)
HOME="$TMPHOME" CLAUDE_NOTIFIER_SOURCE="$PWD" bash install.sh
# inspect $TMPHOME/.claude-notifier/ and $TMPHOME/.claude/settings.json
rm -rf "$TMPHOME"
```

```powershell
# PowerShell
$TMPHOME = (New-Item -ItemType Directory -Path "$env:TEMP\cn-$(Get-Random)").FullName
$env:HOME = $TMPHOME; $env:USERPROFILE = $TMPHOME; $env:CLAUDE_NOTIFIER_SOURCE = (Get-Location).Path
./install.ps1
# inspect $TMPHOME/.claude-notifier/ and $TMPHOME/.claude/settings.json
Remove-Item $TMPHOME -Recurse -Force
```

---

## Task 1: Initialize git repo and commit skeleton

**Files:**
- Create: `.gitignore`
- Already exists: `docs/specs/2026-04-19-claude-notifier-design.md`
- Already exists: `docs/plans/2026-04-19-claude-notifier-implementation.md` (this file)

- [ ] **Step 1: Create `.gitignore`**

```
# editor / OS
.DS_Store
Thumbs.db
*.swp
.vscode/
```

- [ ] **Step 2: Initialize git repo**

Run in `C:\Users\mrt_b\claude-notifier\`:
```bash
git init -b main
```
Expected: `Initialized empty Git repository in .../claude-notifier/.git/`

- [ ] **Step 3: First commit**

```bash
git add .gitignore docs/
git commit -m "docs: initial spec and implementation plan"
```
Expected: commit created, `git log --oneline` shows one commit.

---

## Task 2: Windows runtime helper `scripts/notify.ps1`

**Files:**
- Create: `scripts/notify.ps1`

- [ ] **Step 1: Write `scripts/notify.ps1`**

```powershell
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Stop','Notification')]
    [string]$Event
)

# Defaults
$lang   = if ($env:CLAUDE_NOTIFIER_LANG)   { $env:CLAUDE_NOTIFIER_LANG.ToLower() } else { 'en' }
$events = if ($env:CLAUDE_NOTIFIER_EVENTS) { $env:CLAUDE_NOTIFIER_EVENTS.ToLower() } else { 'stop,notification' }
$sound  = if ($env:CLAUDE_NOTIFIER_SOUND -eq $null) { '1' } else { $env:CLAUDE_NOTIFIER_SOUND }
$toast  = if ($env:CLAUDE_NOTIFIER_TOAST -eq $null) { '1' } else { $env:CLAUDE_NOTIFIER_TOAST }

if (($events -split ',') -notcontains $Event.ToLower()) { exit 0 }

$messages = @{
    'Stop'         = @{ 'en' = 'Task complete';               'tr' = 'İş tamamlandı' }
    'Notification' = @{ 'en' = 'Claude needs your attention'; 'tr' = 'Claude dikkatini bekliyor' }
}
$msg = $messages[$Event][$lang]
if (-not $msg) { $msg = $messages[$Event]['en'] }

if ($sound -eq '1') {
    try {
        if ($Event -eq 'Stop') { [System.Media.SystemSounds]::Asterisk.Play() }
        else                   { [System.Media.SystemSounds]::Exclamation.Play() }
    } catch { Write-Error "sound failed: $_" }
}

if ($toast -eq '1') {
    try {
        [Windows.UI.Notifications.ToastNotificationManager,Windows.UI.Notifications,ContentType=WindowsRuntime] > $null
        $x = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $n = $x.GetElementsByTagName('text')
        $null = $n.Item(0).AppendChild($x.CreateTextNode('Claude Code'))
        $null = $n.Item(1).AppendChild($x.CreateTextNode($msg))
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Claude Code').Show([Windows.UI.Notifications.ToastNotification]::new($x))
    } catch { Write-Error "toast failed: $_" }
}

exit 0
```

- [ ] **Step 2: Smoke test the helper directly**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/notify.ps1 -Event Stop
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/notify.ps1 -Event Notification
```
Expected: you hear two different sounds and see two toasts ("Task complete", "Claude needs your attention"). Exit code 0 both times.

- [ ] **Step 3: Test language switch**

```powershell
$env:CLAUDE_NOTIFIER_LANG = 'tr'
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/notify.ps1 -Event Stop
Remove-Item Env:\CLAUDE_NOTIFIER_LANG
```
Expected: toast shows "İş tamamlandı".

- [ ] **Step 4: Test event disable**

```powershell
$env:CLAUDE_NOTIFIER_EVENTS = 'notification'
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/notify.ps1 -Event Stop
Remove-Item Env:\CLAUDE_NOTIFIER_EVENTS
```
Expected: no sound, no toast, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/notify.ps1
git commit -m "feat: Windows runtime helper (notify.ps1)"
```

---

## Task 3: macOS/Linux runtime helper `scripts/notify.sh`

**Files:**
- Create: `scripts/notify.sh`

- [ ] **Step 1: Write `scripts/notify.sh`**

```bash
#!/usr/bin/env bash
# claude-notifier runtime helper (macOS/Linux)
# Usage: notify.sh <Stop|Notification>

set -u

EVENT="${1:-}"
case "$EVENT" in
    Stop|Notification) ;;
    *) echo "usage: notify.sh <Stop|Notification>" >&2; exit 2 ;;
esac

LANG_PREF="${CLAUDE_NOTIFIER_LANG:-en}"
LANG_PREF="$(echo "$LANG_PREF" | tr '[:upper:]' '[:lower:]')"
EVENTS_PREF="${CLAUDE_NOTIFIER_EVENTS:-stop,notification}"
EVENTS_PREF="$(echo "$EVENTS_PREF" | tr '[:upper:]' '[:lower:]')"
SOUND_PREF="${CLAUDE_NOTIFIER_SOUND:-1}"
TOAST_PREF="${CLAUDE_NOTIFIER_TOAST:-1}"

event_lower="$(echo "$EVENT" | tr '[:upper:]' '[:lower:]')"
case ",$EVENTS_PREF," in
    *",$event_lower,"*) ;;
    *) exit 0 ;;
esac

# Message lookup
if [ "$EVENT" = "Stop" ]; then
    msg_en="Task complete";               msg_tr="İş tamamlandı"
else
    msg_en="Claude needs your attention"; msg_tr="Claude dikkatini bekliyor"
fi
case "$LANG_PREF" in
    tr) msg="$msg_tr" ;;
    *)  msg="$msg_en" ;;
esac

os="$(uname -s)"

play_sound() {
    if [ "$SOUND_PREF" != "1" ]; then return 0; fi
    case "$os" in
        Darwin)
            if [ "$EVENT" = "Stop" ]; then sound=/System/Library/Sounds/Glass.aiff
            else                            sound=/System/Library/Sounds/Ping.aiff
            fi
            afplay "$sound" 2>/dev/null || true
            ;;
        Linux)
            if [ "$EVENT" = "Stop" ]; then fd=/usr/share/sounds/freedesktop/stereo/complete.oga
            else                            fd=/usr/share/sounds/freedesktop/stereo/message.oga
            fi
            if command -v paplay >/dev/null 2>&1 && [ -f "$fd" ]; then
                paplay "$fd" 2>/dev/null || true
            elif command -v aplay >/dev/null 2>&1 && [ -f /usr/share/sounds/alsa/Front_Center.wav ]; then
                aplay /usr/share/sounds/alsa/Front_Center.wav 2>/dev/null || true
            else
                printf '\a'
            fi
            ;;
    esac
}

show_toast() {
    if [ "$TOAST_PREF" != "1" ]; then return 0; fi
    case "$os" in
        Darwin)
            # Escape double quotes and backslashes for AppleScript
            safe_msg=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')
            osascript -e "display notification \"$safe_msg\" with title \"Claude Code\"" 2>/dev/null || \
                echo "toast failed (osascript missing?)" >&2
            ;;
        Linux)
            if command -v notify-send >/dev/null 2>&1; then
                notify-send "Claude Code" "$msg" 2>/dev/null || true
            else
                echo "toast unavailable: install libnotify-bin (e.g., apt install libnotify-bin)" >&2
            fi
            ;;
    esac
}

play_sound
show_toast
exit 0
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/notify.sh
```

- [ ] **Step 3: Smoke test (run on a mac/Linux machine if available; on Windows skip to commit)**

```bash
./scripts/notify.sh Stop
./scripts/notify.sh Notification
CLAUDE_NOTIFIER_LANG=tr ./scripts/notify.sh Stop
CLAUDE_NOTIFIER_EVENTS=notification ./scripts/notify.sh Stop  # should be silent
./scripts/notify.sh BadEvent                                   # should exit 2 with usage msg
```
Expected: on mac/Linux, appropriate sounds + toasts; language switch shows Turkish; disabled event silent; bad event prints usage and exits 2.

- [ ] **Step 4: Commit**

```bash
git add scripts/notify.sh
git commit -m "feat: macOS/Linux runtime helper (notify.sh)"
```

---

## Task 4: Windows installer `install.ps1` — install path

**Files:**
- Create: `install.ps1`

- [ ] **Step 1: Write `install.ps1` (install path only; uninstall added in Task 5)**

```powershell
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$RepoRaw    = 'https://raw.githubusercontent.com/CHANGEME/claude-notifier/main'
$HelperName = 'notify.ps1'
$HomeDir    = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
$InstallDir = Join-Path $HomeDir '.claude-notifier'
$HelperDest = Join-Path $InstallDir $HelperName
$SettingsDir  = Join-Path $HomeDir '.claude'
$SettingsPath = Join-Path $SettingsDir 'settings.json'

function Install-Helper {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    if ($env:CLAUDE_NOTIFIER_SOURCE) {
        $src = Join-Path $env:CLAUDE_NOTIFIER_SOURCE "scripts/$HelperName"
        if (-not (Test-Path $src)) { throw "CLAUDE_NOTIFIER_SOURCE set but $src not found" }
        Copy-Item -Force $src $HelperDest
    } else {
        $url = "$RepoRaw/scripts/$HelperName"
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $HelperDest
    }
    Write-Host "✓ Installed helper to $HelperDest"
}

function Read-Settings {
    if (-not (Test-Path $SettingsPath)) { return [ordered]@{} }
    $raw = Get-Content -Raw -Path $SettingsPath
    if ([string]::IsNullOrWhiteSpace($raw)) { return [ordered]@{} }
    try {
        return $raw | ConvertFrom-Json -AsHashtable
    } catch {
        throw "Failed to parse ${SettingsPath}: $_`nAborting without changes."
    }
}

function Write-Settings($obj) {
    New-Item -ItemType Directory -Force -Path $SettingsDir | Out-Null
    $tmp = "$SettingsPath.tmp"
    ($obj | ConvertTo-Json -Depth 32) | Set-Content -Path $tmp -Encoding UTF8
    Move-Item -Force $tmp $SettingsPath
}

function Build-HookEntry([string]$EventName) {
    return @{
        hooks = @(@{
            type    = 'command'
            shell   = 'powershell'
            async   = $true
            command = "& `"`$HOME\.claude-notifier\notify.ps1`" -Event $EventName"
        })
    }
}

function Merge-Hook($settings, [string]$EventName) {
    if (-not $settings.ContainsKey('hooks')) { $settings['hooks'] = @{} }
    if (-not $settings['hooks'].ContainsKey($EventName)) { $settings['hooks'][$EventName] = @() }

    # Remove any existing claude-notifier entries (idempotent re-install)
    $filtered = @()
    foreach ($group in $settings['hooks'][$EventName]) {
        $groupHooks = @()
        foreach ($h in $group['hooks']) {
            if (-not ($h['command'] -and ($h['command'] -match 'claude-notifier'))) {
                $groupHooks += $h
            }
        }
        if ($groupHooks.Count -gt 0) {
            $group['hooks'] = $groupHooks
            $filtered += $group
        }
    }
    $filtered += Build-HookEntry $EventName
    $settings['hooks'][$EventName] = $filtered
}

function Install-Hooks {
    $settings = Read-Settings
    Merge-Hook $settings 'Stop'
    Merge-Hook $settings 'Notification'
    Write-Settings $settings
    Write-Host "✓ Patched $SettingsPath"
}

if ($Uninstall) {
    # Stub — implemented in Task 5
    throw "Uninstall not yet implemented."
}

Install-Helper
Install-Hooks
Write-Host ""
Write-Host "claude-notifier installed. Restart Claude Code or run /hooks to load the new settings."
```

- [ ] **Step 2: Dry-run test with isolated HOME**

```powershell
$TMPHOME = (New-Item -ItemType Directory -Path "$env:TEMP\cn-$(Get-Random)").FullName
$oldHome = $env:HOME; $oldUP = $env:USERPROFILE
$env:HOME = $TMPHOME; $env:USERPROFILE = $TMPHOME
$env:CLAUDE_NOTIFIER_SOURCE = (Get-Location).Path
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
Get-Content "$TMPHOME\.claude\settings.json"
Test-Path "$TMPHOME\.claude-notifier\notify.ps1"
$env:HOME = $oldHome; $env:USERPROFILE = $oldUP
Remove-Item Env:\CLAUDE_NOTIFIER_SOURCE
Remove-Item $TMPHOME -Recurse -Force
```
Expected: `settings.json` contains `hooks.Stop` and `hooks.Notification` each with one entry calling `notify.ps1`. Helper exists at `$TMPHOME\.claude-notifier\notify.ps1`.

- [ ] **Step 3: Test idempotency (re-run, should not duplicate)**

```powershell
# With same TMPHOME still set up
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
# Then inspect
(Get-Content "$TMPHOME\.claude\settings.json" | ConvertFrom-Json).hooks.Stop[0].hooks.Count
```
Expected: count is 1, not 2 or more.

- [ ] **Step 4: Test merge preserves other hooks**

```powershell
# Set up pre-existing hook
$pre = @{
    hooks = @{
        Stop = @(@{
            hooks = @(@{ type = 'command'; command = 'echo other-tool' })
        })
    }
} | ConvertTo-Json -Depth 32
New-Item -ItemType Directory -Force -Path "$TMPHOME\.claude" | Out-Null
Set-Content -Path "$TMPHOME\.claude\settings.json" -Value $pre -Encoding UTF8
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
Get-Content "$TMPHOME\.claude\settings.json"
```
Expected: `hooks.Stop` has two entries — the original `echo other-tool` and the new claude-notifier call. Neither is lost.

- [ ] **Step 5: Commit**

```bash
git add install.ps1
git commit -m "feat: Windows installer (install path)"
```

---

## Task 5: Windows installer — uninstall path

**Files:**
- Modify: `install.ps1`

- [ ] **Step 1: Replace the `if ($Uninstall) { throw ... }` stub with real implementation**

Insert before `Install-Helper` / `Install-Hooks` call:

```powershell
function Uninstall-Hooks {
    if (-not (Test-Path $SettingsPath)) {
        Write-Host "No settings.json found; nothing to unpatch."
        return
    }
    $settings = Read-Settings
    if (-not $settings.ContainsKey('hooks')) {
        Write-Host "No hooks section found; nothing to remove."
        return
    }
    foreach ($eventName in @('Stop','Notification')) {
        if (-not $settings['hooks'].ContainsKey($eventName)) { continue }
        $keptGroups = @()
        foreach ($group in $settings['hooks'][$eventName]) {
            $keptHooks = @()
            foreach ($h in $group['hooks']) {
                if (-not ($h['command'] -and ($h['command'] -match 'claude-notifier'))) {
                    $keptHooks += $h
                }
            }
            if ($keptHooks.Count -gt 0) {
                $group['hooks'] = $keptHooks
                $keptGroups += $group
            }
        }
        if ($keptGroups.Count -eq 0) {
            $settings['hooks'].Remove($eventName)
        } else {
            $settings['hooks'][$eventName] = $keptGroups
        }
    }
    if ($settings['hooks'].Count -eq 0) {
        $settings.Remove('hooks')
    }
    Write-Settings $settings
    Write-Host "✓ Removed claude-notifier hooks from $SettingsPath"
}

function Uninstall-Helper {
    if (Test-Path $InstallDir) {
        Remove-Item -Recurse -Force $InstallDir
        Write-Host "✓ Removed $InstallDir"
    }
}
```

Then replace the earlier `if ($Uninstall) { throw ... }` block with:

```powershell
if ($Uninstall) {
    Uninstall-Hooks
    Uninstall-Helper
    Write-Host ""
    Write-Host "claude-notifier uninstalled."
    exit 0
}
```

- [ ] **Step 2: Test uninstall removes our hook but keeps others**

```powershell
$TMPHOME = (New-Item -ItemType Directory -Path "$env:TEMP\cn-$(Get-Random)").FullName
$env:HOME = $TMPHOME; $env:USERPROFILE = $TMPHOME
$env:CLAUDE_NOTIFIER_SOURCE = (Get-Location).Path

# Pre-seed with an unrelated hook
$pre = @{ hooks = @{ Stop = @(@{ hooks = @(@{ type='command'; command='echo other-tool' }) }) } } | ConvertTo-Json -Depth 32
New-Item -ItemType Directory -Force -Path "$TMPHOME\.claude" | Out-Null
Set-Content -Path "$TMPHOME\.claude\settings.json" -Value $pre -Encoding UTF8

# Install, then uninstall
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Uninstall

# Verify: only the other-tool hook remains, Notification key removed
Get-Content "$TMPHOME\.claude\settings.json"
Test-Path "$TMPHOME\.claude-notifier"

Remove-Item $TMPHOME -Recurse -Force
Remove-Item Env:\CLAUDE_NOTIFIER_SOURCE
```
Expected: `settings.json` has `hooks.Stop` with one entry (`echo other-tool`), no `hooks.Notification`. `~/.claude-notifier` directory is gone.

- [ ] **Step 3: Test uninstall is safe when nothing is installed**

```powershell
$TMPHOME = (New-Item -ItemType Directory -Path "$env:TEMP\cn-$(Get-Random)").FullName
$env:HOME = $TMPHOME; $env:USERPROFILE = $TMPHOME
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Uninstall
Remove-Item $TMPHOME -Recurse -Force
```
Expected: prints "No settings.json found; nothing to unpatch." and exits 0.

- [ ] **Step 4: Commit**

```bash
git add install.ps1
git commit -m "feat: Windows installer uninstall path"
```

---

## Task 6: macOS/Linux installer `install.sh` — install path

**Files:**
- Create: `install.sh`

Requires `jq`. Document this in README. On Ubuntu: `apt install jq`; on macOS with brew: `brew install jq`. If absent, script aborts with install hint.

- [ ] **Step 1: Write `install.sh` (install path; uninstall added in Task 7)**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/CHANGEME/claude-notifier/main"
HELPER_NAME="notify.sh"
INSTALL_DIR="$HOME/.claude-notifier"
HELPER_DEST="$INSTALL_DIR/$HELPER_NAME"
SETTINGS_DIR="$HOME/.claude"
SETTINGS_PATH="$SETTINGS_DIR/settings.json"

MODE="install"
for arg in "$@"; do
    case "$arg" in
        --uninstall) MODE="uninstall" ;;
        *) echo "usage: install.sh [--uninstall]" >&2; exit 2 ;;
    esac
done

require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "error: jq is required. Install with:" >&2
        echo "  macOS:  brew install jq" >&2
        echo "  Debian: sudo apt install jq" >&2
        echo "  Fedora: sudo dnf install jq" >&2
        exit 1
    fi
}

install_helper() {
    mkdir -p "$INSTALL_DIR"
    if [ -n "${CLAUDE_NOTIFIER_SOURCE:-}" ]; then
        local src="$CLAUDE_NOTIFIER_SOURCE/scripts/$HELPER_NAME"
        [ -f "$src" ] || { echo "CLAUDE_NOTIFIER_SOURCE set but $src not found" >&2; exit 1; }
        cp "$src" "$HELPER_DEST"
    else
        curl -fsSL "$REPO_RAW/scripts/$HELPER_NAME" -o "$HELPER_DEST"
    fi
    chmod +x "$HELPER_DEST"
    echo "✓ Installed helper to $HELPER_DEST"
}

read_settings() {
    if [ ! -f "$SETTINGS_PATH" ]; then
        echo "{}"
        return
    fi
    if ! jq empty "$SETTINGS_PATH" 2>/dev/null; then
        echo "error: $SETTINGS_PATH is not valid JSON. Aborting without changes." >&2
        exit 1
    fi
    cat "$SETTINGS_PATH"
}

write_settings() {
    local content="$1"
    mkdir -p "$SETTINGS_DIR"
    local tmp="$SETTINGS_PATH.tmp"
    printf '%s\n' "$content" > "$tmp"
    mv "$tmp" "$SETTINGS_PATH"
}

install_hooks() {
    local current
    current="$(read_settings)"
    local updated
    updated=$(printf '%s' "$current" | jq '
        def cn_entry($ev):
            { hooks: [{
                type: "command",
                shell: "bash",
                async: true,
                command: "\"$HOME/.claude-notifier/notify.sh\" " + $ev
            }] };
        def scrub($ev):
            (.hooks[$ev] // [])
            | map(.hooks |= map(select((.command // "") | contains("claude-notifier") | not)))
            | map(select(.hooks | length > 0));
        .hooks //= {}
        | .hooks.Stop         = (scrub("Stop")         + [cn_entry("Stop")])
        | .hooks.Notification = (scrub("Notification") + [cn_entry("Notification")])
    ')
    write_settings "$updated"
    echo "✓ Patched $SETTINGS_PATH"
}

if [ "$MODE" = "install" ]; then
    require_jq
    install_helper
    install_hooks
    echo ""
    echo "claude-notifier installed. Restart Claude Code or run /hooks to load the new settings."
fi
```

- [ ] **Step 2: Make executable**

```bash
chmod +x install.sh
```

- [ ] **Step 3: Dry-run test with isolated HOME**

```bash
TMPHOME=$(mktemp -d)
HOME="$TMPHOME" CLAUDE_NOTIFIER_SOURCE="$PWD" bash install.sh
cat "$TMPHOME/.claude/settings.json"
ls "$TMPHOME/.claude-notifier/"
rm -rf "$TMPHOME"
```
Expected: `settings.json` has `hooks.Stop` and `hooks.Notification` each with one entry. `notify.sh` exists in `.claude-notifier`.

- [ ] **Step 4: Test idempotency and merge preservation**

```bash
TMPHOME=$(mktemp -d)
mkdir -p "$TMPHOME/.claude"
cat > "$TMPHOME/.claude/settings.json" <<'EOF'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo other-tool"}]}]}}
EOF

HOME="$TMPHOME" CLAUDE_NOTIFIER_SOURCE="$PWD" bash install.sh
HOME="$TMPHOME" CLAUDE_NOTIFIER_SOURCE="$PWD" bash install.sh  # second run

jq '.hooks.Stop | length' "$TMPHOME/.claude/settings.json"
jq '.hooks.Stop[0].hooks[0].command' "$TMPHOME/.claude/settings.json"
rm -rf "$TMPHOME"
```
Expected: `hooks.Stop | length` is 2 (other-tool + claude-notifier). First entry is `echo other-tool`. Running install twice doesn't grow the array further.

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "feat: macOS/Linux installer (install path)"
```

---

## Task 7: macOS/Linux installer — uninstall path

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add `uninstall_hooks` and `uninstall_helper` functions before the final if/fi**

```bash
uninstall_hooks() {
    if [ ! -f "$SETTINGS_PATH" ]; then
        echo "No settings.json found; nothing to unpatch."
        return
    fi
    if ! jq empty "$SETTINGS_PATH" 2>/dev/null; then
        echo "error: $SETTINGS_PATH is not valid JSON. Aborting." >&2
        exit 1
    fi
    local updated
    updated=$(jq '
        def scrub($ev):
            (.hooks[$ev] // [])
            | map(.hooks |= map(select((.command // "") | contains("claude-notifier") | not)))
            | map(select(.hooks | length > 0));
        if (.hooks // null) == null then .
        else
            .hooks.Stop         = scrub("Stop")
            | .hooks.Notification = scrub("Notification")
            | (if (.hooks.Stop         | length) == 0 then del(.hooks.Stop)         else . end)
            | (if (.hooks.Notification | length) == 0 then del(.hooks.Notification) else . end)
            | (if (.hooks | length)             == 0 then del(.hooks)              else . end)
        end
    ' "$SETTINGS_PATH")
    write_settings "$updated"
    echo "✓ Removed claude-notifier hooks from $SETTINGS_PATH"
}

uninstall_helper() {
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
        echo "✓ Removed $INSTALL_DIR"
    fi
}
```

- [ ] **Step 2: Replace the final `if [ "$MODE" = "install" ]; then ... fi` block with**

```bash
case "$MODE" in
    install)
        require_jq
        install_helper
        install_hooks
        echo ""
        echo "claude-notifier installed. Restart Claude Code or run /hooks to load the new settings."
        ;;
    uninstall)
        require_jq
        uninstall_hooks
        uninstall_helper
        echo ""
        echo "claude-notifier uninstalled."
        ;;
esac
```

- [ ] **Step 3: Test uninstall preserves other hooks**

```bash
TMPHOME=$(mktemp -d)
mkdir -p "$TMPHOME/.claude"
cat > "$TMPHOME/.claude/settings.json" <<'EOF'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo other-tool"}]}]}}
EOF
HOME="$TMPHOME" CLAUDE_NOTIFIER_SOURCE="$PWD" bash install.sh
HOME="$TMPHOME" CLAUDE_NOTIFIER_SOURCE="$PWD" bash install.sh --uninstall

cat "$TMPHOME/.claude/settings.json"
[ ! -d "$TMPHOME/.claude-notifier" ] && echo "helper dir removed ✓"
rm -rf "$TMPHOME"
```
Expected: `settings.json` has only the `echo other-tool` hook under `hooks.Stop`, no `hooks.Notification`. `claude-notifier` dir gone.

- [ ] **Step 4: Test uninstall is safe when nothing is installed**

```bash
TMPHOME=$(mktemp -d)
HOME="$TMPHOME" bash install.sh --uninstall
rm -rf "$TMPHOME"
```
Expected: prints "No settings.json found; nothing to unpatch." and exits 0.

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "feat: macOS/Linux installer uninstall path"
```

---

## Task 8: README.md (English)

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write `README.md`**

```markdown
# claude-notifier

Play a system sound and show a desktop toast whenever Claude Code finishes a task or asks you a question. Cross-platform. One-line install. No dependencies.

![demo](./assets/demo.gif)

> 🇹🇷 **Türkçe:** [README.tr.md](./README.tr.md)

## Install

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/CHANGEME/claude-notifier/main/install.ps1 | iex
```

**macOS / Linux (requires `jq`):**

```bash
curl -fsSL https://raw.githubusercontent.com/CHANGEME/claude-notifier/main/install.sh | bash
```

Open a new Claude Code session or run `/hooks` to load the new settings.

## How it works

The installer drops a tiny helper script in `~/.claude-notifier/` and adds two hooks to `~/.claude/settings.json` — one for the `Stop` event (task complete) and one for `Notification` (Claude needs attention). Existing hooks are preserved.

The runtime helper picks the right API per platform: `SystemSounds` + WinRT toast on Windows, `afplay` + `osascript` on macOS, `paplay` + `notify-send` on Linux.

## Customize

All configuration is through environment variables — set them in your shell or in `~/.claude/settings.json` `env` field.

| Variable                     | Values                    | Default               | Purpose                                      |
|------------------------------|---------------------------|-----------------------|----------------------------------------------|
| `CLAUDE_NOTIFIER_LANG`       | `en`, `tr`                | `en`                  | Message language                             |
| `CLAUDE_NOTIFIER_EVENTS`     | `stop`, `notification`    | `stop,notification`   | Which events trigger notifications (CSV)     |
| `CLAUDE_NOTIFIER_SOUND`      | `0`, `1`                  | `1`                   | Enable/disable sound                         |
| `CLAUDE_NOTIFIER_TOAST`      | `0`, `1`                  | `1`                   | Enable/disable toast                         |

Example — silent mode, only trigger on questions, Turkish text:

```json
{
  "env": {
    "CLAUDE_NOTIFIER_SOUND": "0",
    "CLAUDE_NOTIFIER_EVENTS": "notification",
    "CLAUDE_NOTIFIER_LANG": "tr"
  }
}
```

## Uninstall

**Windows:**

```powershell
irm https://raw.githubusercontent.com/CHANGEME/claude-notifier/main/install.ps1 -OutFile $env:TEMP\cn.ps1; & $env:TEMP\cn.ps1 -Uninstall; Remove-Item $env:TEMP\cn.ps1
```

**macOS / Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/CHANGEME/claude-notifier/main/install.sh | bash -s -- --uninstall
```

Uninstall removes only `claude-notifier`'s hook entries and its helper directory. Any other hooks you've configured are preserved.

## Security — want to read before you run?

This project uses the `curl | bash` install pattern. If you prefer to inspect before running:

```bash
curl -fsSL https://raw.githubusercontent.com/CHANGEME/claude-notifier/main/install.sh -o install.sh
less install.sh
bash install.sh
```

## Requirements

- **Windows:** Windows 10 build 19041+ or Windows 11, PowerShell 5.1+
- **macOS:** macOS 12+ (Monterey or newer)
- **Linux:** bash, `jq`, and a notification daemon (`notify-send` via `libnotify-bin`); sound via `pulseaudio` or `alsa-utils`

## Troubleshooting

- **"Nothing happened after install"** → open `/hooks` once in Claude Code, or restart the CLI. The hook watcher picks up settings changes on next reload.
- **Linux: sound but no toast** → install `libnotify-bin` (`sudo apt install libnotify-bin`)
- **Windows: toast doesn't show, sound works** → make sure Focus Assist isn't blocking notifications

## Contributing

PRs welcome. Keep it dependency-free and under ~200 lines per script.

## License

MIT — see [LICENSE](./LICENSE).
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: English README"
```

---

## Task 9: README.tr.md (Turkish)

**Files:**
- Create: `README.tr.md`

- [ ] **Step 1: Write `README.tr.md`**

```markdown
# claude-notifier

Claude Code bir işi bitirdiğinde ya da sana bir soru sorduğunda sistem sesi çalar ve masaüstü bildirimi gösterir. Windows, macOS, Linux. Tek satır kurulum. Bağımlılık yok.

![demo](./assets/demo.gif)

> 🇬🇧 **English:** [README.md](./README.md)

## Kurulum

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/CHANGEME/claude-notifier/main/install.ps1 | iex
```

**macOS / Linux (`jq` gerekir):**

```bash
curl -fsSL https://raw.githubusercontent.com/CHANGEME/claude-notifier/main/install.sh | bash
```

Yeni bir Claude Code oturumu aç ya da `/hooks` komutunu çalıştır.

## Nasıl çalışır

Installer `~/.claude-notifier/` altına küçük bir helper script koyar ve `~/.claude/settings.json`'a iki hook ekler — biri `Stop` (iş bitti) event'i için, diğeri `Notification` (Claude dikkatini bekliyor) event'i için. Mevcut hook'larına dokunmaz.

Runtime helper her platformda doğru API'yi seçer: Windows'ta `SystemSounds` + WinRT toast, macOS'ta `afplay` + `osascript`, Linux'ta `paplay` + `notify-send`.

## Özelleştirme

Tüm ayarlar environment variable üzerinden — shell'inde veya `~/.claude/settings.json` içindeki `env` alanında tanımlayabilirsin.

| Değişken                     | Değerler                  | Varsayılan            | Amaç                                         |
|------------------------------|---------------------------|-----------------------|----------------------------------------------|
| `CLAUDE_NOTIFIER_LANG`       | `en`, `tr`                | `en`                  | Mesaj dili                                   |
| `CLAUDE_NOTIFIER_EVENTS`     | `stop`, `notification`    | `stop,notification`   | Hangi event'ler bildirim tetiklesin (CSV)    |
| `CLAUDE_NOTIFIER_SOUND`      | `0`, `1`                  | `1`                   | Ses aç/kapa                                  |
| `CLAUDE_NOTIFIER_TOAST`      | `0`, `1`                  | `1`                   | Toast aç/kapa                                |

Örnek — sessiz mod, sadece sorularda tetiklen, Türkçe mesaj:

```json
{
  "env": {
    "CLAUDE_NOTIFIER_SOUND": "0",
    "CLAUDE_NOTIFIER_EVENTS": "notification",
    "CLAUDE_NOTIFIER_LANG": "tr"
  }
}
```

## Kaldırma

**Windows:**

```powershell
irm https://raw.githubusercontent.com/CHANGEME/claude-notifier/main/install.ps1 -OutFile $env:TEMP\cn.ps1; & $env:TEMP\cn.ps1 -Uninstall; Remove-Item $env:TEMP\cn.ps1
```

**macOS / Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/CHANGEME/claude-notifier/main/install.sh | bash -s -- --uninstall
```

Uninstall yalnızca `claude-notifier`'ın hook entry'lerini ve helper klasörünü siler. Diğer hook'ların olduğu gibi kalır.

## Güvenlik — çalıştırmadan önce okumak ister misin?

Bu proje `curl | bash` kalıbını kullanıyor. İstersen önce oku:

```bash
curl -fsSL https://raw.githubusercontent.com/CHANGEME/claude-notifier/main/install.sh -o install.sh
less install.sh
bash install.sh
```

## Gereksinimler

- **Windows:** Windows 10 build 19041+ veya Windows 11, PowerShell 5.1+
- **macOS:** macOS 12+ (Monterey veya üzeri)
- **Linux:** bash, `jq`, bildirim daemon'ı (`libnotify-bin` üzerinden `notify-send`); ses için `pulseaudio` ya da `alsa-utils`

## Sorun giderme

- **"Kurdum, bir şey olmadı"** → Claude Code'da bir kez `/hooks` aç, ya da CLI'ı yeniden başlat. Hook watcher ayar değişikliklerini reload'ta yakalar.
- **Linux: ses var ama toast yok** → `sudo apt install libnotify-bin`
- **Windows: toast çıkmıyor ama ses var** → Focus Assist bildirimleri engelliyor olabilir

## Katkı

PR'lar açık. Bağımlılık eklemeden, script başı ~200 satır sınırını koru.

## Lisans

MIT — bkz. [LICENSE](./LICENSE).
```

- [ ] **Step 2: Commit**

```bash
git add README.tr.md
git commit -m "docs: Turkish README"
```

---

## Task 10: LICENSE (MIT)

**Files:**
- Create: `LICENSE`

- [ ] **Step 1: Write `LICENSE`**

Replace `<year>` with `2026` and `<your name>` with the user's preferred display name (ask the user; default "Murat Bilginer").

```
MIT License

Copyright (c) 2026 Murat Bilginer

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Commit**

```bash
git add LICENSE
git commit -m "chore: add MIT license"
```

---

## Task 11: Lint CI workflow

**Files:**
- Create: `.github/workflows/lint.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: lint

on:
  push:
    branches: [main]
  pull_request:

jobs:
  shellcheck:
    name: shellcheck
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run shellcheck
        run: |
          sudo apt-get update && sudo apt-get install -y shellcheck
          shellcheck install.sh scripts/notify.sh

  psscriptanalyzer:
    name: PSScriptAnalyzer
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install PSScriptAnalyzer
        shell: pwsh
        run: Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
      - name: Analyze
        shell: pwsh
        run: |
          $issues = Invoke-ScriptAnalyzer -Path install.ps1, scripts/notify.ps1 -Severity Warning,Error
          if ($issues) { $issues | Format-Table -AutoSize; exit 1 }
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/lint.yml
git commit -m "ci: shellcheck and PSScriptAnalyzer workflow"
```

---

## Task 12: Live integration test on this Windows machine

This task exercises the real end-to-end flow on the host machine. Run all steps and report observed vs expected. Restore previous settings.json at the end.

**Files:**
- Reads: `~/.claude/settings.json`

- [ ] **Step 1: Back up current settings.json**

```powershell
Copy-Item $env:USERPROFILE\.claude\settings.json $env:USERPROFILE\.claude\settings.json.precn-backup
```

- [ ] **Step 2: Remove the inline hooks that were set up earlier in this project**

Open `C:\Users\mrt_b\.claude\settings.json` in an editor and delete the entire `"hooks": { ... }` block that was added earlier. Save.

- [ ] **Step 3: Run the installer against the real HOME using local source**

```powershell
$env:CLAUDE_NOTIFIER_SOURCE = "C:\Users\mrt_b\claude-notifier"
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\mrt_b\claude-notifier\install.ps1
Remove-Item Env:\CLAUDE_NOTIFIER_SOURCE
```
Expected: prints "✓ Installed helper to C:\Users\mrt_b\.claude-notifier\notify.ps1" and "✓ Patched C:\Users\mrt_b\.claude\settings.json".

- [ ] **Step 4: Verify settings.json shape**

```powershell
(Get-Content $env:USERPROFILE\.claude\settings.json -Raw | ConvertFrom-Json).hooks.Stop[0].hooks[0].command
(Get-Content $env:USERPROFILE\.claude\settings.json -Raw | ConvertFrom-Json).hooks.Notification[0].hooks[0].command
```
Expected: both print a command ending in `notify.ps1" -Event Stop` / `-Event Notification`.

- [ ] **Step 5: Fire the helper directly to confirm it works standalone**

```powershell
& "$env:USERPROFILE\.claude-notifier\notify.ps1" -Event Stop
```
Expected: hear Asterisk sound, see "Task complete" toast.

- [ ] **Step 6: End this Claude Code session (exit or `/clear`) to let the Stop hook fire through the real event**

The Stop event fires when Claude finishes. The next user-driven interaction that ends with Claude stopping will trigger it. If this session was started before the new settings were written, a `/hooks` visit or restart is needed first.

Expected on next Stop: sound + toast.

- [ ] **Step 7: Run uninstall and verify cleanup**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\mrt_b\claude-notifier\install.ps1 -Uninstall
Test-Path $env:USERPROFILE\.claude-notifier
(Get-Content $env:USERPROFILE\.claude\settings.json -Raw | ConvertFrom-Json).hooks
```
Expected: `~/.claude-notifier` absent; `hooks` key either absent or has no `Stop`/`Notification` entries from claude-notifier.

- [ ] **Step 8: Restore original settings.json**

```powershell
Move-Item -Force $env:USERPROFILE\.claude\settings.json.precn-backup $env:USERPROFILE\.claude\settings.json
```

- [ ] **Step 9: Commit any test-driven fixes**

If any script changed during testing:
```bash
git add -u
git commit -m "fix: <what changed> discovered in live test"
```

Otherwise nothing to commit for this task.

---

## Task 13: Demo GIF capture (optional but strongly recommended for LinkedIn)

**Files:**
- Create: `assets/demo.gif`

This is a one-person creative task; the engineer records it manually.

- [ ] **Step 1: Install ScreenToGif (Windows) from https://www.screentogif.com/**

- [ ] **Step 2: Plan the 15-20 second take**

Frames to capture:
1. Clean terminal
2. Type/paste the install one-liner, press Enter
3. ✓ Installed output
4. Open Claude Code, give a trivial prompt (e.g., "echo hello")
5. When Claude finishes, toast appears in lower-right corner
6. End

- [ ] **Step 3: Record, trim, export**

Export as GIF, target ≤2 MB. Reduce FPS to 12-15 if file is too large.

- [ ] **Step 4: Save and commit**

```bash
mv <wherever-you-exported>/demo.gif C:\Users\mrt_b\claude-notifier\assets\demo.gif
git add assets/demo.gif
git commit -m "docs: demo gif"
```

---

## Task 14: Push to GitHub

**Files:**
- No new files.

- [ ] **Step 1: Create the repo on GitHub**

Option A — via `gh` CLI (if installed and authenticated):

```bash
gh repo create claude-notifier --public --source=. --remote=origin --description "Desktop sound + toast when Claude Code finishes a task or asks a question. Cross-platform. One-line install."
```

Option B — via web UI: create empty public repo `claude-notifier` at github.com, then:

```bash
git remote add origin https://github.com/<user>/claude-notifier.git
```

- [ ] **Step 2: Replace `CHANGEME` with the actual GitHub username in all files**

Files containing `CHANGEME`: `install.ps1`, `install.sh`, `README.md`, `README.tr.md`.

```bash
# On Linux/macOS/WSL:
grep -rl CHANGEME . | xargs sed -i 's/CHANGEME/<user>/g'
```

On Windows PowerShell:
```powershell
Get-ChildItem -Recurse -File -Include *.ps1,*.sh,*.md | ForEach-Object {
    (Get-Content $_.FullName -Raw) -replace 'CHANGEME','<user>' | Set-Content $_.FullName -Encoding UTF8
}
```

- [ ] **Step 3: Commit the URL change**

```bash
git add -u
git commit -m "chore: set GitHub username in install URLs"
```

- [ ] **Step 4: Push**

```bash
git push -u origin main
```

- [ ] **Step 5: Smoke-test the published install**

On the same machine (or a fresh one):

```powershell
irm https://raw.githubusercontent.com/<user>/claude-notifier/main/install.ps1 | iex
```

Expected: installer runs, downloads helper from GitHub raw, patches settings.

- [ ] **Step 6: Add topics on GitHub**

Via `gh`:
```bash
gh repo edit --add-topic claude-code,claude,notifications,hooks,powershell,bash,cross-platform,desktop-notifications
```

---

## Post-implementation: LinkedIn post notes (not a task, just reference)

Draft a post around:
- Pain: Claude uzun sürerken başka sekmeye gidiyorsun, bittiğini kaçırıyorsun
- Fix: tek satır install, ses + toast, cross-platform
- Link to repo + demo GIF inline
- Keep it short, let the GIF do the work

---

## Self-review checklist

After plan is written:

1. **Spec coverage** — does every spec section have a task?
   - Repo layout ✓ Task 1 (skeleton) + Tasks 2-11 (each file)
   - Install flow ✓ Tasks 4, 6
   - Uninstall flow ✓ Tasks 5, 7
   - Runtime flow ✓ Tasks 2, 3
   - Hook structure ✓ Tasks 4, 6 (generation), Tasks 5, 7 (removal criterion)
   - Platform API map ✓ Tasks 2 (Win), 3 (mac/Linux)
   - Error handling ✓ covered in each task
   - Testing ✓ Tasks 4, 5, 6, 7 (unit-style with TMPHOME), Task 12 (live)
   - Documentation ✓ Tasks 8, 9, 10
   - Security note ✓ Task 8, 9
   - Demo GIF ✓ Task 13
2. **Placeholder scan** — `CHANGEME` in install URLs is intentional (replaced in Task 14). No TBD/TODO elsewhere.
3. **Type consistency** — helper paths, env var names, event names, command matching substring all consistent: `~/.claude-notifier/notify.{ps1,sh}`, `CLAUDE_NOTIFIER_*`, `Stop`/`Notification`, substring `claude-notifier` for merge/unmerge detection.
