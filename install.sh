#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${AQUATIC_ABYSS_REPO:-https://github.com/crimsonclyde/Acquatic-Abyss.git}"
REPO_DIR="${AQUATIC_ABYSS_DIR:-$HOME/Documents/Repositories/github/Acquatic-Abyss}"
CONFIG_DIR="$HOME/.config"
BACKUP_DIR="$HOME/.config/hypr_backup_$(date +%Y%m%d_%H%M%S)"
DEFAULT_WALLPAPER_DIR="$REPO_DIR/appendix/wallpapers"
WALLPAPER_TARGET_DIR="$HOME/Pictures/Wallpapers"

INSTALL_DEPS=0
INSTALL_PLUGINS=0
START_HYPRLAND=0
ORIGINAL_ARGS=("$@")

PACMAN_PACKAGES=(
    hyprland
    waybar
    wofi
    wlogout
    kitty
    nautilus
    network-manager-applet
    blueman
    brightnessctl
    pamixer
    hypridle
    hyprlock
    hyprpaper
    hyprshot
    swaync
    upower
    jq
    lm_sensors
    power-profiles-daemon
    wireplumber
    cliphist
    wl-clipboard
    satty
    nwg-displays
    ksshaskpass
    git
)

AUR_PACKAGES=(
    hyprdynamicmonitors-bin
    waypaper
    aylurs-gtk-shell
)

OPTIONAL_PACKAGES=(
    pavucontrol
)

usage() {
    cat <<EOF
Usage: ./install.sh [options]

Options:
  --deps       Install required Arch/CachyOS packages with pacman and paru/yay.
  --plugins    Install and enable the official Hyprbars plugin with hyprpm.
  --start      Start Hyprland after installing the config.
  -h, --help   Show this help.

Environment:
  AQUATIC_ABYSS_REPO  Git repository to clone when run as a remote script.
  AQUATIC_ABYSS_DIR   Local checkout path. Default: $REPO_DIR
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --deps)
            INSTALL_DEPS=1
            ;;
        --plugins)
            INSTALL_PLUGINS=1
            ;;
        --start)
            START_HYPRLAND=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
    shift
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

confirm() {
    local prompt="$1"
    local answer

    while true; do
        if ! read -r -p "$prompt [y/N] " answer; then
            echo
            return 1
        fi

        case "${answer,,}" in
            y|yes)
                return 0
                ;;
            ""|n|no)
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

bootstrap_repo() {
    if [ -f "$script_dir/.config/hypr/hyprland.lua" ]; then
        REPO_DIR="$script_dir"
        DEFAULT_WALLPAPER_DIR="$REPO_DIR/appendix/wallpapers"
        return
    fi

    if ! command -v git >/dev/null 2>&1; then
        if [ "$INSTALL_DEPS" -eq 1 ] && command -v pacman >/dev/null 2>&1; then
            echo "Installing git before cloning..."
            sudo pacman -S --needed git
        else
            echo "git is required before this installer can clone $REPO_URL." >&2
            exit 1
        fi
    fi

    if [ ! -d "$REPO_DIR/.git" ]; then
        echo "Cloning config repository into $REPO_DIR..."
        mkdir -p "$(dirname "$REPO_DIR")"
        git clone "$REPO_URL" "$REPO_DIR"
    else
        echo "Updating existing config repository at $REPO_DIR..."
        git -C "$REPO_DIR" pull --ff-only
    fi

    exec "$REPO_DIR/install.sh" "${ORIGINAL_ARGS[@]}"
}

install_dependencies() {
    if ! command -v pacman >/dev/null 2>&1; then
        echo "Dependency installation is only automated for Arch/CachyOS systems." >&2
        exit 1
    fi

    echo "Installing pacman packages..."
    sudo pacman -S --needed "${PACMAN_PACKAGES[@]}" "${OPTIONAL_PACKAGES[@]}"

    local aur_helper=""
    if command -v paru >/dev/null 2>&1; then
        aur_helper="paru"
    elif command -v yay >/dev/null 2>&1; then
        aur_helper="yay"
    fi

    if [ -z "$aur_helper" ]; then
        echo "No AUR helper found. Install these manually: ${AUR_PACKAGES[*]}" >&2
        return
    fi

    echo "Installing AUR packages with $aur_helper..."
    "$aur_helper" -S --needed "${AUR_PACKAGES[@]}"
}

