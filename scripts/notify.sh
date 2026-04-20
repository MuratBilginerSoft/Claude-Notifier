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

    # Per-event overrides (paths to audio files). Empty/invalid falls through to defaults.
    if [ "$EVENT" = "Stop" ]; then custom="${CLAUDE_NOTIFIER_SOUND_STOP:-}"
    else                            custom="${CLAUDE_NOTIFIER_SOUND_NOTIFICATION:-}"
    fi
    if [ -n "$custom" ] && [ ! -f "$custom" ]; then
        echo "sound spec not found: $custom; using default" >&2
        custom=""
    fi

    case "$os" in
        Darwin)
            if [ -n "$custom" ]; then
                afplay "$custom" 2>/dev/null || true
                return 0
            fi
            if [ "$EVENT" = "Stop" ]; then sound=/System/Library/Sounds/Glass.aiff
            else                            sound=/System/Library/Sounds/Ping.aiff
            fi
            afplay "$sound" 2>/dev/null || true
            ;;
        Linux)
            if [ -n "$custom" ]; then
                if command -v paplay >/dev/null 2>&1 && paplay "$custom" 2>/dev/null; then return 0; fi
                if command -v aplay  >/dev/null 2>&1 && aplay  "$custom" 2>/dev/null; then return 0; fi
                # Fall through to defaults if custom couldn't be played.
            fi
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
            safe_msg=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g; s/`/\\`/g; s/\$/\\$/g')
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
