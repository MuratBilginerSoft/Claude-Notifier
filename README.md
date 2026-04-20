# Claude-Notifier

Play a system sound and show a desktop toast whenever Claude Code finishes a task or asks you a question. Cross-platform. One-line install. No dependencies.

![demo](./assets/demo.gif)

> 🇹🇷 **Türkçe:** [README.tr.md](./README.tr.md)

## Install

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/MuratBilginerSoft/Claude-Notifier/main/install.ps1 | iex
```

**macOS / Linux (requires `jq`):**

```bash
curl -fsSL https://raw.githubusercontent.com/MuratBilginerSoft/Claude-Notifier/main/install.sh | bash
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
irm https://raw.githubusercontent.com/MuratBilginerSoft/Claude-Notifier/main/install.ps1 -OutFile $env:TEMP\cn.ps1; & $env:TEMP\cn.ps1 -Uninstall; Remove-Item $env:TEMP\cn.ps1
```

**macOS / Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/MuratBilginerSoft/Claude-Notifier/main/install.sh | bash -s -- --uninstall
```

Uninstall removes only `claude-notifier`'s hook entries and its helper directory. Any other hooks you've configured are preserved.

## Security — want to read before you run?

This project uses the `curl | bash` install pattern. If you prefer to inspect before running:

```bash
curl -fsSL https://raw.githubusercontent.com/MuratBilginerSoft/Claude-Notifier/main/install.sh -o install.sh
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