link_config() {
    local source="$1"
    local target="$2"
    local name
    name="$(basename "$source")"

    if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
        echo "$name is already linked."
        return
    fi

    if [ -d "$target" ] || [ -L "$target" ]; then
        echo "Backing up existing $name configuration..."
        mkdir -p "$BACKUP_DIR"
        mv "$target" "$BACKUP_DIR/"
    fi

    echo "Linking $name..."
    ln -s "$source" "$target"
}

install_config() {
    mkdir -p "$CONFIG_DIR"

    link_config "$REPO_DIR/.config/hypr" "$CONFIG_DIR/hypr"
    link_config "$REPO_DIR/.config/hyprdynamicmonitors" "$CONFIG_DIR/hyprdynamicmonitors"
    link_config "$REPO_DIR/.config/waypaper" "$CONFIG_DIR/waypaper"
    link_config "$REPO_DIR/.config/waybar" "$CONFIG_DIR/waybar"
    link_config "$REPO_DIR/.config/ags" "$CONFIG_DIR/ags"
    link_config "$REPO_DIR/.config/wlogout" "$CONFIG_DIR/wlogout"
    link_config "$REPO_DIR/.config/noctalia" "$CONFIG_DIR/noctalia"

    echo "Config installation complete."
    if [ -d "$BACKUP_DIR" ]; then
        echo "Previous configs backed up to $BACKUP_DIR"
    fi
}

install_user_config() {
    local source="$REPO_DIR/config/defaults.env"
    local target_dir="${XDG_CONFIG_HOME:-$HOME/.config}/aquatic-abyss"
    local target="$target_dir/config.env"

    [ -f "$source" ] || return 0

    if [ -f "$target" ]; then
        echo "User config already exists at $target."
        return 0
    fi

    if ! confirm "Copy default app choices to $target (edit it to change terminal, browser, etc.)?"; then
        echo "Skipping user config. Repo defaults will be used."
        return 0
    fi

    mkdir -p "$target_dir"
    cp "$source" "$target"
    echo "User config created at $target."
}

