#!/usr/bin/env bash
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$INSTALLER_DIR/../.." && pwd)"
BACKUP_DIR="$HOME/.config/hypr_backup_$(date +%Y%m%d_%H%M%S)"

MODE=""
DRY_RUN=0
UI_BACKEND="text"

STEP_DEPS=0
STEP_CONFIG=0
STEP_WALLPAPERS=0
STEP_PLUGINS=0
STEP_GPU=0
STEP_SERVICES=0
STEP_START=0

DISTRO_ID="unknown"
DISTRO_NAME="Unknown Linux"
DISTRO_FAMILY="unsupported"
PACKAGE_MANAGER="none"
HYPRLAND_INSTALLED=0
HYPRCTL_INSTALLED=0
IN_HYPRLAND=0
HYPRLAND_VERSION=""
HYPRCTL_VERSION=""

WARNINGS=()
ERRORS=()
MODULE_NAMES=()
MODULES_SELECTED=()
PACKAGES_TO_INSTALL=()
AUR_TO_INSTALL=()
MANUAL_PACKAGE_NOTES=()
PACKAGES_INSTALLED=()
CONFIG_LINKED=()
BACKED_UP_CONFIGS=()
RESTORE_TARGETS=()
SERVICES_ENABLED=()
HARDCODED_PATHS=()
MISSING_REQUIRED_BEFORE=()
MISSING_FEATURE_BEFORE=()
MISSING_OPTIONAL_BEFORE=()
MISSING_REQUIRED_AFTER=()
MISSING_FEATURE_AFTER=()
MISSING_OPTIONAL_AFTER=()
WALLPAPER_RESULT=""
PLUGIN_RESULT=""
START_RESULT=""

# shellcheck source=lib/summary.sh
. "$INSTALLER_DIR/lib/summary.sh"
# shellcheck source=lib/ui.sh
. "$INSTALLER_DIR/lib/ui.sh"
# shellcheck source=lib/distro.sh
. "$INSTALLER_DIR/lib/distro.sh"
# shellcheck source=lib/checks.sh
. "$INSTALLER_DIR/lib/checks.sh"
# shellcheck source=lib/packages.sh
. "$INSTALLER_DIR/lib/packages.sh"
# shellcheck source=lib/config.sh
. "$INSTALLER_DIR/lib/config.sh"
# shellcheck source=lib/wallpapers.sh
. "$INSTALLER_DIR/lib/wallpapers.sh"
# shellcheck source=lib/plugins.sh
. "$INSTALLER_DIR/lib/plugins.sh"
# shellcheck source=lib/services.sh
. "$INSTALLER_DIR/lib/services.sh"

usage() {
    cat <<EOF
Usage: bash appendix/installer/install.sh [mode]

Modes:
  --auto      Automatic install with required packages, config, safe wallpapers, services.
  --manual    Manual/custom install with checklist choices.
  --dry-run   Detect system and print the plan without modifying anything.
  -h, --help  Show this help.
EOF
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --auto)
                MODE="auto"
                ;;
            --manual)
                MODE="manual"
                ;;
            --dry-run)
                if [ -z "$MODE" ]; then
                    MODE="dry-run"
                fi
                DRY_RUN=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                printf 'Unknown option: %s\n' "$1" >&2
                usage
                exit 1
                ;;
        esac
        shift
    done
}

reset_steps() {
    STEP_DEPS=0
    STEP_CONFIG=0
    STEP_WALLPAPERS=0
    STEP_PLUGINS=0
    STEP_GPU=0
    STEP_SERVICES=0
    STEP_START=0
}

select_auto_steps() {
    reset_steps
    STEP_DEPS=1
    STEP_CONFIG=1
    STEP_WALLPAPERS=1
    STEP_SERVICES=1
}

select_dry_run_steps() {
    reset_steps
    DRY_RUN=1
    STEP_DEPS=1
    STEP_CONFIG=1
    STEP_WALLPAPERS=1
    STEP_PLUGINS=1
    STEP_SERVICES=1
}

select_manual_steps() {
    local choices
    local choice

    reset_steps
    choices="$(ui_choose_manual_steps)"

    for choice in $choices; do
        case "$choice" in
            deps) STEP_DEPS=1 ;;
            config) STEP_CONFIG=1 ;;
            wallpapers) STEP_WALLPAPERS=1 ;;
            plugins) STEP_PLUGINS=1 ;;
            gpu) STEP_GPU=1 ;;
            services) STEP_SERVICES=1 ;;
            start) STEP_START=1 ;;
        esac
    done
}

choose_mode_if_needed() {
    if [ -n "$MODE" ]; then
        return
    fi

    MODE="$(ui_choose_mode)"
    [ "$MODE" = "dry-run" ] && DRY_RUN=1
}

select_steps_for_mode() {
    if [ "$DRY_RUN" -eq 1 ] && [ "$MODE" = "manual" ]; then
        select_dry_run_steps
        return
    fi

    case "$MODE" in
        auto)
            select_auto_steps
            ;;
        manual)
            select_manual_steps
            ;;
        dry-run)
            select_dry_run_steps
            ;;
        *)
            ui_error "Unknown mode: $MODE"
            exit 1
            ;;
    esac
}

adjust_for_distro_support() {
    if distro_supports_packages; then
        return
    fi

    if [ "$STEP_DEPS" -eq 1 ]; then
        ui_warn "Package installation disabled on unsupported distro."
        STEP_DEPS=0
    fi

    if [ "$HYPRLAND_INSTALLED" -eq 0 ] && [ "$MODE" = "auto" ]; then
        ui_error "Automatic install cannot continue on unsupported distro without Hyprland installed."
        STEP_CONFIG=0
        STEP_WALLPAPERS=0
        STEP_SERVICES=0
    fi
}

run_selected_steps() {
    install_packages
    check_hyprland_installed
    install_config_links
    install_user_config
    install_modules
    install_wallpapers
    install_hyprbars_plugin
    enable_services
    start_or_reload_hyprland
}

main() {
    parse_args "$@"
    ui_init

    ui_title "Aquatic Abyss Experimental Installer"
    detect_distro
    print_distro_report

    check_hyprland_tools
    check_dependency_report "before"
    scan_hardcoded_paths

    choose_mode_if_needed
    select_steps_for_mode
    adjust_for_distro_support
    select_modules
    show_plan

    if [ "$MODE" = "manual" ] && [ "$DRY_RUN" -eq 0 ]; then
        ui_pause_for_plan || {
            ui_info "Install cancelled."
            exit 0
        }
    fi

    run_selected_steps
    check_dependency_report "after"
    show_summary
}

main "$@"
