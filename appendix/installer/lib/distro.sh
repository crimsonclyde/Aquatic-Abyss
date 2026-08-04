#!/usr/bin/env bash

detect_distro() {
    DISTRO_ID="unknown"
    DISTRO_NAME="Unknown Linux"
    DISTRO_FAMILY="unsupported"
    PACKAGE_MANAGER="none"

    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_NAME="${PRETTY_NAME:-${NAME:-Unknown Linux}}"
        local like="${ID_LIKE:-}"

        case "$DISTRO_ID" in
            arch|cachyos)
                DISTRO_FAMILY="arch"
                PACKAGE_MANAGER="pacman"
                ;;
            debian|ubuntu|linuxmint)
                DISTRO_FAMILY="debian"
                PACKAGE_MANAGER="apt"
                ;;
            *)
                if [[ " $like " == *" arch "* ]]; then
                    DISTRO_FAMILY="arch"
                    PACKAGE_MANAGER="pacman"
                elif [[ " $like " == *" debian "* ]] || [[ " $like " == *" ubuntu "* ]]; then
                    DISTRO_FAMILY="debian"
                    PACKAGE_MANAGER="apt"
                fi
                ;;
        esac
    fi
}

distro_supports_packages() {
    [ "$DISTRO_FAMILY" = "arch" ] || [ "$DISTRO_FAMILY" = "debian" ]
}

print_distro_report() {
    ui_title "Detected System"
    ui_info "Distro: $DISTRO_NAME"
    ui_info "Family: $DISTRO_FAMILY"
    ui_info "Package manager: $PACKAGE_MANAGER"

    if ! distro_supports_packages; then
        ui_warn "Unsupported distro for automatic package installation. Config-only install is allowed if Hyprland is already installed."
    fi
}
