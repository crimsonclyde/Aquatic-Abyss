#!/usr/bin/env bash

print_list() {
    local title="$1"
    shift || true

    printf '%s:\n' "$title"
    if [ "$#" -eq 0 ]; then
        printf '  none\n'
        return
    fi

    local item
    for item in "$@"; do
        printf '  - %s\n' "$item"
    done
}

show_plan() {
    package_plan

    ui_title "Install Plan"
    ui_info "Mode: $MODE"
    ui_info "Dry run: $DRY_RUN"
    ui_info "Steps:"
    [ "$STEP_DEPS" -eq 1 ] && ui_info "  - install dependencies"
    [ "$STEP_CONFIG" -eq 1 ] && ui_info "  - install config symlinks"
    [ "$STEP_WALLPAPERS" -eq 1 ] && ui_info "  - copy repo wallpapers"
    [ "$STEP_PLUGINS" -eq 1 ] && ui_info "  - install Hyprbars plugin"
    [ "$STEP_GPU" -eq 1 ] && ui_info "  - install GPU tools"
    [ "$STEP_SERVICES" -eq 1 ] && ui_info "  - enable/start useful services"
    [ "$STEP_START" -eq 1 ] && ui_info "  - start/reload Hyprland"

    print_list "Package candidates" "${PACKAGES_TO_INSTALL[@]}"
    print_list "AUR package candidates" "${AUR_TO_INSTALL[@]}"
    print_list "Manual or unavailable packages" "${MANUAL_PACKAGE_NOTES[@]}"
}

show_summary() {
    ui_title "Summary"
    ui_info "Mode: $MODE"
    print_list "Installed package candidates" "${PACKAGES_INSTALLED[@]}"
    print_list "Config links" "${CONFIG_LINKED[@]}"
    print_list "Backed up configs" "${BACKED_UP_CONFIGS[@]}"
    ui_info "Wallpapers: ${WALLPAPER_RESULT:-No wallpaper action.}"
    ui_info "Plugin: ${PLUGIN_RESULT:-No plugin action.}"
    print_list "Services enabled/started" "${SERVICES_ENABLED[@]}"
    ui_info "Hyprland action: ${START_RESULT:-No start/reload action.}"

    ui_title "Restore Command"
    restore_command

    if [ "${#HARDCODED_PATHS[@]}" -gt 0 ]; then
        ui_title "Hardcoded User Paths"
        print_list "Hardcoded user paths found" "${HARDCODED_PATHS[@]}"
        ui_warn "These should be replaced with HOME-relative paths before public release."
    fi

    ui_title "Warnings"
    print_list "Warnings" "${WARNINGS[@]}"

    ui_title "Errors"
    print_list "Errors" "${ERRORS[@]}"

    if [ "${#MISSING_REQUIRED_AFTER[@]}" -gt 0 ] || [ "${#MISSING_FEATURE_AFTER[@]}" -gt 0 ]; then
        ui_title "Remaining Missing Tools"
        print_list "Required missing" "${MISSING_REQUIRED_AFTER[@]}"
        print_list "Feature missing" "${MISSING_FEATURE_AFTER[@]}"
        print_list "Optional missing" "${MISSING_OPTIONAL_AFTER[@]}"
    fi
}
