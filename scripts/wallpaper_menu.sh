#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hyprland"
LOG="$STATE_DIR/wallpaper.log"
ROTATION_FLAG="$STATE_DIR/wallpaper-rotation.enabled"
ROTATION_PID="$STATE_DIR/wallpaper-rotation.pid"
WAYPAPER_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/waypaper/config.ini"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
WALLPAPER_DIRS=(
    "$HOME/Pictures/Wallpapers"
    "$HOME/Pictures/Wallpaper"
)
FALLBACK_WALLPAPER="/usr/share/hypr/wall0.png"
ROTATION_INTERVAL_SECONDS="${WALLPAPER_ROTATION_INTERVAL_SECONDS:-3600}"

mkdir -p "$STATE_DIR"

find_wallpapers() {
    local dir

    for dir in "${WALLPAPER_DIRS[@]}"; do
        [ -d "$dir" ] || continue
        find "$dir" -maxdepth 3 -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.avif' -o -iname '*.bmp' \)
    done 2>/dev/null | sort -u
}

display_name() {
    local path="$1"
    local name

    name=$(basename "$path")
    printf '%s' "${name%.*}"
}

expand_path() {
    local path="$1"

    printf '%s\n' "${path/#\~/$HOME}"
}

current_wallpaper() {
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

    if [ -n "$configured" ]; then
        printf '%s\n' "$configured"
    fi
}

ensure_hyprpaper() {
    if ! pgrep -x hyprpaper >/dev/null; then
        hyprpaper >> "$LOG" 2>&1 &
        disown 2>/dev/null || true
        sleep 0.4
    fi
}

restart_hyprpaper() {
    pkill -x hyprpaper 2>/dev/null || true
    sleep 0.2
    hyprpaper >> "$LOG" 2>&1 &
    disown 2>/dev/null || true
    sleep 0.5
}

update_waypaper_config() {
    local wallpaper="$1"
    local folder
    local monitor
    local tmp

    folder=$(dirname "$wallpaper")
    monitor=$(first_monitor)
    mkdir -p "$(dirname "$WAYPAPER_CONFIG")"

    if [ ! -r "$WAYPAPER_CONFIG" ]; then
        {
            printf '[Settings]\n'
            printf 'language = en\n'
            printf 'folder = %s\n' "$folder"
            printf 'wallpaper = %s\n' "$wallpaper"
            printf 'backend = hyprpaper\n'
            printf 'monitors = %s\n' "${monitor:-All}"
            printf 'fill = fill\n'
        } > "$WAYPAPER_CONFIG"
        return
    fi

    tmp=$(mktemp)
    awk -F= -v folder="$folder" -v wallpaper="$wallpaper" -v monitor="${monitor:-All}" '
        function key_name(raw) {
            key=raw
            sub(/^[[:space:]]*/, "", key)
            sub(/[[:space:]]*$/, "", key)
            return key
        }

        BEGIN { seen_folder=0; seen_wallpaper=0; seen_backend=0; seen_monitors=0 }

        key_name($1) == "folder" {
            if (!seen_folder) print "folder = " folder
            seen_folder=1
            next
        }

        key_name($1) == "wallpaper" {
            if (!seen_wallpaper) print "wallpaper = " wallpaper
            seen_wallpaper=1
            next
        }

        key_name($1) == "backend" {
            if (!seen_backend) print "backend = hyprpaper"
            seen_backend=1
            next
        }

        key_name($1) == "monitors" {
            if (!seen_monitors) print "monitors = " monitor
            seen_monitors=1
            next
        }

        { print }

        END {
            if (!seen_folder) print "folder = " folder
            if (!seen_wallpaper) print "wallpaper = " wallpaper
            if (!seen_backend) print "backend = hyprpaper"
            if (!seen_monitors) print "monitors = " monitor
        }
    ' "$WAYPAPER_CONFIG" > "$tmp"
    mv "$tmp" "$WAYPAPER_CONFIG"
}

monitor_names() {
    local monitors_json

    if command -v jq >/dev/null 2>&1 && monitors_json=$(hyprctl monitors -j 2>> "$LOG"); then
        printf '%s\n' "$monitors_json" | jq -r '.[].name // empty'
        return
    fi

    hyprctl monitors 2>> "$LOG" | awk '/^Monitor / { print $2 }'
}

