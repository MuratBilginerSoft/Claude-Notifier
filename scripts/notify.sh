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

# --- Hook payload excerpt --------------------------------------------------
# Claude Code pipes a JSON payload to the hook's stdin. For Notification
# we surface .message; for Stop we dig into .transcript_path (JSONL) and
# pick the last assistant text. Any failure falls through silently and we
# fall back to the generic event message.
excerpt=""
if [ ! -t 0 ] && command -v jq >/dev/null 2>&1; then
    payload="$(cat)"
    if [ -n "$payload" ]; then
        if [ "$EVENT" = "Notification" ]; then
            excerpt="$(printf '%s' "$payload" | jq -r '.message // empty' 2>/dev/null || true)"
        else
            transcript="$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
            if [ -n "$transcript" ] && [ -f "$transcript" ]; then
                # Walk backwards through the transcript (last ~200 lines) and
                # return the text content of the most recent assistant message.
                excerpt="$(tail -n 200 "$transcript" 2>/dev/null \
                    | awk '{ a[NR]=$0 } END { for (i=NR;i>=1;i--) print a[i] }' \
                    | while IFS= read -r line; do
                        text="$(printf '%s' "$line" | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null)"
                        if [ -n "$text" ]; then printf '%s' "$text"; break; fi
                      done)"
            fi
        fi
        # Normalize whitespace + truncate to 200 characters.
        if [ -n "$excerpt" ]; then
            excerpt="$(printf '%s' "$excerpt" | tr '\n\r\t' '   ' | tr -s ' ')"
            if [ "${#excerpt}" -gt 200 ]; then
                excerpt="$(printf '%s' "$excerpt" | cut -c1-199)…"
            fi
        fi
    fi
fi


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

    app_name='Claude Notifier - BrainyTech'
    icon="$HOME/.claude-notifier/icon.png"

    # summary = event message (title line), body = excerpt when available
    summary="$msg"
    body="$excerpt"

    case "$os" in
        Darwin)
            # osascript's display notification needs a non-empty body string.
            [ -z "$body" ] && body=" "
            safe_summary=$(printf '%s' "$summary" | sed 's/\\/\\\\/g; s/"/\\"/g; s/`/\\`/g; s/\$/\\$/g')
            safe_body=$(printf '%s' "$body" | sed 's/\\/\\\\/g; s/"/\\"/g; s/`/\\`/g; s/\$/\\$/g')
            osascript -e "display notification \"$safe_body\" with title \"$safe_summary\"" 2>/dev/null || \
                echo "toast failed (osascript missing?)" >&2
            ;;
        Linux)
            if command -v notify-send >/dev/null 2>&1; then
                args=(-a "$app_name")
                [ -f "$icon" ] && args+=(-i "$icon")
                if [ -n "$body" ]; then
                    notify-send "${args[@]}" "$summary" "$body" 2>/dev/null || true
                else
                    notify-send "${args[@]}" "$summary" 2>/dev/null || true
                fi
            else
                echo "toast unavailable: install libnotify-bin (e.g., apt install libnotify-bin)" >&2
            fi
            ;;
    esac
}

play_sound
show_toast
exit 0
