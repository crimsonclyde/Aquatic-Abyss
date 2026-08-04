#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

have() {
    command -v "$1" >/dev/null 2>&1
}

json_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    printf '%s' "$value"
}

wifi_interface() {
    have nmcli || return 0

    nmcli -t -f DEVICE,TYPE device 2>/dev/null | awk -F: '$2 == "wifi" { print $1; exit }'
}

wifi_enabled() {
    have nmcli || return 1

    [ "$(nmcli radio wifi 2>/dev/null || true)" = "enabled" ]
}

signal_icon() {
    local signal="${1:-0}"

    if [ "$signal" -ge 80 ]; then
        printf '󰤨'
    elif [ "$signal" -ge 60 ]; then
        printf '󰤥'
    elif [ "$signal" -ge 40 ]; then
        printf '󰤢'
    elif [ "$signal" -ge 20 ]; then
        printf '󰤟'
    else
        printf '󰤯'
    fi
}

connected_row() {
    have nmcli || return 0

    nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi 2>/dev/null | awk -F: '$1 == "yes" { print; exit }'
}

connected_ssid() {
    local row

    row=$(connected_row)
    [ -n "$row" ] || return 0
    printf '%s' "$row" | awk -F: '{ print $2 }'
}

has_wifi() {
    [ -n "$(wifi_interface)" ]
}

print_row() {
    local action="$1"
    local icon="$2"
    local title="$3"
    local subtitle="$4"
    local active="$5"

    printf '%s\t%s\t%s\t%s\t%s\n' "$action" "$icon" "$title" "$subtitle" "$active"
}

print_status() {
    local iface connected ssid signal icon ip

    if ! has_wifi; then
        printf '{"text":"","tooltip":"","class":"hidden"}\n'
        return
    fi

    if ! wifi_enabled; then
        printf '{"text":"󰤮","tooltip":"WiFi disabled","class":"wifi-off"}\n'
        return
    fi

    iface=$(wifi_interface)
    connected=$(connected_row)

    if [ -n "$connected" ]; then
        ssid=$(printf '%s' "$connected" | awk -F: '{ print $2 }')
        signal=$(printf '%s' "$connected" | awk -F: '{ print $3 }')
        icon=$(signal_icon "$signal")
        ip=$(nmcli -t -f IP4.ADDRESS device show "$iface" 2>/dev/null | awk -F: '{ print $2; exit }')

        printf '{"text":"%s","tooltip":"%s","class":"wifi-connected"}\n' \
            "$(json_escape "$icon")" \
            "$(json_escape "$ssid ($signal%)\\nIP: $ip")"
    else
        printf '{"text":"󰤭","tooltip":"WiFi on, not connected","class":"wifi-disconnected"}\n'
    fi
}

print_list() {
    local connected ssid signal icon security active subtitle

    if ! has_wifi; then
        return 0
    fi

    if wifi_enabled; then
        print_row "wifi:off" "󰤮" "Disable WiFi" "Turn off wireless networking" "false"

        connected=$(connected_ssid)
        if [ -n "$connected" ]; then
            print_row "wifi:disconnect" "󰤭" "Disconnect" "Leave $connected" "false"
        fi

        nmcli -t -f SSID,SECURITY,SIGNAL dev wifi list 2>/dev/null \
            | awk -F: '$1 != "" && !seen[$1]++ { print }' \
            | sort -t: -k3 -rn \
            | while IFS=: read -r ssid security signal; do
                [ -n "$ssid" ] || continue

                icon=$(signal_icon "$signal")
                active="false"
                subtitle="${signal}% signal"

                if [ -n "$security" ] && [ "$security" != "--" ]; then
                    subtitle="$subtitle · secured"
                else
                    subtitle="$subtitle · open"
                fi

                if [ "$ssid" = "${connected:-}" ]; then
                    active="true"
                    subtitle="Connected · $subtitle"
                fi

                print_row "wifi:connect:$ssid" "$icon" "$ssid" "$subtitle" "$active"
            done || true
    else
        print_row "wifi:on" "󰤨" "Enable WiFi" "Turn on wireless networking" "false"
    fi

    return 0
}

run_action() {
    local action="${1:-}"
    local iface target

    iface=$(wifi_interface)

    case "$action" in
        wifi:on)
            nmcli radio wifi on
            notify-send "WiFi" "Enabled"
            ;;
        wifi:off)
            nmcli radio wifi off
            notify-send "WiFi" "Disabled"
            ;;
        wifi:disconnect)
            [ -n "$iface" ] || exit 1
            nmcli device disconnect "$iface"
            notify-send "WiFi" "Disconnected"
            ;;
        wifi:connect:*)
            [ -n "$iface" ] || exit 1
            target="${action#wifi:connect:}"
            [ -n "$target" ] || exit 1

            if [ "$target" = "$(connected_ssid)" ]; then
                exit 0
            fi

            notify-send "WiFi" "Connecting to $target..."
            if nmcli device wifi connect "$target" ifname "$iface"; then
                notify-send "WiFi" "Connected to $target"
            else
                notify-send -u critical "WiFi" "Failed to connect to $target"
            fi
            ;;
        *)
            exit 1
            ;;
    esac
}

case "${1:-status}" in
    available)
        has_wifi || exit 1
        printf 'yes\n'
        ;;
    visible)
        # Legacy alias for the pre-module quick-settings picker; removed in 5.3.
        if has_wifi; then
            printf 'yes\n'
        else
            printf 'no\n'
        fi
        ;;
    list)
        print_list
        ;;
    status)
        print_status
        ;;
    run)
        shift
        run_action "${1:-}"
        ;;
    menu)
        if has_wifi; then
            "$REPO_DIR/scripts/quick-settings.sh" wifi >/dev/null 2>&1 &
        fi
        ;;
    *)
        printf 'Usage: %s [available|visible|list|status|run ACTION]\n' "$0" >&2
        exit 2
        ;;
esac
