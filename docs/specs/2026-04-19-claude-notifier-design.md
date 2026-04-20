# claude-notifier — Design Spec

**Date:** 2026-04-19
**Author:** muratbilginer09@gmail.com
**Status:** Approved for implementation

## Purpose

Cross-platform, one-line installable Claude Code hook set that plays a system sound and shows a desktop notification when:

- Claude finishes a task (`Stop` event)
- Claude asks a question or needs attention (`Notification` event)

Target distribution: GitHub repository, shared on LinkedIn. Primary audience: Claude Code users on Windows, macOS, Linux.

## Goals / Non-goals

**Goals**
- One-line install via `curl | bash` / `irm | iex`
- Works out of the box on Win11, macOS 12+, major Linux distros with a notification daemon
- Sane defaults, minimal env-var customization
- Clean uninstall that leaves existing hooks untouched
- No runtime dependencies beyond OS-native tooling

**Non-goals (v1)**
- Config file with custom sound paths, quiet hours, icon customization (future)
- Packaging to npm/brew/apt (future)
- GUI configurator
- Windows 10 below build 19041 support (toast API compatibility)

## Architecture

Two-layer separation:

1. **Installer** (`install.ps1`, `install.sh`) — runs once. Downloads runtime helper, patches `~/.claude/settings.json`, prints status.
2. **Runtime helper** (`scripts/notify.ps1`, `scripts/notify.sh`) — invoked by Claude Code hooks on each event. Reads env vars, plays sound, shows toast, exits 0.

### Repo layout

```
claude-notifier/
├── README.md                  # EN
├── README.tr.md               # TR
├── LICENSE                    # MIT
├── install.ps1                # Windows installer + uninstaller
├── install.sh                 # macOS/Linux installer + uninstaller
├── scripts/
│   ├── notify.ps1             # Windows runtime helper
│   └── notify.sh              # macOS/Linux runtime helper
├── assets/
│   └── demo.gif
└── .github/workflows/lint.yml # shellcheck + PSScriptAnalyzer (optional)
```

### Platform API map

| OS      | Sound                                                       | Toast                                 |
|---------|-------------------------------------------------------------|---------------------------------------|
| Windows | `[System.Media.SystemSounds]::Asterisk/Exclamation.Play()`  | WinRT `ToastNotificationManager`      |
| macOS   | `afplay /System/Library/Sounds/Glass.aiff`                  | `osascript -e 'display notification'` |
| Linux   | `paplay` → `aplay` → `printf '\a'` (fallback chain)         | `notify-send`                         |

If a required tool is missing on Linux (e.g., `notify-send` absent), runtime falls back to sound-only and writes a warning to stderr. Never fails in a way that blocks Claude.

## Install flow

```
user shell
  │ irm .../install.ps1 | iex   (or curl .../install.sh | bash)
  ▼
installer
  ├─ mkdir ~/.claude-notifier/
  ├─ download notify.{ps1|sh}  →  ~/.claude-notifier/
  ├─ read ~/.claude/settings.json  (create {} if absent)
  ├─ parse JSON  →  abort on parse error, leave file untouched
  ├─ merge Stop + Notification hook entries (skip if already claude-notifier)
  ├─ atomic write (temp file + rename)
  └─ print success + next steps
```

### Hook entries written to `settings.json`

**Windows:**
```json
{
  "hooks": {
    "Stop": [{
      "hooks": [{
        "type": "command",
        "shell": "powershell",
        "async": true,
        "command": "& \"$HOME\\.claude-notifier\\notify.ps1\" -Event Stop"
      }]
    }],
    "Notification": [{
      "hooks": [{
        "type": "command",
        "shell": "powershell",
        "async": true,
        "command": "& \"$HOME\\.claude-notifier\\notify.ps1\" -Event Notification"
      }]
    }]
  }
}
```

**macOS/Linux:** identical structure, `shell: "bash"`, command `"$HOME/.claude-notifier/notify.sh" Stop` / `Notification`.

Merge rule: if an event array already has entries, append alongside — never replace. Duplicate detection looks for the literal substring `claude-notifier` in `.command` and updates in place.

## Runtime flow

`notify.{ps1|sh} <Event>`:

1. Read env with defaults:
   - `CLAUDE_NOTIFIER_LANG` → `en`
   - `CLAUDE_NOTIFIER_EVENTS` → `stop,notification`
   - `CLAUDE_NOTIFIER_SOUND` → `1`
   - `CLAUDE_NOTIFIER_TOAST` → `1`
2. If `<Event>` not in enabled events, exit 0.
3. Select message (hardcoded table, two langs × two events):
   - `Stop` / en: "Task complete" — tr: "İş tamamlandı"
   - `Notification` / en: "Claude needs your attention" — tr: "Claude dikkatini bekliyor"
