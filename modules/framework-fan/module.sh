#!/usr/bin/env bash
set -euo pipefail

# Fan control for laptops with a ChromeOS EC (e.g. Framework) via ectool.
# Manual duty ladder from off to max; "auto" hands control back to the EC.
LEVELS=(0 20 40 60 80 100)
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/aquatic-abyss-fan-state"

find_ectool() {
    command -v ectool 2>/dev/null && return 0
    command -v fw-ectool 2>/dev/null && return 0
    return 1
}

read_rpm() {
    local hwmon rpm

    for hwmon in /sys/class/hwmon/hwmon*; do
        [ -r "$hwmon/name" ] || continue
        [ "$(cat "$hwmon/name")" = "cros_ec" ] || continue
        [ -r "$hwmon/fan1_input" ] || continue
        rpm=$(cat "$hwmon/fan1_input")
        printf '%s' "$rpm"
        return 0
    done

    return 1
}

read_state() {
    local state

    if [ -r "$STATE_FILE" ]; then
        state=$(cat "$STATE_FILE")
        case "$state" in
            auto|[0-9]|[0-9][0-9])
                printf '%s' "$state"
                return 0
                ;;
        esac
    fi

    printf 'auto'
}

write_state() {
    printf '%s' "$1" > "$STATE_FILE"
}

apply_level() {
    local index="$1"
    local ectool

    if ! ectool=$(find_ectool); then
        echo "ectool not found; install fw-ectool" >&2
        return 1
    fi

    if [ "$index" = "auto" ]; then
        sudo -n "$ectool" autofanctrl >/dev/null
    else
        sudo -n "$ectool" fanduty "${LEVELS[$index]}" >/dev/null
    fi

    write_state "$index"
}

step() {
    local direction="$1"
    local state max_index

    state=$(read_state)
    max_index=$((${#LEVELS[@]} - 1))

    if [ "$state" = "auto" ]; then
        # Entering manual mode: + means "more than auto", - means "quieter".
        if [ "$direction" = "up" ]; then
            apply_level 3
        else
            apply_level 1
        fi
        return
    fi

    if [ "$direction" = "up" ]; then
        state=$((state < max_index ? state + 1 : max_index))
    else
        state=$((state > 0 ? state - 1 : 0))
    fi

    apply_level "$state"
}

status() {
    local state rpm mode_text

    state=$(read_state)
    rpm=$(read_rpm || printf '?')

    if [ "$state" = "auto" ]; then
        mode_text="auto"
    elif [ "${LEVELS[$state]}" -eq 0 ]; then
        mode_text="off"
    elif [ "${LEVELS[$state]}" -eq 100 ]; then
        mode_text="max"
    else
        mode_text="${LEVELS[$state]}%"
    fi

    printf '{"text":"Fan %s RPM · %s","rpm":"%s","mode":"%s"}\n' "$rpm" "$mode_text" "$rpm" "$mode_text"
}

available() {
    # Require the EC device AND ectool: a fan row you can't control is clutter.
    [ -e /dev/cros_ec ] || return 1
    find_ectool >/dev/null || return 1
    echo yes
}

case "${1:-status}" in
    available)
        available
        ;;
    up)
        step up
        ;;
    down)
        step down
        ;;
    auto)
        apply_level auto
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $(basename "$0") {available|up|down|auto|status}" >&2
        exit 1
        ;;
esac
