#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${AQUATIC_ABYSS_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
export AQUATIC_ABYSS_DIR="$REPO"
AGS_CONFIG="$REPO/.config/ags/shortcut-overlay.tsx"
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/ags-shortcut-overlay.log"

mkdir -p "$(dirname "$LOG")"

is_running() {
    ags request --instance ags-shortcut-overlay ping >/dev/null 2>&1
}

start_visible() {
    nohup ags run "$AGS_CONFIG" show >"$LOG" 2>&1 &
    disown 2>/dev/null || true

    for _ in {1..30}; do
        if is_running; then
            return 0
        fi

        sleep 0.1
    done

    echo "ags-shortcut-overlay did not start; see $LOG" >&2
    return 1
}

ensure_started() {
    if ! is_running; then
        start_visible
    fi
}

case "${1:-toggle}" in
    start)
        ensure_started
        ;;
    stop)
        ags quit --instance ags-shortcut-overlay >/dev/null 2>&1 || true
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
        ags request --instance ags-shortcut-overlay show >/dev/null 2>&1
        ;;
    toggle)
        if ! is_running; then
            start_visible
            exit 0
        fi
        ags request --instance ags-shortcut-overlay toggle >/dev/null 2>&1
        ;;
    hide)
        ensure_started
        ags request --instance ags-shortcut-overlay hide >/dev/null 2>&1
        ;;
    *)
        echo "Usage: $0 [start|stop|restart|show|toggle|hide]" >&2
        exit 2
        ;;
esac
