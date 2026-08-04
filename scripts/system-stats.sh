#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${AQUATIC_ABYSS_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
export AQUATIC_ABYSS_DIR="$REPO"
AGS_CONFIG="$REPO/.config/ags/system-stats.tsx"
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/ags-system-stats.log"

mkdir -p "$(dirname "$LOG")"

ensure_started() {
    if ! ags request --instance ags-system-stats ping >/dev/null 2>&1; then
        nohup ags run "$AGS_CONFIG" >"$LOG" 2>&1 &
        disown 2>/dev/null || true

        for _ in {1..30}; do
            if ags request --instance ags-system-stats ping >/dev/null 2>&1; then
                return 0
            fi

            sleep 0.1
        done

        echo "ags-system-stats did not start; see $LOG" >&2
        return 1
    fi
}

case "${1:-toggle}" in
    start)
        ensure_started
        ;;
    stop)
        ags quit --instance ags-system-stats >/dev/null 2>&1 || true
        ;;
    restart)
        "$0" stop
        "$0" start
        ;;
    show|toggle|hide)
        ensure_started
        ags request --instance ags-system-stats "$1" >/dev/null 2>&1
        ;;
    *)
        echo "Usage: $0 [start|stop|restart|show|toggle|hide]" >&2
        exit 2
        ;;
esac