install_wallpapers() {
    local source_dir="$DEFAULT_WALLPAPER_DIR"
    local target_dir="$WALLPAPER_TARGET_DIR"
    local wallpapers=()

    if [ ! -d "$source_dir" ]; then
        echo "Default wallpaper directory not found at $source_dir; skipping wallpapers."
        return
    fi

    if ! confirm "Copy the default Acquatic Abyss wallpapers to $target_dir?"; then
        echo "Skipping default wallpapers."
        return
    fi

    if [ -d "$target_dir" ] && [ -n "$(find "$target_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
        echo "$target_dir already exists and is not empty."
        echo "Be careful: copying the defaults may overwrite files with matching names."
        if ! confirm "Proceed with copying the default wallpapers?"; then
            echo "Skipping default wallpapers."
            return
        fi
    fi

    mkdir -p "$target_dir"

    while IFS= read -r -d '' wallpaper; do
        wallpapers+=("$wallpaper")
    done < <(find "$source_dir" -maxdepth 1 -type f -print0)

    if [ "${#wallpapers[@]}" -eq 0 ]; then
        echo "No default wallpapers found in $source_dir."
        return
    fi

    cp -f "${wallpapers[@]}" "$target_dir/"
    echo "Copied ${#wallpapers[@]} default wallpapers to $target_dir."
}

detect_aur_helper() {
    if command -v paru >/dev/null 2>&1; then
        echo paru
    elif command -v yay >/dev/null 2>&1; then
        echo yay
    fi
}

read_package_list() {
    local file="$1"

    [ -f "$file" ] || return 0
    grep -vE '^[[:space:]]*(#|$)' "$file" || true
}

install_module_packages() {
    local dir="$1"
    local name="$2"
    local packages=()
    local aur_packages=()
    local aur_helper

    [ "$INSTALL_DEPS" -eq 1 ] || return 0
    command -v pacman >/dev/null 2>&1 || return 0

    mapfile -t packages < <(read_package_list "$dir/packages.arch")
    mapfile -t aur_packages < <(read_package_list "$dir/packages.aur")

    if [ "${#packages[@]}" -gt 0 ]; then
        sudo pacman -S --needed "${packages[@]}"
    fi

    if [ "${#aur_packages[@]}" -gt 0 ]; then
        aur_helper="$(detect_aur_helper)"
        if [ -n "$aur_helper" ]; then
            "$aur_helper" -S --needed "${aur_packages[@]}"
        else
            echo "No AUR helper found. Install these manually for $name: ${aur_packages[*]}" >&2
        fi
    fi
}

install_module_sudoers() {
    local dir="$1"
    local name="$2"
    local source="$dir/sudoers"
    # zz- prefix: sudoers is last-match-wins and reads sudoers.d alphabetically,
    # so this must sort after generic %wheel rules to keep NOPASSWD effective.
    local target="/etc/sudoers.d/zz-aquatic-$name"

    [ -f "$source" ] || return 0

    if sudo test -f "$target" 2>/dev/null; then
        return 0
    fi

    if ! visudo -cf "$source" >/dev/null 2>&1; then
        echo "Invalid sudoers file in module $name; skipping." >&2
        return 0
    fi

    if ! confirm "Install sudoers rule for module $name ($target)?"; then
        echo "Skipping sudoers rule for $name."
        return 0
    fi

    sudo install -m 0440 -o root -g root "$source" "$target"
    echo "Sudoers rule for $name installed."
}

run_module_install_hook() {
    local dir="$1"
    local name="$2"

    [ -f "$dir/install.sh" ] || return 0
    bash "$dir/install.sh" "$REPO_DIR" || echo "Module $name install hook failed." >&2
}

install_modules() {
    local dir name

    for dir in "$REPO_DIR"/modules/*/; do
        [ -f "$dir/module.sh" ] || continue
        name="$(basename "$dir")"

        if ! confirm "Set up module '$name' (packages, sudoers, install hooks)?"; then
            echo "Skipping module $name."
            continue
        fi

        install_module_packages "$dir" "$name"
        install_module_sudoers "$dir" "$name"
        run_module_install_hook "$dir" "$name"
    done
}

install_plugins() {
    if ! command -v hyprpm >/dev/null 2>&1; then
        echo "hyprpm is not available. Install Hyprland first, then rerun ./install.sh --plugins." >&2
        exit 1
    fi

    echo "Updating Hyprland plugin headers..."
    hyprpm update

    echo "Adding official Hyprland plugins repository..."
    if ! hyprpm add https://github.com/hyprwm/hyprland-plugins; then
        echo "Repository may already exist; continuing."
    fi

    echo "Enabling Hyprbars..."
    hyprpm enable hyprbars
    hyprpm reload -n
}

start_hyprland() {
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        echo "Hyprland is already running. Reloading config..."
        hyprctl reload
        return
    fi

    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        echo "Starting Hyprland..."
        exec Hyprland --config "$CONFIG_DIR/hypr/hyprland.lua"
    fi

    echo "Config installed. Log out and start Hyprland from a TTY or display manager."
}

bootstrap_repo "$@"

if [ "$INSTALL_DEPS" -eq 1 ]; then
    install_dependencies
fi

install_config
install_user_config
install_wallpapers
install_modules

if [ "$INSTALL_PLUGINS" -eq 1 ]; then
    install_plugins
fi

if [ "$START_HYPRLAND" -eq 1 ]; then
    start_hyprland
else
    echo "Restart Hyprland or run: hyprctl reload"
fi
