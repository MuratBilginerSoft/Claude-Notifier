#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/MuratBilginerSoft/Claude-Notifier/main"
HELPER_NAME="notify.sh"
INSTALL_DIR="$HOME/.claude-notifier"
HELPER_DEST="$INSTALL_DIR/$HELPER_NAME"
SETTINGS_DIR="$HOME/.claude"
SETTINGS_PATH="$SETTINGS_DIR/settings.json"

trap 'rm -f "$SETTINGS_PATH.tmp"' EXIT

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
        curl -fSL "$REPO_RAW/scripts/$HELPER_NAME" -o "$HELPER_DEST" \
            || { echo "error: failed to download $HELPER_NAME from $REPO_RAW" >&2; exit 1; }
    fi
    chmod +x "$HELPER_DEST"
    echo "[OK] Installed helper to $HELPER_DEST"

    # Icon is non-critical: if download fails, toasts still render without a logo.
    local icon_dest="$INSTALL_DIR/icon.png"
    if [ -n "${CLAUDE_NOTIFIER_SOURCE:-}" ]; then
        local icon_src="$CLAUDE_NOTIFIER_SOURCE/assets/icon.png"
        if [ -f "$icon_src" ]; then
            cp "$icon_src" "$icon_dest" && echo "[OK] Installed icon to $icon_dest"
        fi
    else
        if curl -fSL "$REPO_RAW/assets/icon.png" -o "$icon_dest" 2>/dev/null; then
            echo "[OK] Installed icon to $icon_dest"
        else
            echo "[WARN] Could not download icon from $REPO_RAW; toasts will render without a logo."
        fi
    fi
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
    echo "[OK] Patched $SETTINGS_PATH"
}

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
    echo "[OK] Removed claude-notifier hooks from $SETTINGS_PATH"
}

uninstall_helper() {
    if [ -d "$INSTALL_DIR" ]; then
        if rm -rf "$INSTALL_DIR"; then
            echo "[OK] Removed $INSTALL_DIR"
        else
            echo "error: failed to remove $INSTALL_DIR" >&2
            exit 1
        fi
    else
        echo "$INSTALL_DIR not found; skipping."
    fi
}

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
