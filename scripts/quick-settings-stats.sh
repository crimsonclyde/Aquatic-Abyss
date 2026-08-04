#!/usr/bin/env bash
set -euo pipefail

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_string() {
    printf '"%s"' "$(json_escape "$1")"
}

read_cpu() {
    awk '
        NR == 1 {
            idle = $5 + $6
            total = 0
            for (i = 2; i <= NF; i++) total += $i
            if (total > 0) printf "CPU %.0f%%", (total - idle) / total * 100
        }
    ' /proc/stat
}

read_memory() {
    awk '
        /MemTotal:/ { total = $2 }
        /MemAvailable:/ { available = $2 }
        END {
            if (total > 0) printf "RAM %.0f%%", (total - available) / total * 100
        }
    ' /proc/meminfo
}

read_disk() {
    df -h / | awk 'NR == 2 { print "Disk " $5 }'
}

read_temperature() {
    if command -v sensors >/dev/null 2>&1; then
        sensors 2>/dev/null | awk '
            /^Tctl:/ || /^Package id 0:/ || /^cpu@/ || /^cpu_/ {
                value = $2
                gsub(/[+°]/, "", value)
                print "Temp " value
                found = 1
                exit
            }
            END {
                if (!found) exit 1
            }
        ' && return 0
    fi

    for temp_file in /sys/class/thermal/thermal_zone*/temp; do
        [ -r "$temp_file" ] || continue
        temp=$(cat "$temp_file")
        [ "$temp" -gt 0 ] || continue
        awk -v temp="$temp" 'BEGIN { printf "Temp %.0fC", temp / 1000 }'
        return 0
    done

    printf 'Temp --'
}

read_battery() {
    local battery_dir capacity status

    for battery_dir in /sys/class/power_supply/BAT*; do
        [ -r "$battery_dir/capacity" ] || continue
        capacity=$(cat "$battery_dir/capacity")
        status=$(cat "$battery_dir/status" 2>/dev/null || printf '')

        case "$status" in
            Charging)
                printf 'Battery %s%% charging' "$capacity"
                ;;
            Full)
                printf 'Battery %s%% full' "$capacity"
                ;;
            *)
                printf 'Battery %s%%' "$capacity"
                ;;
        esac
        return 0
    done

    printf 'Battery --'
}

