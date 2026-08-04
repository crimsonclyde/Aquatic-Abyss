#!/usr/bin/env bash
set -euo pipefail

# Connect/disconnect toggle for one user-configured Bluetooth audio device.
# The device is machine-specific and lives outside the repo:
#   ~/.config/aquatic-abyss/bt-soundbar.env  (see bt-soundbar.env.example)
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/aquatic-abyss/bt-soundbar.env"

BT_SOUNDBAR_MAC=""
BT_SOUNDBAR_NAME="Soundbar"

if [ -r "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
fi

have() {
    command -v "$1" >/dev/null 2>&1
}

notify() {
    local icon="$1"
    local urgency="$2"
    shift 2

    if have notify-send; then
        notify-send -i "$icon" --urgency="$urgency" "Bluetooth" "$*" || true
    fi
}

bt() {
    # bluetoothctl talks to bluetoothd over D-Bus; if the daemon is wedged a
    # call can stall forever, so cap every invocation.
    timeout 10s bluetoothctl "$@"
}

is_connected() {
    bt info "$BT_SOUNDBAR_MAC" 2>/dev/null | grep -q "Connected: yes"
}

connect() {
    if is_connected; then
        notify bluetooth-active low "$BT_SOUNDBAR_NAME already connected"
        return 0
    fi

    bt power on >/dev/null 2>&1 || true

    if bt connect "$BT_SOUNDBAR_MAC" >/dev/null 2>&1 && is_connected; then
        notify bluetooth-active low "Connected to $BT_SOUNDBAR_NAME 🔊"
        return 0
    fi

    notify bluetooth-disabled critical "Failed to connect to $BT_SOUNDBAR_NAME (powered on and paired?)"
    return 1
}

disconnect() {
    if ! is_connected; then
        notify bluetooth-disabled low "$BT_SOUNDBAR_NAME is not connected"
        return 0
    fi

    if bt disconnect "$BT_SOUNDBAR_MAC" >/dev/null 2>&1 && ! is_connected; then
        notify bluetooth-disabled low "Disconnected from $BT_SOUNDBAR_NAME"
        return 0
    fi

    notify bluetooth-disabled critical "Failed to disconnect from $BT_SOUNDBAR_NAME"
    return 1
}

toggle() {
    if is_connected; then
        disconnect
    else
        connect
    fi
}

status() {
    local state="disconnected"

    if is_connected; then
        state="connected"
    fi

    printf '{"text":"%s %s","state":"%s"}\n' "$BT_SOUNDBAR_NAME" "$state" "$state"
}

available() {
    # Hidden until usable: needs bluetoothctl, a Bluetooth adapter, and a
    # configured device. No configured MAC → no button, per "hidden, not broken".
    have bluetoothctl || return 1
    ls /sys/class/bluetooth/ 2>/dev/null | grep -q . || return 1
    [ -n "$BT_SOUNDBAR_MAC" ] || return 1
    echo yes
}

require_config() {
    if [ -z "$BT_SOUNDBAR_MAC" ]; then
        echo "bt-soundbar: set BT_SOUNDBAR_MAC in $CONFIG_FILE" >&2
        notify bluetooth-disabled normal "Soundbar not configured — set BT_SOUNDBAR_MAC in ${CONFIG_FILE/#$HOME/\~}"
        exit 1
    fi

    if ! have bluetoothctl; then
        echo "bt-soundbar: bluetoothctl not found (install bluez)" >&2
        exit 1
    fi
}

case "${1:-toggle}" in
    available)
        available
        ;;
    status)
        require_config
        status
        ;;
    connect)
        require_config
        connect
        ;;
    disconnect)
        require_config
        disconnect
        ;;
    toggle)
        require_config
        toggle
        ;;
    *)
        echo "Usage: $(basename "$0") {available|status|connect|disconnect|toggle}" >&2
        exit 2
        ;;
esac
