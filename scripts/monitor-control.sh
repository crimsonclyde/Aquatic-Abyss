#!/usr/bin/env bash
set -euo pipefail

INTERNAL_OUTPUT="${INTERNAL_OUTPUT:-eDP-1}"
INTERNAL_SCALE="${INTERNAL_SCALE:-1.5}"
WORKSPACES="${WORKSPACES:-1 2 3 4 5 6 7 8 9 10}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hyprland"
LOG_FILE="$STATE_DIR/monitor-control.log"
WATCH_PID_FILE="$STATE_DIR/monitor-control-watch.pid"
WATCH_INTERVAL="${WATCH_INTERVAL:-2}"

mkdir -p "$STATE_DIR"

log() {
    { printf '%s %s\n' "$(date --iso-8601=seconds)" "$*"; } 2>/dev/null >> "$LOG_FILE" || true
}

json_escape() {
    jq -Rsa .
}

lua_string() {
    jq -R .
}

monitor_json() {
    local json

    if ! json=$(hyprctl monitors -j 2>/dev/null); then
        log "hyprctl monitors -j failed"
        printf '[]\n'
        return
    fi

    if ! printf '%s' "$json" | jq -e type >/dev/null 2>&1; then
        log "hyprctl monitors -j returned invalid JSON"
        printf '[]\n'
        return
    fi

    printf '%s\n' "$json"
}

workspace_json() {
    local json

    if ! json=$(hyprctl workspaces -j 2>/dev/null); then
        log "hyprctl workspaces -j failed"
        printf '[]\n'
        return
    fi

    if ! printf '%s' "$json" | jq -e type >/dev/null 2>&1; then
        log "hyprctl workspaces -j returned invalid JSON"
        printf '[]\n'
        return
    fi

    printf '%s\n' "$json"
}

lid_state() {
    local line

    line=$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager LidIsClosed 2>/dev/null || true)
    if [ -z "$line" ]; then
        line=$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager LidClosed 2>/dev/null || true)
    fi

    case "$line" in
        "b true")
            printf 'closed'
            ;;
        "b false")
            printf 'open'
            ;;
        *)
            printf 'unknown'
            ;;
    esac
}

internal_active() {
    monitor_json | jq -e --arg internal "$INTERNAL_OUTPUT" 'any(.[]; .name == $internal)' >/dev/null
}

wait_for_internal_active() {
    local attempts=0

    while [ "$attempts" -lt 10 ]; do
        if internal_active; then
            return 0
        fi

        attempts=$((attempts + 1))
        sleep 0.2
    done

    log "$INTERNAL_OUTPUT did not become active after enable command"
    return 1
}

first_external() {
    monitor_json | jq -r --arg internal "$INTERNAL_OUTPUT" '
        [.[] | select(.name != $internal) | .name][0] // empty
    '
}

external_names() {
    monitor_json | jq -r --arg internal "$INTERNAL_OUTPUT" '
        .[] | select(.name != $internal) | .name
    '
}

external_list() {
    monitor_json | jq -r --arg internal "$INTERNAL_OUTPUT" '
        [.[] | select(.name != $internal) | .name] | join(", ")
    '
}

monitor_signature() {
    monitor_json | jq -r '
        [.[] | .name] | sort | join(",")
    '
}

all_workspace_names() {
    local -a workspaces

    read -r -a workspaces <<< "$WORKSPACES"
    printf '%s\n' "${workspaces[@]}"
}

workspace_exists() {
    local workspace="$1"

    workspace_json | jq -e --arg workspace "$workspace" '
        any(.[]; .name == $workspace)
    ' >/dev/null
}

set_workspace_rule() {
    local workspace="$1"
    local target="$2"
    local workspace_lua
    local target_lua

    [ -n "$workspace" ] || return 0
    [ -n "$target" ] || return 0

    log "setting workspace $workspace default monitor to $target"
    workspace_lua=$(printf '%s' "$workspace" | lua_string)
    target_lua=$(printf '%s' "$target" | lua_string)

    if ! monitor_eval "hl.workspace_rule({ workspace = $workspace_lua, monitor = $target_lua, persistent = false })"; then
        log "failed to set workspace $workspace default monitor to $target"
    fi
}

move_workspace_to_monitor() {
    local workspace="$1"
    local target="$2"
    local workspace_lua
    local target_lua

    [ -n "$workspace" ] || return 0
    [ -n "$target" ] || return 0

    log "assigning workspace $workspace to $target"
    workspace_lua=$(printf '%s' "$workspace" | lua_string)
    target_lua=$(printf '%s' "$target" | lua_string)

    if ! workspace_exists "$workspace"; then
        log "workspace $workspace is not active; leaving default rule only"
        return 0
    fi

    if ! monitor_eval "hl.dispatch(hl.dsp.workspace.move({ workspace = $workspace_lua, monitor = $target_lua }))"; then
        log "failed to assign workspace $workspace to $target"
    fi
}

assign_workspace_range() {
    local target="$1"
    shift

    [ -n "$target" ] || return 0

    local workspace
    for workspace in "$@"; do
        set_workspace_rule "$workspace" "$target"
        move_workspace_to_monitor "$workspace" "$target"
    done
}

