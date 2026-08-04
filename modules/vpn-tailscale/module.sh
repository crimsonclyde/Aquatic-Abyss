#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/aquatic-abyss/vpn-tailscale.env"
LEGACY_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/vpn_menu.env"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
LOG_FILE="$STATE_DIR/aquatic-abyss-vpn.log"

TS_PRIMARY_ID=""
TS_PRIMARY_NAME="Personal"
TS_SECONDARY_ID=""
TS_SECONDARY_NAME="Work"
VPN_PRIMARY_NAME=""
VPN_PRIMARY_LABEL="OpenVPN"

if [ -r "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
elif [ -r "$LEGACY_CONFIG_FILE" ]; then
    # Pre-module config location; still honored so existing setups keep working.
    # shellcheck disable=SC1090
    . "$LEGACY_CONFIG_FILE"
fi

have() {
    command -v "$1" >/dev/null 2>&1
}

log_message() {
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

notify() {
    local title="$1"
    local message="$2"

    if have notify-send; then
        notify-send "$title" "$message" || true
    fi
}

run_logged() {
    local description="$1"
    shift

    local output status

    if output=$("$@" 2>&1); then
        [ -z "$output" ] || log_message "$description: $output"
        return 0
    fi

    status=$?
    log_message "$description failed ($status): $output"
    notify "VPN action failed" "${output:-$description failed}"
    return "$status"
}

tailscale_up_checked() {
    local description="$1"
    local state

    run_logged "$description" tailscale up --timeout=12s || return $?

    state=$(tailscale_state)
    if [ "$state" = "Running" ]; then
        return 0
    fi

    log_message "$description left Tailscale in state: $state"
    if [ "$state" = "NeedsLogin" ]; then
        notify "Tailscale login required" "Run tailscale up in a terminal to finish authentication."
    else
        notify "Tailscale not connected" "Current state: $state"
    fi

    return 1
}

json_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    printf '%s' "$value"
}

connection_label() {
    local name="$1"
    local type="$2"

    if [ -n "$VPN_PRIMARY_NAME" ] && [ "$name" = "$VPN_PRIMARY_NAME" ]; then
        printf '%s' "$VPN_PRIMARY_LABEL"
        return
    fi

    case "$type" in
        wireguard)
            printf '%s' "$name"
            ;;
        vpn)
            printf '%s' "$name"
            ;;
        *)
            printf '%s' "$name"
            ;;
    esac
}

connection_kind() {
    case "$1" in
        wireguard)
            printf 'WireGuard'
            ;;
        vpn)
            printf 'OpenVPN'
            ;;
        *)
            printf 'VPN'
            ;;
    esac
}

connection_icon() {
    case "$1" in
        wireguard)
            printf '󰒃'
            ;;
        *)
            printf ''
            ;;
    esac
}

nm_connections() {
    have nmcli || return 0

    nmcli -t -f name,type con show 2>/dev/null | while IFS=: read -r name type; do
        case "$type" in
            vpn|wireguard)
                printf '%s\t%s\n' "$name" "$type"
                ;;
        esac
    done
}

nm_active_names() {
    have nmcli || return 0

    nmcli -t -f name,type,state con show --active 2>/dev/null | while IFS=: read -r name type state; do
        case "$type" in
            vpn|wireguard)
                [ "$state" = "activated" ] && printf '%s\n' "$name"
                ;;
        esac
    done
}

nm_is_active() {
    local name="$1"

    nm_active_names | grep -Fxq "$name"
}

tailscale_state() {
    have tailscale || {
        printf 'missing'
        return
    }

    if have jq; then
        tailscale status --json 2>/dev/null | jq -r '.BackendState // "Stopped"' 2>/dev/null || printf 'Stopped'
    else
        tailscale status >/dev/null 2>&1 && printf 'Running' || printf 'Stopped'
    fi
}

tailscale_active_id() {
    have tailscale || return 0

    if have jq; then
        tailscale switch --list --json 2>/dev/null | jq -r '.[] | select(.selected == true) | .id' 2>/dev/null || true
        return
    fi

    tailscale switch --list 2>/dev/null | awk '/\*/ { print $1; exit }'
}

tailscale_label_for_id() {
    local account_id="$1"

    if [ -n "$TS_PRIMARY_ID" ] && [ "$account_id" = "$TS_PRIMARY_ID" ]; then
        printf '%s' "$TS_PRIMARY_NAME"
    elif [ -n "$TS_SECONDARY_ID" ] && [ "$account_id" = "$TS_SECONDARY_ID" ]; then
        printf '%s' "$TS_SECONDARY_NAME"
    else
        printf 'Tailscale'
    fi
}

has_any_provider() {
    if have tailscale; then
        return 0
    fi

    if [ -n "$(nm_connections)" ]; then
        return 0
    fi

    return 1
}

print_row() {
    local action="$1"
    local icon="$2"
    local title="$3"
    local subtitle="$4"
    local active="$5"

    printf '%s\t%s\t%s\t%s\t%s\n' "$action" "$icon" "$title" "$subtitle" "$active"
}

