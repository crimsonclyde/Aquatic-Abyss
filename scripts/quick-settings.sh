#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${AQUATIC_ABYSS_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
export AQUATIC_ABYSS_DIR="$REPO"
AGS_CONFIG="$REPO/.config/ags/quick-settings.tsx"
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/ags-quick-settings.log"

mkdir -p "$(dirname "$LOG")"

is_running() {
    ags request --instance ags-quick-settings ping >/dev/null 2>&1
}

start_visible() {
    nohup ags run "$AGS_CONFIG" >"$LOG" 2>&1 &
    disown 2>/dev/null || true

    for _ in {1..100}; do
        if is_running; then
            ags request --instance ags-quick-settings show >/dev/null 2>&1 || true
            return 0
        fi

        sleep 0.1
    done

    echo "ags-quick-settings did not start; see $LOG" >&2
    return 1
}

ensure_started() {
    if ! ags request --instance ags-quick-settings ping >/dev/null 2>&1; then
        start_visible
    fi
}

case "${1:-toggle}" in
    start)
        ensure_started
        ;;
    stop)
        ags quit --instance ags-quick-settings >/dev/null 2>&1 || true
        ;;
    restart)
        "$0" stop
        "$0" start
        ;;
    show)
        if ! is_running; then
            start_visible
            exit 0
        fi
        ags request --instance ags-quick-settings show >/dev/null 2>&1
        ;;
    toggle)
        if ! is_running; then
            start_visible
            exit 0
        fi
        ags request --instance ags-quick-settings toggle >/dev/null 2>&1
        ;;
    hide)
        ensure_started
        ags request --instance ags-quick-settings "$1" >/dev/null 2>&1
        ;;
    wallpaper)
        ensure_started
        ags request --instance ags-quick-settings wallpaper >/dev/null 2>&1
        ;;
    wifi)
        ensure_started
        ags request --instance ags-quick-settings wifi >/dev/null 2>&1
        ;;
    vpn)
        ensure_started
        ags request --instance ags-quick-settings vpn >/dev/null 2>&1
        ;;
    *)
        echo "Usage: $0 [start|stop|restart|show|toggle|hide|wallpaper|wifi|vpn]" >&2
        exit 2
        ;;
esac