move_workspaces_from_internal() {
    local target="$1"
    local workspace

    [ -n "$target" ] || return 0

    while IFS= read -r workspace; do
        [ -n "$workspace" ] || continue
        log "moving workspace $workspace from $INTERNAL_OUTPUT to $target"
        move_workspace_to_monitor "$workspace" "$target"
    done < <(workspace_json | jq -r --arg internal "$INTERNAL_OUTPUT" '
        .[] | select(.monitor == $internal) | .name
    ')
}

assign_workspace_policy() {
    local -a externals
    local -a workspaces

    mapfile -t externals < <(external_names)
    mapfile -t workspaces < <(all_workspace_names)

    if ! internal_active; then
        if [ "${#externals[@]}" -gt 0 ]; then
            log "internal inactive; assigning all workspaces to ${externals[0]}"
            assign_workspace_range "${externals[0]}" "${workspaces[@]}"
        fi
        return 0
    fi

    case "${#externals[@]}" in
        0)
            log "single internal monitor; assigning all workspaces to $INTERNAL_OUTPUT"
            assign_workspace_range "$INTERNAL_OUTPUT" "${workspaces[@]}"
            ;;
        1)
            log "internal plus one external ${externals[0]}; assigning 1-4 internal and 5-10 external"
            assign_workspace_range "$INTERNAL_OUTPUT" 1 2 3 4
            assign_workspace_range "${externals[0]}" 5 6 7 8 9 10
            ;;
        *)
            log "internal plus two externals ${externals[0]}, ${externals[1]}; assigning 1-3 internal, 4-6 external 1, 7-10 external 2"
            assign_workspace_range "$INTERNAL_OUTPUT" 1 2 3
            assign_workspace_range "${externals[0]}" 4 5 6
            assign_workspace_range "${externals[1]}" 7 8 9 10
            ;;
    esac
}

monitor_eval() {
    hyprctl eval "$1" >/dev/null
}

instance_alive() {
    local runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

    [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || return 1
    [ -S "$runtime_dir/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ]
}

pid_instance_signature() {
    local pid="$1"

    tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null \
        | sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p'
}

internal_on() {
    log "enabling $INTERNAL_OUTPUT"
    monitor_eval "hl.monitor({ output = \"$INTERNAL_OUTPUT\", mode = \"preferred\", position = \"auto\", scale = $INTERNAL_SCALE, disabled = false })"
    wait_for_internal_active || true
    assign_workspace_policy
}

internal_off() {
    local external

    external=$(first_external)
    if [ -z "$external" ]; then
        log "refusing to disable $INTERNAL_OUTPUT without an active external monitor"
        return 0
    fi

    move_workspaces_from_internal "$external"
    log "disabling $INTERNAL_OUTPUT"
    monitor_eval "hl.monitor({ output = \"$INTERNAL_OUTPUT\", disabled = true })"
}

apply_state() {
    local lid
    local external

    lid=$(lid_state)
    external=$(first_external)

    if [ "$lid" = "closed" ] && [ -n "$external" ]; then
        log "applying docked state with lid closed and external $external"
        internal_off
        assign_workspace_policy
    else
        log "applying mobile/open state with lid $lid"
        internal_on
    fi
}

watch_state() {
    local current
    local previous=""
    local status

    log "starting monitor state watcher for instance ${HYPRLAND_INSTANCE_SIGNATURE:-unknown}"
    while true; do
        if ! instance_alive; then
            log "hyprland instance ${HYPRLAND_INSTANCE_SIGNATURE:-unknown} is gone; watcher exiting"
            exit 0
        fi

        current="$(lid_state)|$(monitor_signature)"
        if [ "$current" != "$previous" ]; then
            log "monitor state changed: ${previous:-initial} -> $current"
            set +e
            apply_state
            status=$?
            set -e

            if [ "$status" -ne 0 ]; then
                log "monitor state apply failed with status $status; watcher will retry"
            fi
            previous="$current"
        fi

        sleep "$WATCH_INTERVAL"
    done
}

start_watch() {
    local script_path
    local pid

    script_path=$(readlink -f "$0")

    if [ -f "$WATCH_PID_FILE" ]; then
        pid=$(cat "$WATCH_PID_FILE" 2>/dev/null || true)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            if [ "$(pid_instance_signature "$pid")" = "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
                exit 0
            fi
            log "killing stale watcher $pid bound to a dead hyprland instance"
            kill "$pid" 2>/dev/null || true
        fi
    fi

    log "launching monitor state watcher"
    nohup "$script_path" watch >> "$LOG_FILE" 2>&1 &
    printf '%s\n' "$!" > "$WATCH_PID_FILE"
}

toggle_internal() {
    if internal_active; then
        internal_off
    else
        internal_on
    fi
}

print_status() {
    local lid
    local internal
    local external
    local text
    local class
    local tooltip

    lid=$(lid_state)
    external=$(external_list)

    if internal_active; then
        internal="on"
    else
        internal="off"
    fi

    if [ -n "$external" ] && [ "$lid" = "closed" ] && [ "$internal" = "off" ]; then
        text="Docked"
        class="docked"
    elif [ -n "$external" ]; then
        text="External"
        class="external"
    else
        text="Mobile"
        class="mobile"
    fi

    tooltip="Lid: $lid | Internal $INTERNAL_OUTPUT: $internal | External: ${external:-none}"

    printf '{"text":%s,"tooltip":%s,"class":%s,"internal":%s,"external":%s,"lid":%s}\n' \
        "$(printf '%s' "$text" | json_escape)" \
        "$(printf '%s' "$tooltip" | json_escape)" \
        "$(printf '%s' "$class" | json_escape)" \
        "$(printf '%s' "$internal" | json_escape)" \
        "$(printf '%s' "${external:-none}" | json_escape)" \
        "$(printf '%s' "$lid" | json_escape)"
}

case "${1:-status}" in
    apply)
        apply_state
        ;;
    internal-on)
        internal_on
        ;;
    internal-off)
        internal_off
        ;;
    internal-toggle)
        toggle_internal
        ;;
    watch)
        watch_state
        ;;
    start-watch)
        start_watch
        ;;
    status)
        print_status
        ;;
    *)
        echo "Usage: $0 [apply|internal-on|internal-off|internal-toggle|watch|start-watch|status]" >&2
        exit 2
        ;;
esac
