#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${AQUATIC_ABYSS_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
export AQUATIC_ABYSS_DIR="$REPO"
AGS_CONFIG="$REPO/.config/ags/osd.tsx"
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/ags-osd.log"

mkdir -p "$(dirname "$LOG")"

case "${1:-start}" in
    start)
        if ! ags request --instance ags-osd ping >/dev/null 2>&1; then
            nohup ags run "$AGS_CONFIG" >"$LOG" 2>&1 &
            disown 2>/dev/null || true
        fi
        ;;
    stop)
        ags quit --instance ags-osd >/dev/null 2>&1 || true
        ;;
    restart)
        "$0" stop
        "$0" start
        ;;
    *)
        echo "Usage: $0 [start|stop|restart]" >&2
        exit 2
        ;;
esac
