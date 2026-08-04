#!/usr/bin/env bash

install_hyprbars_plugin() {
    [ "$STEP_PLUGINS" -eq 1 ] || return 0

    if [ "$HYPRLAND_INSTALLED" -eq 0 ]; then
        ui_warn "Skipping Hyprbars plugin: Hyprland is not installed."
        return 0
    fi

    if ! command -v hyprpm >/dev/null 2>&1; then
        ui_warn "Skipping Hyprbars plugin: hyprpm is not available."
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        ui_info "Would run hyprpm update, add hyprland-plugins, enable hyprbars, and reload if inside Hyprland."
        return 0
    fi

    if ! hyprpm update; then
        ui_warn "hyprpm update failed."
        return 0
    fi

    if ! hyprpm add https://github.com/hyprwm/hyprland-plugins; then
        ui_warn "Could not add Hyprland plugins repository. It may already be configured."
    fi

    if ! hyprpm enable hyprbars; then
        ui_warn "Could not enable Hyprbars."
        return 0
    fi

    if [ "$IN_HYPRLAND" -eq 1 ]; then
        hyprpm reload -n || ui_warn "Hyprbars enabled but plugin reload failed."
    fi

    PLUGIN_RESULT="Hyprbars plugin enabled."

    return 0
}