print_list() {
    local ts_status active_ts ts_label

    if have tailscale; then
        ts_status=$(tailscale_state)
        active_ts=$(tailscale_active_id || true)
        ts_label=$(tailscale_label_for_id "$active_ts")

        if [ "$ts_status" = "Running" ]; then
            print_row "tailscale:down" "󰖂" "$ts_label" "Tailscale connected" "true"
            if [ -n "$TS_PRIMARY_ID" ] && [ "$active_ts" != "$TS_PRIMARY_ID" ]; then
                print_row "tailscale:switch:$TS_PRIMARY_ID" "󰖂" "$TS_PRIMARY_NAME" "Switch Tailscale account" "false"
            fi
            if [ -n "$TS_SECONDARY_ID" ] && [ "$active_ts" != "$TS_SECONDARY_ID" ]; then
                print_row "tailscale:switch:$TS_SECONDARY_ID" "󰖂" "$TS_SECONDARY_NAME" "Switch Tailscale account" "false"
            fi
        else
            if [ -n "$TS_PRIMARY_ID" ] || [ -n "$TS_SECONDARY_ID" ]; then
                if [ -n "$TS_PRIMARY_ID" ]; then
                    if [ "$active_ts" = "$TS_PRIMARY_ID" ] && [ "$ts_status" = "NeedsLogin" ]; then
                        print_row "tailscale:up" "󰖂" "$TS_PRIMARY_NAME" "Login required" "false"
                    else
                        print_row "tailscale:switch:$TS_PRIMARY_ID" "󰖂" "$TS_PRIMARY_NAME" "Switch and connect Tailscale" "false"
                    fi
                fi
                if [ -n "$TS_SECONDARY_ID" ]; then
                    if [ "$active_ts" = "$TS_SECONDARY_ID" ] && [ "$ts_status" = "NeedsLogin" ]; then
                        print_row "tailscale:up" "󰖂" "$TS_SECONDARY_NAME" "Login required" "false"
                    else
                        print_row "tailscale:switch:$TS_SECONDARY_ID" "󰖂" "$TS_SECONDARY_NAME" "Switch and connect Tailscale" "false"
                    fi
                fi
            else
                print_row "tailscale:up" "󰖂" "Tailscale" "Connect mesh VPN" "false"
            fi
        fi
    fi

    nm_connections | while IFS=$'\t' read -r name type; do
        local label kind icon action active state

        label=$(connection_label "$name" "$type")
        kind=$(connection_kind "$type")
        icon=$(connection_icon "$type")

        if nm_is_active "$name"; then
            action="nm:down:$name"
            active="true"
            state="$kind connected"
        else
            action="nm:up:$name"
            active="false"
            state="Connect $kind profile"
        fi

        print_row "$action" "$icon" "$label" "$state" "$active"
    done || true

    return 0
}

print_status() {
    local vpn_active ts_status active_ts ts_active status_text tooltip class

    if ! has_any_provider; then
        printf '{"text":"","tooltip":"","class":"hidden"}\n'
        return
    fi

    vpn_active=""
    while IFS= read -r active_name; do
        vpn_active="$active_name"
        break
    done < <(nm_active_names)

    ts_status=$(tailscale_state)
    ts_active=""

    if [ "$ts_status" = "Running" ]; then
        active_ts=$(tailscale_active_id || true)
        ts_active=$(tailscale_label_for_id "$active_ts")
    fi

    if [ -n "$vpn_active" ] && [ -n "$ts_active" ]; then
        status_text=""
        tooltip="VPN: $vpn_active\\n$ts_active: Connected"
        class="connected-both"
    elif [ -n "$vpn_active" ]; then
        status_text=""
        tooltip="VPN: $vpn_active"
        class="connected"
    elif [ -n "$ts_active" ]; then
        status_text="󰖂"
        tooltip="$ts_active: Connected"
        class="connected-ts"
    else
        status_text="󰖣"
        tooltip="VPN disconnected"
        class="disconnected"
    fi

    printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
        "$(json_escape "$status_text")" \
        "$(json_escape "$tooltip")" \
        "$(json_escape "$class")"
}

run_action() {
    local action="${1:-}"
    local target

    case "$action" in
        tailscale:down)
            run_logged "tailscale down" tailscale down
            notify "Tailscale" "Disconnected"
            ;;
        tailscale:up)
            tailscale_up_checked "tailscale up"
            notify "Tailscale" "Connected"
            ;;
        tailscale:switch:*)
            target="${action#tailscale:switch:}"
            run_logged "tailscale switch $target" tailscale switch "$target"
            tailscale_up_checked "tailscale up after switch"
            notify "Tailscale" "Connected to $(tailscale_label_for_id "$target")"
            ;;
        nm:down:*)
            target="${action#nm:down:}"
            run_logged "nmcli down $target" nmcli con down "$target"
            notify "VPN" "$target disconnected"
            ;;
        nm:up:*)
            target="${action#nm:up:}"
            run_logged "nmcli up $target" nmcli con up "$target"
            notify "VPN" "$target connected"
            ;;
        *)
            log_message "unknown action: $action"
            exit 1
            ;;
    esac
}

case "${1:-status}" in
    available)
        has_any_provider || exit 1
        printf 'yes\n'
        ;;
    visible)
        # Legacy alias for the pre-module quick-settings picker; removed in 5.3.
        if has_any_provider; then
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
        if has_any_provider; then
            "$REPO_DIR/scripts/quick-settings.sh" vpn >/dev/null 2>&1 &
        fi
        ;;
    *)
        printf 'Usage: %s [available|visible|list|status|run ACTION]\n' "$0" >&2
        exit 2
        ;;
esac
