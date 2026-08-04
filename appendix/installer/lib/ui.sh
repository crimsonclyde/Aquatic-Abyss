#!/usr/bin/env bash

ui_init() {
    UI_BACKEND="text"

    if command -v whiptail >/dev/null 2>&1; then
        UI_BACKEND="whiptail"
    elif command -v dialog >/dev/null 2>&1; then
        UI_BACKEND="dialog"
    fi
}

ui_title() {
    printf '\n%s\n' "== $1 =="
}

ui_info() {
    printf '%s\n' "$1"
}

ui_warn() {
    printf 'Warning: %s\n' "$1" >&2
    WARNINGS+=("$1")
}

ui_error() {
    printf 'Error: %s\n' "$1" >&2
    ERRORS+=("$1")
}

ui_confirm() {
    local prompt="$1"
    local answer

    case "$UI_BACKEND" in
        whiptail)
            whiptail --title "Acquatic Abyss Installer" --yesno "$prompt" 10 70
            return $?
            ;;
        dialog)
            dialog --title "Acquatic Abyss Installer" --yesno "$prompt" 10 70
            return $?
            ;;
    esac

    while true; do
        read -r -p "$prompt [y/N] " answer || return 1
        case "${answer,,}" in
            y|yes)
                return 0
                ;;
            ""|n|no)
                return 1
                ;;
            *)
                printf 'Please answer yes or no.\n'
                ;;
        esac
    done
}

ui_choose_mode() {
    local choice

    case "$UI_BACKEND" in
        whiptail)
            choice=$(whiptail --title "Acquatic Abyss Installer" --menu "Choose install mode:" 14 70 3 \
                "auto" "Automatic install" \
                "manual" "Manual/custom install" \
                "dry-run" "Dry run" 3>&1 1>&2 2>&3) || exit 1
            printf '%s\n' "$choice"
            return
            ;;
        dialog)
            choice=$(dialog --stdout --title "Acquatic Abyss Installer" --menu "Choose install mode:" 14 70 3 \
                "auto" "Automatic install" \
                "manual" "Manual/custom install" \
                "dry-run" "Dry run") || exit 1
            printf '%s\n' "$choice"
            return
            ;;
    esac

    printf '\nChoose install mode:\n'
    printf '1. Automatic install\n'
    printf '2. Manual/custom install\n'
    printf '3. Dry run\n'

    while true; do
        read -r -p "Selection [1-3]: " choice || exit 1
        case "$choice" in
            1) printf 'auto\n'; return ;;
            2) printf 'manual\n'; return ;;
            3) printf 'dry-run\n'; return ;;
            *) printf 'Choose 1, 2, or 3.\n' ;;
        esac
    done
}

ui_choose_manual_steps() {
    local result
    local choices

    case "$UI_BACKEND" in
        whiptail)
            result=$(whiptail --title "Manual install choices" --checklist "Choose steps:" 22 78 10 \
                "deps" "Install dependencies" ON \
                "config" "Install config symlinks" ON \
                "wallpapers" "Copy repo wallpapers" ON \
                "plugins" "Install Hyprbars plugin" OFF \
                "gpu" "Install GPU tools" OFF \
                "services" "Enable/start useful services" OFF \
                "start" "Start/reload Hyprland" OFF 3>&1 1>&2 2>&3) || exit 1
            printf '%s\n' "$result" | tr -d '"'
            return
            ;;
        dialog)
            result=$(dialog --stdout --title "Manual install choices" --checklist "Choose steps:" 22 78 10 \
                "deps" "Install dependencies" on \
                "config" "Install config symlinks" on \
                "wallpapers" "Copy repo wallpapers" on \
                "plugins" "Install Hyprbars plugin" off \
                "gpu" "Install GPU tools" off \
                "services" "Enable/start useful services" off \
                "start" "Start/reload Hyprland" off) || exit 1
            printf '%s\n' "$result"
            return
            ;;
    esac

    printf '\nManual/custom install choices.\n'
    printf 'Answer yes or no for each step.\n'
    choices=()
    ui_confirm "Install dependencies?" && choices+=("deps")
    ui_confirm "Install config symlinks?" && choices+=("config")
    ui_confirm "Copy repo wallpapers?" && choices+=("wallpapers")
    ui_confirm "Install Hyprbars plugin?" && choices+=("plugins")
    ui_confirm "Install GPU tools?" && choices+=("gpu")
    ui_confirm "Enable/start useful services?" && choices+=("services")
    ui_confirm "Start/reload Hyprland?" && choices+=("start")
    printf '%s\n' "${choices[@]}"
}

ui_pause_for_plan() {
    if [ "$MODE" = "auto" ] || [ "$MODE" = "dry-run" ]; then
        return
    fi

    ui_confirm "Proceed with this install plan?"
}