first_monitor() {
    local monitor

    monitor=$(monitor_names | head -n 1)
    [ -n "$monitor" ] && printf '%s\n' "$monitor"
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

set_wallpaper() {
    local wallpaper
    local notify="${2:-yes}"

    wallpaper=$(expand_path "$1")

    if [ ! -f "$wallpaper" ]; then
        notify-send "Wallpaper" "File not found: $wallpaper"
        return 1
    fi

    ensure_hyprpaper
    if ! apply_wallpaper "$wallpaper"; then
        restart_hyprpaper
        if ! apply_wallpaper "$wallpaper"; then
            notify-send "Wallpaper" "Could not apply wallpaper. See $LOG"
            return 1
        fi
    fi

    update_waypaper_config "$wallpaper"
    if [ "$notify" = "yes" ]; then
        notify-send "Wallpaper" "$(display_name "$wallpaper")"
    fi
}

random_wallpaper() {
    local notify="${1:-yes}"
    local selected

    selected=$(find_wallpapers | shuf -n 1)
    if [ -z "$selected" ]; then
        selected="$FALLBACK_WALLPAPER"
    fi

    set_wallpaper "$selected" "$notify"
}

rotation_running() {
    local pid=""

    if [ -r "$ROTATION_PID" ]; then
        pid=$(cat "$ROTATION_PID")
    fi

    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

rotation_start() {
    if rotation_running; then
        return 0
    fi

    (
        while [ -e "$ROTATION_FLAG" ]; do
            sleep "$ROTATION_INTERVAL_SECONDS"
            [ -e "$ROTATION_FLAG" ] || break
            random_wallpaper no >> "$LOG" 2>&1 || true
        done
    ) >> "$LOG" 2>&1 &

    printf '%s\n' "$!" > "$ROTATION_PID"
}

rotation_stop() {
    local pid=""

    rm -f "$ROTATION_FLAG"
    if [ -r "$ROTATION_PID" ]; then
        pid=$(cat "$ROTATION_PID")
        [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    fi
    rm -f "$ROTATION_PID"
}

rotation_enable() {
    touch "$ROTATION_FLAG"
    rotation_start
    notify-send "Wallpaper" "Hourly rotation enabled"
}

rotation_disable() {
    rotation_stop
    notify-send "Wallpaper" "Hourly rotation disabled"
}

rotation_status() {
    if [ -e "$ROTATION_FLAG" ]; then
        printf 'enabled\n'
    else
        printf 'disabled\n'
    fi
}

preview_browser() {
    "$SCRIPT_DIR/quick-settings.sh" wallpaper >/dev/null 2>&1 &
}

menu() {
    local map_file
    local current
    local current_name
    local rotation
    local chosen
    local wallpaper

    map_file=$(mktemp)
    current=$(current_wallpaper)
    current_name="None"
    [ -n "$current" ] && current_name=$(display_name "$current")
    rotation=$(rotation_status)

    {
        printf '󰸉 Current: %s\n' "$current_name"
        if [ "$rotation" = "enabled" ]; then
            printf '󰔟 Disable hourly rotation\n'
        else
            printf '󰔟 Enable hourly rotation\n'
        fi
        printf '󰏫 Browse wallpapers with previews\n'
        printf ' Random wallpaper now\n'
        printf '%s\n' '--------------------'
    } > "$map_file"

    find_wallpapers | while IFS= read -r wallpaper; do
        if [ "$wallpaper" = "$current" ]; then
            printf '󰸉 [Active] %s\t%s\n' "$(display_name "$wallpaper")" "$wallpaper" >> "$map_file"
        else
            printf '󰸉 %s\t%s\n' "$(display_name "$wallpaper")" "$wallpaper" >> "$map_file"
        fi
    done

    chosen=$(cut -f1 "$map_file" | wofi --dmenu --prompt "Wallpaper: " --width 560 --lines 14 || true)

    if [ -z "$chosen" ] || [[ "$chosen" == *"----"* ]] || [[ "$chosen" == "󰸉 Current:"* ]] || [[ "$chosen" == "󰸉 [Active]"* ]]; then
        rm -f "$map_file"
        return 0
    fi

    case "$chosen" in
        "󰔟 Enable hourly rotation")
            rotation_enable
            ;;
        "󰔟 Disable hourly rotation")
            rotation_disable
            ;;
        " Random wallpaper now")
            random_wallpaper
            ;;
        "󰏫 Browse wallpapers with previews")
            preview_browser
            ;;
        *)
            wallpaper=$(awk -F '\t' -v choice="$chosen" '$1 == choice { print $2; exit }' "$map_file")
            [ -n "$wallpaper" ] && set_wallpaper "$wallpaper"
            ;;
    esac

    rm -f "$map_file"
}

case "${1:-menu}" in
    menu)
        menu
        ;;
    set)
        set_wallpaper "${2:?missing wallpaper path}"
        ;;
    random)
        random_wallpaper
        ;;
    preview)
        preview_browser
        ;;
    rotate-enable)
        rotation_enable
        ;;
    rotate-disable)
        rotation_disable
        ;;
    rotate-toggle)
        if [ "$(rotation_status)" = "enabled" ]; then
            rotation_disable
        else
            rotation_enable
        fi
        ;;
    rotate-start-if-enabled)
        [ -e "$ROTATION_FLAG" ] && rotation_start
        ;;
    rotate-status)
        rotation_status
        ;;
    list)
        find_wallpapers
        ;;
    current)
        current_wallpaper
        ;;
    *)
        printf 'Usage: %s [menu|set PATH|random|preview|rotate-enable|rotate-disable|rotate-toggle|rotate-start-if-enabled|rotate-status|list|current]\n' "$0" >&2
        exit 2
        ;;
esac