read_gpu() {
    local script_dir

    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    gpu_json=$("$script_dir/gpu_stats.sh" 2>/dev/null || true)
    text=$(printf '%s' "$gpu_json" | sed -n 's/.*"text"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    if [ -n "$text" ]; then
        printf 'GPU %s' "$text"
    else
        printf 'GPU --'
    fi
}

read_power() {
    if command -v powerprofilesctl >/dev/null 2>&1; then
        profile=$(powerprofilesctl get 2>/dev/null || true)
        if [ -n "$profile" ]; then
            printf 'Power %s' "$profile"
            return 0
        fi
    fi

    printf 'Power --'
}

is_vpn_interface() {
    case "$1" in
        tailscale*|wg*|tun*|tap*|ppp*|vpn*|proton*|nordlynx*|mullvad*|surfshark*|ivpn*|zt*|zerotier*|warp*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_local_interface() {
    case "$1" in
        lo|docker*|br-*|veth*|virbr*|podman*|cni*|flannel*|cali*|kube*|nerdctl*|containerd*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

interface_ipv4() {
    local iface="$1"

    ip -o -4 addr show dev "$iface" scope global 2>/dev/null | awk '
        NR == 1 {
            split($4, parts, "/")
            print parts[1]
            exit
        }
    '
}

read_lan_ip() {
    local default_iface iface address

    command -v ip >/dev/null 2>&1 || return 1

    default_iface=$(ip -4 route show default 2>/dev/null | awk '
        {
            for (i = 1; i <= NF; i++) {
                if ($i == "dev") {
                    print $(i + 1)
                    exit
                }
            }
        }
    ')

    if [ -n "$default_iface" ] && ! is_local_interface "$default_iface" && ! is_vpn_interface "$default_iface"; then
        address=$(interface_ipv4 "$default_iface")
        if [ -n "$address" ]; then
            printf '%s' "$address"
            return 0
        fi
    fi

    while read -r iface address; do
        iface="${iface%@*}"
        if is_local_interface "$iface" || is_vpn_interface "$iface"; then
            continue
        fi

        printf '%s' "$address"
        return 0
    done < <(ip -o -4 addr show up scope global 2>/dev/null | awk '{ split($4, parts, "/"); print $2, parts[1] }')

    return 1
}

read_vpn_ip() {
    local connection_type iface address

    command -v ip >/dev/null 2>&1 || return 1

    if command -v nmcli >/dev/null 2>&1; then
        while IFS=: read -r connection_type iface; do
            case "$connection_type" in
                vpn|wireguard)
                    ;;
                *)
                    continue
                    ;;
            esac

            [ -n "$iface" ] && [ "$iface" != "--" ] || continue

            address=$(interface_ipv4 "$iface")
            if [ -n "$address" ]; then
                printf '%s' "$address"
                return 0
            fi
        done < <(nmcli -t -f TYPE,DEVICE connection show --active 2>/dev/null || true)
    fi

    while read -r iface address; do
        iface="${iface%@*}"
        if ! is_vpn_interface "$iface"; then
            continue
        fi

        printf '%s' "$address"
        return 0
    done < <(ip -o -4 addr show up scope global 2>/dev/null | awk '{ split($4, parts, "/"); print $2, parts[1] }')

    return 1
}

read_wan_ip() {
    local address

    command -v curl >/dev/null 2>&1 || return 1

    address=$(curl -4fsS --connect-timeout 1 --max-time 2 https://api.ipify.org 2>/dev/null || true)
    if printf '%s' "$address" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
        printf '%s' "$address"
        return 0
    fi

    return 1
}

read_network_json() {
    local rows=()
    local address

    address=$(read_lan_ip || true)
    if [ -n "$address" ]; then
        rows+=("[$(json_string "LAN IP"),$(json_string "$address")]")
    fi

    address=$(read_wan_ip || true)
    if [ -n "$address" ]; then
        rows+=("[$(json_string "WAN IP"),$(json_string "$address")]")
    fi

    address=$(read_vpn_ip || true)
    if [ -n "$address" ]; then
        rows+=("[$(json_string "VPN IP"),$(json_string "$address")]")
    fi

    local IFS=,
    printf '[%s]' "${rows[*]}"
}

read_wallpaper() {
    config_wallpaper=""
    user_wallpaper_dir="$HOME/Pictures/Wallpapers"

    if [ -r "$HOME/.config/waypaper/config.ini" ]; then
        config_wallpaper=$(awk -F= '
            $1 ~ /^[[:space:]]*wallpaper[[:space:]]*$/ {
                sub(/^[[:space:]]*/, "", $2)
                print $2
                exit
            }
        ' "$HOME/.config/waypaper/config.ini")
    fi

    if [ -n "$config_wallpaper" ] && [ ! -f "$config_wallpaper" ] && [ "$config_wallpaper" = /usr/share/hypr/wall0.png ]; then
        first_user_wallpaper=$(find "$user_wallpaper_dir" -maxdepth 3 -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.avif' \) \
            2>/dev/null | sort | head -n 1)
        if [ -n "$first_user_wallpaper" ]; then
            config_wallpaper="$first_user_wallpaper"
        fi
    fi

    if [ -z "$config_wallpaper" ] && [ -r "$HOME/.config/hypr/hyprpaper.conf" ]; then
        config_wallpaper=$(awk -F= '
            $1 ~ /^[[:space:]]*wallpaper[[:space:]]*$/ {
                sub(/^[[:space:]]*/, "", $2)
                split($2, parts, ",")
                print parts[length(parts)]
                exit
            }
        ' "$HOME/.config/hypr/hyprpaper.conf")
    fi

    if [ -n "$config_wallpaper" ]; then
        printf 'Wallpaper %s' "$(basename "$config_wallpaper")"
    else
        printf 'Wallpaper --'
    fi
}

read_wpctl_line() {
    wpctl get-volume "$1" 2>/dev/null || true
}

format_wpctl_volume() {
    label="$1"
    line="$2"

    if [ -z "$line" ]; then
        printf '%s --' "$label"
        return
    fi

    volume=$(printf '%s' "$line" | awk '{ print $2 }')
    percent=$(awk -v volume="$volume" 'BEGIN { printf "%.0f", volume * 100 }')

    if printf '%s' "$line" | grep -qi muted; then
        printf '%s muted' "$label"
    else
        printf '%s %s%%' "$label" "$percent"
    fi
}

cpu=$(read_cpu || printf 'CPU --')
memory=$(read_memory || printf 'RAM --')
disk=$(read_disk || printf 'Disk --')
temperature=$(read_temperature || printf 'Temp --')
gpu=$(read_gpu || printf 'GPU --')
battery=$(read_battery || printf 'Battery --')
power=$(read_power || printf 'Power --')
wallpaper=$(read_wallpaper || printf 'Wallpaper --')
volume=$(format_wpctl_volume "Volume" "$(read_wpctl_line "@DEFAULT_AUDIO_SINK@")")
mic=$(format_wpctl_volume "Mic" "$(read_wpctl_line "@DEFAULT_AUDIO_SOURCE@")")
network=$(read_network_json)

printf '{"cpu":"%s","memory":"%s","disk":"%s","temperature":"%s","gpu":"%s","battery":"%s","power":"%s","wallpaper":"%s","volume":"%s","mic":"%s","network":%s}\n' \
    "$(json_escape "$cpu")" \
    "$(json_escape "$memory")" \
    "$(json_escape "$disk")" \
    "$(json_escape "$temperature")" \
    "$(json_escape "$gpu")" \
    "$(json_escape "$battery")" \
    "$(json_escape "$power")" \
    "$(json_escape "$wallpaper")" \
    "$(json_escape "$volume")" \
    "$(json_escape "$mic")" \
    "$network"
