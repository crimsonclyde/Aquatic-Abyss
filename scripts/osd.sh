#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${AQUATIC_ABYSS_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
AGS_LAUNCHER="$REPO/scripts/ags-osd.sh"
BACKLIGHT_DEVICE="amdgpu_bl1"
INSTANCE="ags-osd"

start_ags_osd() {
    "$AGS_LAUNCHER" start
}

send_osd() {
    start_ags_osd

    for _ in 1 2 3 4 5; do
        if ags request --instance "$INSTANCE" show "$1" "$2" "${3:-false}" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done

    ags request --instance "$INSTANCE" show "$1" "$2" "${3:-false}" >/dev/null
}

brightness_percent() {
    current="$(brightnessctl -d "$BACKLIGHT_DEVICE" get)"
    max="$(brightnessctl -d "$BACKLIGHT_DEVICE" max)"
    awk -v current="$current" -v max="$max" 'BEGIN { printf "%d", (current / max * 100) + 0.5 }'
}

volume_percent() {
    wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{ printf "%d", ($2 * 100) + 0.5 }'
}

mic_percent() {
    wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | awk '{ printf "%d", ($2 * 100) + 0.5 }'
}

case "${1:-}" in
    brightness-up)
        brightnessctl -q -d "$BACKLIGHT_DEVICE" set +5%
        send_osd brightness "$(brightness_percent)" false
        ;;
    brightness-down)
        brightnessctl -q -d "$BACKLIGHT_DEVICE" set 5%-
        send_osd brightness "$(brightness_percent)" false
        ;;
    volume-up)
        wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+
        send_osd volume "$(volume_percent)" false
        ;;
    volume-down)
        wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
        send_osd volume "$(volume_percent)" false
        ;;
    volume-mute)
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        muted="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED && echo true || echo false)"
        send_osd volume "$(volume_percent)" "$muted"
        ;;
    mic-up)
        wpctl set-volume -l 1 @DEFAULT_AUDIO_SOURCE@ 5%+
        send_osd mic "$(mic_percent)" false
        ;;
    mic-down)
        wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 5%-
        send_osd mic "$(mic_percent)" false
        ;;
    mic-mute)
        wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
        muted="$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED && echo true || echo false)"
        send_osd mic "$(mic_percent)" "$muted"
        ;;
    show)
        send_osd "${2:?kind required}" "${3:?percent required}" "${4:-false}"
        ;;
    *)
        echo "Usage: $0 brightness-up|brightness-down|volume-up|volume-down|volume-mute|mic-up|mic-down|mic-mute|show KIND PERCENT [MUTED]" >&2
        exit 2
        ;;
esac
