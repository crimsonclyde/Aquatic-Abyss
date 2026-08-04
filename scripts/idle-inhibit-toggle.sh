#!/usr/bin/env bash
set -euo pipefail

if pgrep -x hypridle >/dev/null; then
    pkill -x hypridle
    notify-send "Idle inhibit" "Enabled: hypridle stopped"
else
    hypridle >/dev/null 2>&1 &
    disown 2>/dev/null || true
    notify-send "Idle inhibit" "Disabled: hypridle running"
fi
