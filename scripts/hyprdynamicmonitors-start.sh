#!/usr/bin/env bash
set -u

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hyprland"
LOG_FILE="$LOG_DIR/hyprdynamicmonitors.log"
MONITOR_CACHE_DIR="$HOME/.cache/hyprdynamicmonitors"

mkdir -p "$LOG_DIR"
mkdir -p "$MONITOR_CACHE_DIR"

if pgrep -af "hyprdynamicmonitors run" >/dev/null; then
    exit 0
fi

if ! command -v hyprdynamicmonitors >/dev/null 2>&1; then
    echo "$(date --iso-8601=seconds) hyprdynamicmonitors is not installed" >> "$LOG_FILE"
    exit 0
fi

nohup hyprdynamicmonitors run --enable-lid-events >> "$LOG_FILE" 2>&1 &
