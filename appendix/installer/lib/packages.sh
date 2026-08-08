#!/usr/bin/env bash

ARCH_CORE_PACKAGES=(
    hyprland
    waybar
    wofi
    wlogout
    kitty
    nautilus
    git
    curl
    which
    jq
    libnotify
    ttf-jetbrains-mono-nerd
)

ARCH_HYPR_PACKAGES=(
    hypridle
    hyprlock
    hyprpaper
    hyprshot
    hyprpm
)

ARCH_DESKTOP_PACKAGES=(
    network-manager-applet
    blueman
    bluez
    brightnessctl
    pamixer
    swaync
    upower
    lm_sensors
    power-profiles-daemon
    wireplumber
    cliphist
    wl-clipboard
    satty
    nwg-displays
    btop
    playerctl
    chromium
    ksshaskpass
)

# Preferred from the distro repositories when they carry them (CachyOS ships
# waypaper in its cachyos repo); install_aur_packages sorts the list at
# install time and only the true leftovers are offered as AUR builds.
ARCH_AUR_PACKAGES=(
    hyprdynamicmonitors-bin
    waypaper
    aylurs-gtk-shell
)

ARCH_GPU_PACKAGES_NVIDIA=(nvidia-utils)
ARCH_GPU_PACKAGES_INTEL=(intel-gpu-tools)

DEBIAN_CORE_PACKAGES=(
    hyprland
    waybar
    wofi
    wlogout
    kitty
    nautilus
    git
    curl
    debianutils
    jq
    libnotify-bin
    fonts-jetbrains-mono
)

DEBIAN_HYPR_PACKAGES=(
    hypridle
    hyprlock
    hyprpaper
)

DEBIAN_DESKTOP_PACKAGES=(
    network-manager-gnome
    blueman
    bluez
    brightnessctl
    pamixer
    sway-notification-center
    upower
    lm-sensors
    power-profiles-daemon
    wireplumber
    wl-clipboard
    btop
    playerctl
    chromium
)

DEBIAN_GPU_PACKAGES_NVIDIA=(nvidia-utils)
DEBIAN_GPU_PACKAGES_INTEL=(intel-gpu-tools)

DEBIAN_MANUAL_PACKAGES=(
    hyprshot
    hyprpm
    hyprdynamicmonitors-bin
    waypaper
    aylurs-gtk-shell
    satty
    nwg-displays
    cliphist
    joplin-desktop
    vscodium
    ttf-jetbrains-mono-nerd
)

