#!/usr/bin/env bash

SERVICE_UNITS=(
    NetworkManager
    bluetooth
    power-profiles-daemon
)

vpn_module_selected() {
    local name

    for name in "${MODULES_SELECTED[@]}"; do
        [ "$name" = "vpn-tailscale" ] && return 0
    done

    return 1
}

enable_services() {
    local unit

    [ "$STEP_SERVICES" -eq 1 ] || return 0

    if ! command -v systemctl >/dev/null 2>&1; then
        ui_warn "systemctl is not available; skipping service setup."
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        print_list "Would enable/start services" "${SERVICE_UNITS[@]}"
        if vpn_module_selected; then
            ui_info "Would not start or login tailscaled automatically."
        fi
        return 0
    fi

    for unit in "${SERVICE_UNITS[@]}"; do
        if systemctl list-unit-files "$unit.service" >/dev/null 2>&1; then
            sudo systemctl enable --now "$unit.service" && SERVICES_ENABLED+=("$unit") || ui_warn "Could not enable/start $unit."
        else
            ui_warn "Service unit not found: $unit.service"
        fi
    done

    if vpn_module_selected; then
        ui_info "Tailscale package may be installed, but tailscaled was not started automatically."
    fi

    return 0
}

start_or_reload_hyprland() {
    [ "$STEP_START" -eq 1 ] || return 0

    if [ "$DRY_RUN" -eq 1 ]; then
        ui_info "Would reload Hyprland if running, or start it from a TTY."
        return 0
    fi

    if [ "$IN_HYPRLAND" -eq 1 ]; then
        if command -v hyprctl >/dev/null 2>&1; then
            hyprctl reload && START_RESULT="Hyprland reloaded." || ui_warn "Hyprland reload failed."
        else
            ui_warn "Cannot reload Hyprland: hyprctl is missing."
        fi
        return 0
    fi

    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && command -v Hyprland >/dev/null 2>&1; then
        ui_info "Starting Hyprland..."
        exec Hyprland --config "$HOME/.config/hypr/hyprland.lua"
    fi

    START_RESULT="Hyprland was not started because this is not a TTY-like session."
    ui_warn "$START_RESULT"

    return 0
}