4. If sound enabled: play the OS-appropriate system sound per this table:

   | Event        | Windows                                   | macOS                                          | Linux (paplay path)                                                                 |
   |--------------|-------------------------------------------|------------------------------------------------|-------------------------------------------------------------------------------------|
   | Stop         | `[System.Media.SystemSounds]::Asterisk`   | `afplay /System/Library/Sounds/Glass.aiff`     | `paplay /usr/share/sounds/freedesktop/stereo/complete.oga`                          |
   | Notification | `[System.Media.SystemSounds]::Exclamation`| `afplay /System/Library/Sounds/Ping.aiff`      | `paplay /usr/share/sounds/freedesktop/stereo/message.oga`                           |

   Linux fallback chain if the freedesktop path is absent: try `/usr/share/sounds/alsa/Front_Center.wav` via `aplay`, finally `printf '\a'`.
5. If toast enabled: show toast with title "Claude Code" and selected message.
6. Wrap every action in try/catch — any failure logs to stderr and exits 0, never blocks Claude.

## Uninstall flow

Invocation:
- Windows: `irm .../install.ps1 | iex -Args "-Uninstall"` or `./install.ps1 -Uninstall`
- mac/Linux: `curl -fsSL .../install.sh | bash -s -- --uninstall`

Steps:
1. Read `settings.json`, filter out hook entries whose `command` contains `claude-notifier`.
2. If an event's `hooks` array is empty, remove the key. If the entire `hooks` object is empty, remove it.
3. Atomic write back.
4. Delete `~/.claude-notifier/`.
5. Print confirmation.

## Error handling summary

| Case                                            | Behavior                                                 |
|-------------------------------------------------|----------------------------------------------------------|
| `settings.json` is malformed JSON               | Abort, do not write, stderr error with path              |
| `settings.json` missing                         | Create with `{}`, proceed                                |
| Other hooks already on same event               | Append — never replace                                   |
| Re-install over existing claude-notifier hook   | Update in place (idempotent)                             |
| Linux `notify-send` absent                      | Sound only, stderr warning with install hint             |
| Runtime toast/sound throws                      | try/catch, stderr, exit 0                                |
| Helper path with spaces / unicode               | PS `& "..."` syntax; bash `"$HOME/..."` quoting; UTF-8   |
| Network failure during install                  | Abort with clear message before touching settings        |
| Windows PowerShell 5.1 vs 7                     | WinRT APIs work in both; tested on both                  |

## Testing

Manual matrix (no CI for functional tests in v1):

1. **Windows 11, PowerShell 5.1 and 7** — clean install → finish a prompt in Claude Code → sound + toast observed → `-Uninstall` → `settings.json` is clean (other hooks preserved) → `~/.claude-notifier/` removed.
2. **macOS 14** (if accessible — otherwise documented in README as "community-tested on macOS").
3. **Linux (Ubuntu 22.04 via WSL2 or VM)** — same matrix, then second pass with `notify-send` removed to verify sound-only fallback.

During test, temporarily prepend each helper with `echo "$(date) fired $1" >> /tmp/cn-fired.log` to observe firing, then remove before release.

Optional CI: `.github/workflows/lint.yml` runs `shellcheck` on `.sh` files and `Invoke-ScriptAnalyzer` on `.ps1`. No functional CI (requires GUI notification subsystem).

## Documentation

- **README.md (EN)** — demo GIF at top, one-liner install, env var table, uninstall, "how it works" (3-sentence overview), contributing, security note on `curl | bash` transparency.
- **README.tr.md** — same structure in Turkish.
- **LICENSE** — MIT.

### Security note (in README)

> This project uses the `curl | bash` install pattern. If you prefer to inspect before running:
> ```
> curl -fsSL https://raw.githubusercontent.com/<user>/claude-notifier/main/install.sh -o install.sh
> less install.sh
> bash install.sh
> ```

## Demo GIF

Produced with ScreenToGif (Windows) or Kap (macOS). Sequence:

1. Terminal with one-liner install command
2. ✓ Installed message
3. Open Claude Code, give a trivial prompt
4. When finished, toast appears in corner

Target: ≤20 seconds, ≤2 MB. Saved as `assets/demo.gif`, embedded at top of both READMEs.

## Future (out of scope for v1)

- `~/.claude-notifier/config.json` with custom sound file paths and per-event message overrides
- Quiet hours (silence toasts between configurable times)
- Custom app icon for Windows toast (requires registering an AppUserModelID and installing a shortcut)
- `brew tap` / `npm` / `winget` packaging
- Additional languages beyond EN/TR (PRs welcome)