discover_modules() {
    local dir

    MODULE_NAMES=()

    for dir in "$REPO_DIR"/modules/*/; do
        [ -f "$dir/module.sh" ] || continue
        MODULE_NAMES+=("$(basename "$dir")")
    done
}

select_modules() {
    local name

    MODULES_SELECTED=()
    discover_modules

    if [ "$STEP_DEPS" -eq 0 ] && [ "$STEP_CONFIG" -eq 0 ]; then
        return 0
    fi

    for name in "${MODULE_NAMES[@]}"; do
        if [ "$MODE" = "manual" ] && [ "$DRY_RUN" -eq 0 ]; then
            ui_confirm "Include module '$name' (packages, sudoers, install hooks)?" || continue
        fi
        MODULES_SELECTED+=("$name")
    done

    return 0
}

read_package_list() {
    local file="$1"

    [ -f "$file" ] || return 0
    grep -vE '^[[:space:]]*(#|$)' "$file" || true
}

module_package_plan() {
    local name pkg

    for name in "${MODULES_SELECTED[@]}"; do
        case "$DISTRO_FAMILY" in
            arch)
                while IFS= read -r pkg; do
                    PACKAGES_TO_INSTALL+=("$pkg")
                done < <(read_package_list "$REPO_DIR/modules/$name/packages.arch")
                while IFS= read -r pkg; do
                    AUR_TO_INSTALL+=("$pkg")
                done < <(read_package_list "$REPO_DIR/modules/$name/packages.aur")
                ;;
            debian)
                while IFS= read -r pkg; do
                    PACKAGES_TO_INSTALL+=("$pkg")
                done < <(read_package_list "$REPO_DIR/modules/$name/packages.debian")
                ;;
        esac
    done

    return 0
}

install_module_sudoers() {
    local dir="$1"
    local name="$2"
    local source="$dir/sudoers"
    # zz- prefix: sudoers is last-match-wins and reads sudoers.d alphabetically,
    # so this must sort after generic %wheel rules to keep NOPASSWD effective.
    local target="/etc/sudoers.d/zz-aquatic-$name"

    [ -f "$source" ] || return 0

    if [ "$DRY_RUN" -eq 1 ]; then
        ui_info "Would install sudoers rule $target"
        return 0
    fi

    if sudo test -f "$target" 2>/dev/null; then
        return 0
    fi

    if ! visudo -cf "$source" >/dev/null 2>&1; then
        ui_warn "Invalid sudoers file in module $name; skipping."
        return 0
    fi

    if [ "$MODE" = "manual" ]; then
        ui_confirm "Install sudoers rule for module $name ($target)?" || return 0
    fi

    sudo install -m 0440 -o root -g root "$source" "$target"
    ui_info "Installed sudoers rule for $name."

    return 0
}

run_module_install_hook() {
    local dir="$1"
    local name="$2"

    [ -f "$dir/install.sh" ] || return 0

    if [ "$DRY_RUN" -eq 1 ]; then
        ui_info "Would run install hook for module $name"
        return 0
    fi

    bash "$dir/install.sh" "$REPO_DIR" || ui_warn "Module $name install hook failed."

    return 0
}

install_modules() {
    local name dir

    [ "$STEP_CONFIG" -eq 1 ] || return 0

    for name in "${MODULES_SELECTED[@]}"; do
        dir="$REPO_DIR/modules/$name"
        install_module_sudoers "$dir" "$name"
        run_module_install_hook "$dir" "$name"
    done

    return 0
}

package_plan() {
    PACKAGES_TO_INSTALL=()
    AUR_TO_INSTALL=()
    MANUAL_PACKAGE_NOTES=()

    case "$DISTRO_FAMILY" in
        arch)
            PACKAGES_TO_INSTALL+=("${ARCH_CORE_PACKAGES[@]}" "${ARCH_HYPR_PACKAGES[@]}" "${ARCH_DESKTOP_PACKAGES[@]}")
            AUR_TO_INSTALL+=("${ARCH_AUR_PACKAGES[@]}")
            [ "$STEP_GPU" -eq 1 ] && PACKAGES_TO_INSTALL+=("${ARCH_GPU_PACKAGES_NVIDIA[@]}" "${ARCH_GPU_PACKAGES_INTEL[@]}")
            ;;
        debian)
            PACKAGES_TO_INSTALL+=("${DEBIAN_CORE_PACKAGES[@]}" "${DEBIAN_HYPR_PACKAGES[@]}" "${DEBIAN_DESKTOP_PACKAGES[@]}")
            [ "$STEP_GPU" -eq 1 ] && PACKAGES_TO_INSTALL+=("${DEBIAN_GPU_PACKAGES_NVIDIA[@]}" "${DEBIAN_GPU_PACKAGES_INTEL[@]}")
            MANUAL_PACKAGE_NOTES+=("${DEBIAN_MANUAL_PACKAGES[@]}")
            ;;
        *)
            MANUAL_PACKAGE_NOTES+=("Unsupported distro: automatic package installation disabled.")
            ;;
    esac

    module_package_plan

    return 0
}

install_packages() {
    package_plan

    if [ "$STEP_DEPS" -ne 1 ]; then
        return
    fi

    if ! distro_supports_packages; then
        ui_warn "Skipping dependency installation on unsupported distro."
        return
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        print_list "Would install packages" "${PACKAGES_TO_INSTALL[@]}"
        print_list "Would install AUR packages" "${AUR_TO_INSTALL[@]}"
        print_list "Manual or unavailable packages" "${MANUAL_PACKAGE_NOTES[@]}"
        return
    fi

    case "$DISTRO_FAMILY" in
        arch)
            sudo pacman -S --needed "${PACKAGES_TO_INSTALL[@]}"
            install_aur_packages
            ;;
        debian)
            sudo apt update
            sudo apt install -y "${PACKAGES_TO_INSTALL[@]}" || ui_warn "Some Debian packages were unavailable. See package manager output."
            ;;
    esac

    PACKAGES_INSTALLED=("${PACKAGES_TO_INSTALL[@]}")
    print_list "Manual or unavailable packages" "${MANUAL_PACKAGE_NOTES[@]}"

    return 0
}

install_aur_packages() {
    local aur_helper="" pkg repo_pkgs=() aur_pkgs=()

    [ "${#AUR_TO_INSTALL[@]}" -gt 0 ] || return

    # Prefer the distro repositories; only what they do not carry is offered
    # as an AUR build. AUR packages are user-submitted and unreviewed, so
    # nothing is fetched from there without an explicit yes (auto mode never
    # asks and therefore stays repo-only).
    for pkg in "${AUR_TO_INSTALL[@]}"; do
        if pacman -Si "$pkg" >/dev/null 2>&1; then
            repo_pkgs+=("$pkg")
        else
            aur_pkgs+=("$pkg")
        fi
    done

    if [ "${#repo_pkgs[@]}" -gt 0 ]; then
        sudo pacman -S --needed "${repo_pkgs[@]}" || ui_warn "Package installation failed for: ${repo_pkgs[*]}"
    fi

    [ "${#aur_pkgs[@]}" -gt 0 ] || return 0

    if [ "$MODE" = "auto" ] || ! ui_confirm "Not in the distro repositories: ${aur_pkgs[*]}. Build these from the AUR (user-submitted, unreviewed)?"; then
        ui_warn "Skipped AUR packages. Install manually if wanted: ${aur_pkgs[*]}"
        MANUAL_PACKAGE_NOTES+=("${aur_pkgs[@]}")
        return 0
    fi

    if command -v paru >/dev/null 2>&1; then
        aur_helper="paru"
    elif command -v yay >/dev/null 2>&1; then
        aur_helper="yay"
    fi

    if [ -z "$aur_helper" ]; then
        ui_warn "No AUR helper found. Install manually: ${aur_pkgs[*]}"
        MANUAL_PACKAGE_NOTES+=("${aur_pkgs[@]}")
        return
    fi

    "$aur_helper" -S --needed "${aur_pkgs[@]}" || ui_warn "AUR package installation failed."

    return 0
}
