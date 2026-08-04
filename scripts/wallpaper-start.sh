#!/usr/bin/env bash
set -euo pipefail

LOG="${XDG_STATE_HOME:-$HOME/.local/state}/hyprland/wallpaper.log"
USER_WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
WAYPAPER_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/waypaper/config.ini"
FALLBACK_WALLPAPER="/usr/share/hypr/wall0.png"

mkdir -p "$(dirname "$LOG")"

first_user_wallpaper() {
    find "$USER_WALLPAPER_DIR" -maxdepth 3 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.avif' \) \
        2>/dev/null | sort | head -n 1
}

expand_path() {
    local path="$1"

    printf '%s\n' "${path/#\~/$HOME}"
}

configured_wallpaper() {
    local configured=""

    if [ -r "$WAYPAPER_CONFIG" ]; then
        configured=$(awk -F= '
            $1 ~ /^[[:space:]]*wallpaper[[:space:]]*$/ {
                value=$2
                sub(/^[[:space:]]*/, "", value)
                sub(/[[:space:]]*$/, "", value)
                configured=value
            }
            END {
                if (configured != "") print configured
            }
        ' "$WAYPAPER_CONFIG")
    fi

    configured=$(expand_path "$configured")
    [ -f "$configured" ] && printf '%s\n' "$configured"
}

monitor_names() {
    local monitors_json

    if command -v jq >/dev/null 2>&1 && monitors_json=$(hyprctl monitors -j 2>> "$LOG"); then
        printf '%s\n' "$monitors_json" | jq -r '.[].name // empty'
        return
    fi

    hyprctl monitors 2>> "$LOG" | awk '/^Monitor / { print $2 }'
}

apply_wallpaper() {
    local wallpaper="$1"
    local monitor
    local applied=1
    local found_monitor=1

    while IFS= read -r monitor; do
        [ -n "$monitor" ] || continue
        found_monitor=0
        if hyprctl hyprpaper wallpaper "$monitor,$wallpaper,fill" >> "$LOG" 2>&1; then
            applied=0
        fi
    done < <(monitor_names)

    if [ "$found_monitor" -ne 0 ]; then
        printf 'No Hyprland monitors found while applying wallpaper: %s\n' "$wallpaper" >> "$LOG"
        return 1
    fi

    return "$applied"
}

if ! pgrep -x hyprpaper >/dev/null; then
    hyprpaper >> "$LOG" 2>&1 &
    disown 2>/dev/null || true
    sleep 0.4
fi

wallpaper=$(configured_wallpaper)
[ -n "$wallpaper" ] || wallpaper=$(first_user_wallpaper)
[ -n "$wallpaper" ] || wallpaper="$FALLBACK_WALLPAPER"

apply_wallpaper "$wallpaper" || true
