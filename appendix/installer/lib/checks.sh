#!/usr/bin/env bash

REQUIRED_COMMANDS=(
    Hyprland
    hyprctl
    waybar
    wofi
    kitty
    notify-send
    curl
    which
    jq
    ags
)

FEATURE_COMMANDS=(
    bluetoothctl
    btop
    playerctl
    chromium
    hyprpaper
    hypridle
    hyprlock
    hyprshot
    swaync-client
    wl-copy
    cliphist
)

OPTIONAL_COMMANDS=(
    tailscale
    flatpak
    element-desktop
    joplin-desktop
    vscodium
    nvidia-smi
    intel_gpu_top
)

missing_commands_from() {
    local command_name

    for command_name in "$@"; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            printf '%s\n' "$command_name"
        fi
    done
}

check_dependency_report() {
    local phase="$1"
    local missing_required=()
    local missing_feature=()
    local missing_optional=()

    mapfile -t missing_required < <(missing_commands_from "${REQUIRED_COMMANDS[@]}")
    mapfile -t missing_feature < <(missing_commands_from "${FEATURE_COMMANDS[@]}")
    mapfile -t missing_optional < <(missing_commands_from "${OPTIONAL_COMMANDS[@]}")

    ui_title "Dependency Check: $phase"
    print_list "Required missing" "${missing_required[@]}"
    print_list "Feature missing" "${missing_feature[@]}"
    print_list "Optional missing" "${missing_optional[@]}"

    if [ "$phase" = "before" ]; then
        MISSING_REQUIRED_BEFORE=("${missing_required[@]}")
        MISSING_FEATURE_BEFORE=("${missing_feature[@]}")
        MISSING_OPTIONAL_BEFORE=("${missing_optional[@]}")
    else
        MISSING_REQUIRED_AFTER=("${missing_required[@]}")
        MISSING_FEATURE_AFTER=("${missing_feature[@]}")
        MISSING_OPTIONAL_AFTER=("${missing_optional[@]}")
    fi
}

check_hyprland_installed() {
    HYPRLAND_INSTALLED=0
    HYPRCTL_INSTALLED=0

    command -v Hyprland >/dev/null 2>&1 && HYPRLAND_INSTALLED=1
    command -v hyprctl >/dev/null 2>&1 && HYPRCTL_INSTALLED=1

    if [ "$HYPRLAND_INSTALLED" -eq 1 ]; then
        HYPRLAND_VERSION="$(Hyprland --version 2>/dev/null | head -n 1 || true)"
    else
        HYPRLAND_VERSION=""
    fi
}

check_hyprland_session() {
    IN_HYPRLAND=0

    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        IN_HYPRLAND=1
    elif [ "${XDG_CURRENT_DESKTOP:-}" = "Hyprland" ]; then
        IN_HYPRLAND=1
    fi
}

check_hyprland_tools() {
    check_hyprland_installed
    check_hyprland_session

    ui_title "Hyprland Check"
    if [ "$HYPRLAND_INSTALLED" -eq 1 ]; then
        ui_info "Hyprland: installed ${HYPRLAND_VERSION:+($HYPRLAND_VERSION)}"
    else
        ui_info "Hyprland: missing"
    fi

    if [ "$HYPRCTL_INSTALLED" -eq 1 ]; then
        ui_info "hyprctl: installed"
    else
        ui_info "hyprctl: missing"
    fi

    if [ "$IN_HYPRLAND" -eq 1 ]; then
        ui_info "Current session: Hyprland"
        if command -v hyprctl >/dev/null 2>&1; then
            HYPRCTL_VERSION="$(hyprctl version 2>/dev/null | head -n 1 || true)"
            [ -n "$HYPRCTL_VERSION" ] && ui_info "hyprctl version: $HYPRCTL_VERSION"
        fi
    else
        ui_info "Current session: not Hyprland. Reload/start actions may be skipped."
    fi
}

scan_hardcoded_paths() {
    local result

    HARDCODED_PATHS=()
    result=$(grep -RIn --exclude-dir=.git --exclude='*.png' --exclude='*.jpg' --exclude='*.jpeg' -E '/home/[A-Za-z0-9._-]+/' "$REPO_DIR/.config" "$REPO_DIR/scripts" "$REPO_DIR/docs" 2>/dev/null || true)

    if [ -n "$result" ]; then
        mapfile -t HARDCODED_PATHS <<< "$result"
    fi
}
