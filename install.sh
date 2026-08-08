#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${AQUATIC_ABYSS_REPO:-https://github.com/crimsonclyde/Aquatic-Abyss.git}"
REPO_DIR="${AQUATIC_ABYSS_DIR:-$HOME/Documents/Repositories/github/Aquatic-Abyss}"
# Checkouts from before the 2026-08 "Acquatic"→"Aquatic" rename keep the old
# directory name; reuse them instead of cloning a second copy.
if [ -z "${AQUATIC_ABYSS_DIR:-}" ] && [ ! -d "$REPO_DIR/.git" ] \
    && [ -d "$HOME/Documents/Repositories/github/Acquatic-Abyss/.git" ]; then
    REPO_DIR="$HOME/Documents/Repositories/github/Acquatic-Abyss"
fi
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
    # AUR builds (AGS, libastal, noctalia) assume the base-devel toolchain.
    base-devel
    # Interactive installer menus.
    gum
)

# Needed by the desktop but not guaranteed to be in the official Arch repos.
# CachyOS ships waypaper (and noctalia) in its own repository, so these
# normally install with plain pacman there; whatever the repos do not carry
# is offered as an explicitly confirmed AUR fallback (install_packages) —
# the installer never touches the AUR without asking.
EXTRA_PACKAGES=(
    hyprdynamicmonitors-bin
    waypaper
    aylurs-gtk-shell
)

OPTIONAL_PACKAGES=(
    pavucontrol
)

# hyprpm compiles Hyprland headers and plugins from source.
PLUGIN_BUILD_PACKAGES=(
    base-devel
    cmake
    meson
    cpio
    git
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

# BASH_SOURCE is unset when the script is piped into bash (curl | bash);
# fall back to $0 so set -u does not abort, landing on the current directory.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# ---------------------------------------------------------------------------
# Interaction layer. Uses gum (charmbracelet) for menus when available and
# falls back to plain prompts. Every prompt has a safe default so piped,
# non-interactive runs (curl | bash) complete without hanging.
# ---------------------------------------------------------------------------

# curl | bash leaves the pipe on stdin, so neither our prompts nor pacman's
# [Y/n] questions can be answered from the keyboard. Once the script runs
# from a file (BASH_SOURCE set — i.e. after bootstrap_repo execs the clone)
# it is safe to reattach the terminal. The piped first pass must NOT do
# this: bash is still reading the script itself from stdin. Headless runs
# (no controlling terminal) keep the pipe and take the defaults.
if [ -n "${BASH_SOURCE[0]:-}" ] && [ ! -t 0 ] && (: </dev/tty) 2>/dev/null; then
    exec </dev/tty
fi

INTERACTIVE=0
if [ -t 0 ]; then
    INTERACTIVE=1
fi
USE_GUM=0

# Without a terminal nobody can answer pacman/paru questions; take their
# defaults instead of stalling or aborting on EOF.
PAC_OPTS=()
if [ "$INTERACTIVE" -eq 0 ]; then
    PAC_OPTS=(--noconfirm)
fi

C_RESET="" C_BOLD="" C_TITLE="" C_DIM=""
if [ -t 1 ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_TITLE=$'\033[1;36m'
    C_DIM=$'\033[2m'
fi

print_banner() {
    echo
    echo "${C_TITLE}  ≋≋≋  Aquatic Abyss  ≋≋≋${C_RESET}"
    echo "${C_DIM}  A deep-sea Hyprland desktop. The installer will walk you through"
    echo "  a few choices; every one shows its default and can be changed later"
    echo "  in ~/.config/aquatic-abyss/config.env.${C_RESET}"
}

header() {
    echo
    echo "${C_TITLE}==> ${C_BOLD}$1${C_RESET}"
    if [ -n "${2:-}" ]; then
        echo "${C_DIM}    $2${C_RESET}"
    fi
}

# gum makes the menus pleasant; grab it first so even the first question
# benefits. Best effort only — every prompt also works without it.
ensure_gum() {
    [ "$INTERACTIVE" -eq 1 ] || return 0
    command -v gum >/dev/null 2>&1 && return 0
    [ "$INSTALL_DEPS" -eq 1 ] || return 0
    command -v pacman >/dev/null 2>&1 || return 0

    echo "Installing gum (interactive installer menus)..."
    sudo pacman -S --needed gum || true
}

ui_init() {
    if [ "$INTERACTIVE" -eq 1 ] && command -v gum >/dev/null 2>&1; then
        USE_GUM=1
    fi
}

# ui_confirm <question> [yes|no]   (second arg = default, defaults to no)
ui_confirm() {
    local prompt="$1" default="${2:-no}"
    local hint="[y/N]" answer

    if [ "$INTERACTIVE" -eq 0 ]; then
        if [ "$default" = "yes" ]; then return 0; else return 1; fi
    fi

    if [ "$USE_GUM" -eq 1 ]; then
        local args=()
        if [ "$default" = "no" ]; then
            args=(--default=false)
        fi
        if gum confirm "${args[@]}" "$prompt"; then return 0; else return 1; fi
    fi

    if [ "$default" = "yes" ]; then
        hint="[Y/n]"
    fi

    while true; do
        if ! read -r -p "$prompt $hint " answer; then
            echo
            if [ "$default" = "yes" ]; then return 0; else return 1; fi
        fi

        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            "")
                if [ "$default" = "yes" ]; then return 0; else return 1; fi
                ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# ui_choose <prompt> <default> <option>...   -> prints the chosen option
ui_choose() {
    local prompt="$1" default="$2"
    shift 2
    local opts=("$@") answer sel i

    if [ "$INTERACTIVE" -eq 0 ]; then
        echo "$default"
        return 0
    fi

    if [ "$USE_GUM" -eq 1 ]; then
        sel="$(gum choose --header "$prompt" --selected "$default" "${opts[@]}" || true)"
        echo "${sel:-$default}"
        return 0
    fi

    echo "$prompt" >&2
    i=1
    for sel in "${opts[@]}"; do
        if [ "$sel" = "$default" ]; then
            echo "  $i) $sel  ${C_DIM}(default)${C_RESET}" >&2
        else
            echo "  $i) $sel" >&2
        fi
        i=$((i + 1))
    done

    if ! read -r -p "Choice [1-${#opts[@]}, Enter = default]: " answer; then
        echo >&2
        echo "$default"
        return 0
    fi

    if [[ "$answer" =~ ^[0-9]+$ ]] && [ "$answer" -ge 1 ] && [ "$answer" -le "${#opts[@]}" ]; then
        echo "${opts[answer - 1]}"
    else
        echo "$default"
    fi
    return 0
}

# ui_multichoose <prompt> <option>...   -> prints selected options, one per
# line; empty selection is valid (and the non-interactive default).
ui_multichoose() {
    local prompt="$1"
    shift
    local opts=("$@") answer n i

    if [ "$INTERACTIVE" -eq 0 ]; then
        return 0
    fi

    if [ "$USE_GUM" -eq 1 ]; then
        gum choose --no-limit --header "$prompt" "${opts[@]}" || true
        return 0
    fi

    echo "$prompt" >&2
    i=1
    for n in "${opts[@]}"; do
        echo "  $i) $n" >&2
        i=$((i + 1))
    done

    if ! read -r -p "Numbers separated by spaces [Enter = none]: " answer; then
        echo >&2
        return 0
    fi

    for n in $answer; do
        if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#opts[@]}" ]; then
            echo "${opts[n - 1]}"
        fi
    done
    return 0
}

# Btrfs-only: offer a snapper snapshot before the installer changes anything
# (runs before ensure_gum, so even the gum install is covered).
SNAPSHOT_CREATED=0
SNAPSHOT_NUMBER=""
SNAPSHOT_DESCRIPTION="Safe state before Aquatic Abyss Install"

offer_snapshot() {
    [ "$(findmnt -n -o FSTYPE / 2>/dev/null)" = "btrfs" ] || return 0

    header "Filesystem snapshot" \
        "The root filesystem is Btrfs — a snapper snapshot lets you roll the system back to the state before this install."

    if ! ui_confirm "Create a snapshot before installing anything?" yes; then
        echo "Skipping the snapshot."
        return 0
    fi

    if ! command -v snapper >/dev/null 2>&1; then
        echo "Installing snapper..."
        sudo pacman -S --needed ${PAC_OPTS[@]+"${PAC_OPTS[@]}"} snapper
    fi

    if ! sudo snapper list >/dev/null 2>&1; then
        echo "No snapper config for / yet; creating one..."
        if ! sudo snapper -c root create-config /; then
            echo "Could not set up snapper; continuing without a snapshot." >&2
            return 0
        fi
    fi

    if SNAPSHOT_NUMBER="$(sudo snapper create --type single --print-number \
        --description "$SNAPSHOT_DESCRIPTION")"; then
        SNAPSHOT_CREATED=1
        echo "Snapshot #$SNAPSHOT_NUMBER created."
    else
        SNAPSHOT_NUMBER=""
        echo "Snapshot creation failed; continuing without one." >&2
    fi
    return 0
}

show_snapshot_info() {
    [ "$SNAPSHOT_CREATED" -eq 1 ] || return 0

    local list
    list="$(sudo snapper list 2>/dev/null)" || return 0

    echo
    echo "${C_TITLE}==> ${C_BOLD}Pre-install snapshot${C_RESET}"
    printf '%s\n' "$list" | sed -n '1,2p'
    printf '%s\n' "$list" | grep -F "$SNAPSHOT_DESCRIPTION" | tail -n 1
    echo
    echo "To roll the system back to this state later:"
    echo "  sudo snapper undochange $SNAPSHOT_NUMBER..0"
    echo "(reverts all file changes made since the snapshot; packages installed"
    echo "after it disappear from the filesystem, so reboot afterwards)"
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
            sudo pacman -S --needed ${PAC_OPTS[@]+"${PAC_OPTS[@]}"} git
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

BACKEND_CHOICE="noctalia"

choose_backend() {
    local user_config="${XDG_CONFIG_HOME:-$HOME/.config}/aquatic-abyss/config.env"

    if [ -f "$user_config" ] && grep -q '^AA_BACKEND=' "$user_config"; then
        BACKEND_CHOICE="$(sed -n 's/^AA_BACKEND="\{0,1\}\([a-z0-9_]*\)"\{0,1\}.*$/\1/p' "$user_config" | tail -n 1)"
        BACKEND_CHOICE="${BACKEND_CHOICE:-classic}"
        echo "Desktop backend already configured: $BACKEND_CHOICE ($user_config)"
        return
    fi

    header "Desktop shell" \
        "The backend draws the bar, menus, and on-screen displays."

    local noctalia_label="noctalia — Quickshell bar, menus, and OSD (default)"
    local classic_label="classic — Waybar + AGS menus + Hyprbars (deprecated but complete)"
    local choice
    choice="$(ui_choose "Which desktop shell do you want?" "$noctalia_label" \
        "$noctalia_label" "$classic_label")"

    BACKEND_CHOICE="${choice%% *}"
    echo "Using the $BACKEND_CHOICE backend."
}

# Default applications launched by the desktop keybindings (Super+Return =
# terminal, Super+B = browser, Super+E = file manager, ...). The chosen apps
# are installed with --deps and written to ~/.config/aquatic-abyss/config.env.
APP_TERMINAL_VALUE=""
APP_BROWSER_VALUE=""
APP_FILE_MANAGER_VALUE=""
CHOSEN_APP_PACKAGES=()

choose_apps() {
    local user_config="${XDG_CONFIG_HOME:-$HOME/.config}/aquatic-abyss/config.env"

    if [ -f "$user_config" ]; then
        # Existing config wins; the user edits it directly from here on.
        CHOSEN_APP_PACKAGES=()
        return
    fi

    header "Default applications" \
        "Used by the desktop keybindings (terminal, browser, file manager). Picked apps are installed; 'other' keeps the config default so you can edit it later."

    local choice

    choice="$(ui_choose "Terminal (Super+Return):" "kitty (recommended)" \
        "kitty (recommended)" "alacritty" "foot" "other — set later in config.env")"
    case "$choice" in
        kitty*)     APP_TERMINAL_VALUE="kitty";     CHOSEN_APP_PACKAGES+=(kitty) ;;
        alacritty)  APP_TERMINAL_VALUE="alacritty"; CHOSEN_APP_PACKAGES+=(alacritty) ;;
        foot)       APP_TERMINAL_VALUE="foot";      CHOSEN_APP_PACKAGES+=(foot) ;;
    esac

    choice="$(ui_choose "Web browser:" "chromium (recommended)" \
        "chromium (recommended)" "firefox" "other — set later in config.env")"
    case "$choice" in
        # Chromium keeps the tuned launch flags from config/defaults.env.
        chromium*) CHOSEN_APP_PACKAGES+=(chromium) ;;
        firefox)   APP_BROWSER_VALUE="firefox"; CHOSEN_APP_PACKAGES+=(firefox) ;;
    esac

    choice="$(ui_choose "File manager (Super+E):" "nautilus (recommended)" \
        "nautilus (recommended)" "thunar" "dolphin" "other — set later in config.env")"
    case "$choice" in
        nautilus*) APP_FILE_MANAGER_VALUE="nautilus"; CHOSEN_APP_PACKAGES+=(nautilus) ;;
        thunar)    APP_FILE_MANAGER_VALUE="thunar";   CHOSEN_APP_PACKAGES+=(thunar) ;;
        dolphin)   APP_FILE_MANAGER_VALUE="dolphin";  CHOSEN_APP_PACKAGES+=(dolphin) ;;
    esac
}

# Persist the choice in the user config. Must run after install_user_config:
# the copied defaults.env contains AA_BACKEND="classic", which this replaces.
apply_backend_choice() {
    local target_dir="${XDG_CONFIG_HOME:-$HOME/.config}/aquatic-abyss"
    local target="$target_dir/config.env"

    if [ -f "$target" ] && grep -q '^AA_BACKEND=' "$target"; then
        sed -i "s/^AA_BACKEND=.*/AA_BACKEND=\"$BACKEND_CHOICE\"/" "$target"
        return
    fi

    # No user config and noctalia chosen: the repo default already applies.
    if [ "$BACKEND_CHOICE" = "noctalia" ] && [ ! -f "$target" ]; then
        return
    fi

    mkdir -p "$target_dir"
    printf 'AA_BACKEND="%s"\n' "$BACKEND_CHOICE" >>"$target"
}

repo_has() {
    pacman -Si "$1" >/dev/null 2>&1
}

# install_packages <pkg>... — installs everything the distro repositories
# carry with pacman, then asks before building the remainder from the AUR.
# AUR builds are user-submitted and unreviewed, so nothing is fetched from
# there without an explicit yes; piped/headless runs skip the AUR entirely.
install_packages() {
    local pkg repo_pkgs=() aur_pkgs=() aur_helper providers=()

    # Add provider packages first so they are part of the same transaction.
    mapfile -t providers < <(provider_packages "$@")
    set -- "$@" ${providers[@]+"${providers[@]}"}

    for pkg in "$@"; do
        if repo_has "$pkg"; then
            repo_pkgs+=("$pkg")
        else
            aur_pkgs+=("$pkg")
        fi
    done

    if [ "${#repo_pkgs[@]}" -gt 0 ]; then
        echo "Installing packages from the distro repositories..."
        sudo pacman -S --needed ${PAC_OPTS[@]+"${PAC_OPTS[@]}"} "${repo_pkgs[@]}"
    fi

    [ "${#aur_pkgs[@]}" -gt 0 ] || return 0

    header "AUR fallback" \
        "Not in the distro repositories: ${aur_pkgs[*]}. AUR builds are user-submitted and unreviewed."
    if ! ui_confirm "Build these from the AUR? (skipping keeps the install repo-only)" no; then
        echo "Skipping AUR packages. Install later with: paru -S --needed ${aur_pkgs[*]}"
        return 0
    fi

    aur_helper="$(detect_aur_helper)"
    if [ -z "$aur_helper" ]; then
        echo "No AUR helper (paru/yay) found. Install these manually: ${aur_pkgs[*]}" >&2
        return 0
    fi

    echo "Installing AUR packages with $aur_helper..."
    "$aur_helper" -S --needed ${PAC_OPTS[@]+"${PAC_OPTS[@]}"} "${aur_pkgs[@]}"
}

contains_package() {
    local needle="$1" pkg
    shift
    for pkg in "$@"; do
        [ "$pkg" = "$needle" ] && return 0
    done
    return 1
}

# pacman interrupts an install to ask which package should satisfy a
# dependency whenever several can — either because different packages offer
# the same feature, or because a soname lives in both the Arch and CachyOS
# builds of one package. Each rule is "<dependency> <provider> [trigger]...":
# when the dependency is unsatisfied, and any trigger package is part of the
# install (no trigger means always), the provider is named on the command
# line so no menu appears.
PROVIDER_RULES=(
    # ksshaskpass (SSH passphrase prompts, in the core list) needs a Secret
    # Service daemon; NetworkManager and Chromium use it too. gnome-keyring
    # unlocks itself via PAM at login, so secrets are available without
    # opening anything first — unlike keepassxc, which only serves them
    # while its database is open. kwallet and oo7 stay unrequested.
    "org.freedesktop.secrets gnome-keyring"
    # nautilus pulls localsearch, which needs totem-plparser.
    "totem-plparser totem-pl-parser nautilus"
    # cage (the greeter's compositor) pulls wlroots, which needs libliftoff.
    "libliftoff libliftoff cage"
)

# provider_packages <planned pkg>...  -> prints the extra packages to add.
# `pacman -T` reports a dependency as satisfied (exit 0) when something
# providing it is already installed, so an existing choice — a KDE user's
# kwallet, say — is never second-guessed.
provider_packages() {
    local rule dep provider triggers trigger needed

    for rule in "${PROVIDER_RULES[@]}"; do
        read -r dep provider triggers <<<"$rule"

        needed=1
        if [ -n "$triggers" ]; then
            needed=0
            for trigger in $triggers; do
                if contains_package "$trigger" "$@"; then
                    needed=1
                    break
                fi
            done
        fi

        [ "$needed" -eq 1 ] || continue
        pacman -T "$dep" >/dev/null 2>&1 || echo "$provider"
    done
}

install_dependencies() {
    if ! command -v pacman >/dev/null 2>&1; then
        echo "Dependency installation is only automated for Arch/CachyOS systems." >&2
        exit 1
    fi

    local wanted=("${PACMAN_PACKAGES[@]}" "${OPTIONAL_PACKAGES[@]}"
        ${CHOSEN_APP_PACKAGES[@]+"${CHOSEN_APP_PACKAGES[@]}"} "${EXTRA_PACKAGES[@]}")

    if [ "$BACKEND_CHOICE" = "noctalia" ]; then
        # CachyOS carries noctalia in its repo; elsewhere the AUR -git build.
        if repo_has noctalia; then
            wanted+=(noctalia)
        else
            wanted+=(noctalia-git)
        fi
    fi

    install_packages "${wanted[@]}"
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
        echo "Keeping existing settings at $target."
        return 0
    fi

    mkdir -p "$target_dir"
    cp "$source" "$target"

    # The repo header warns against editing defaults.env; the user copy is
    # exactly the place to edit.
    sed -i '/^# Do NOT edit this file/,+1c\
# Your personal Aquatic Abyss settings. Edit freely — the installer never\
# overwrites this file.' "$target"

    [ -n "$APP_TERMINAL_VALUE" ] && \
        sed -i "s|^AA_TERMINAL=.*|AA_TERMINAL=\"$APP_TERMINAL_VALUE\"|" "$target"
    [ -n "$APP_BROWSER_VALUE" ] && \
        sed -i "s|^AA_BROWSER=.*|AA_BROWSER=\"$APP_BROWSER_VALUE\"|" "$target"
    [ -n "$APP_FILE_MANAGER_VALUE" ] && \
        sed -i "s|^AA_FILE_MANAGER=.*|AA_FILE_MANAGER=\"$APP_FILE_MANAGER_VALUE\"|" "$target"

    echo "Your choices are saved in $target — edit that file to change apps later."
}

install_wallpapers() {
    local source_dir="$DEFAULT_WALLPAPER_DIR"
    local target_dir="$WALLPAPER_TARGET_DIR"
    local wallpapers=()

    if [ ! -d "$source_dir" ]; then
        echo "Default wallpaper directory not found at $source_dir; skipping wallpapers."
        return
    fi

    header "Wallpapers" \
        "The theme ships deep-sea wallpapers used by the wallpaper picker and rotation."

    if ! ui_confirm "Copy the bundled wallpapers to $target_dir? (existing files are never overwritten)" yes; then
        echo "Skipping default wallpapers."
        return
    fi

    mkdir -p "$target_dir"

    while IFS= read -r -d '' wallpaper; do
        wallpapers+=("$wallpaper")
    done < <(find "$source_dir" -maxdepth 1 -type f -print0)

    if [ "${#wallpapers[@]}" -eq 0 ]; then
        echo "No default wallpapers found in $source_dir."
        return
    fi

    cp -n "${wallpapers[@]}" "$target_dir/"
    echo "Wallpapers are in $target_dir."
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

    [ "$INSTALL_DEPS" -eq 1 ] || return 0
    command -v pacman >/dev/null 2>&1 || return 0

    # install_packages sorts the combined list into repo vs AUR itself, so
    # packages.aur entries a distro repo happens to carry stay off the AUR.
    mapfile -t packages < <(
        read_package_list "$dir/packages.arch"
        read_package_list "$dir/packages.aur"
    )

    [ "${#packages[@]}" -gt 0 ] || return 0
    install_packages "${packages[@]}"
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

    if ! ui_confirm "Module $name needs a sudo rule ($target) so its controls work without a password prompt. Install it?" yes; then
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

# One-line description shown in the module menu: the module's `description`
# file, or the first line of its README as a fallback.
module_description() {
    if [ -f "$1/description" ]; then
        head -n 1 "$1/description"
        return 0
    fi

    [ -f "$1/README.md" ] || return 0
    sed -n '/^#/d; /^[[:space:]]*$/d; s/[*`]//g; p; q' "$1/README.md" | cut -c1-72
}

install_modules() {
    local dir name desc
    local names=() labels=()

    for dir in "$REPO_DIR"/modules/*/; do
        [ -f "$dir/module.sh" ] || continue
        name="$(basename "$dir")"
        desc="$(module_description "$dir")"
        names+=("$name")
        labels+=("$name — ${desc:-no description}")
    done

    [ "${#names[@]}" -gt 0 ] || return 0

    header "Optional modules" \
        "Extra features you can add now or any time later with ./install.sh. None are required."

    local selection
    selection="$(ui_multichoose \
        "Which optional modules do you want? (Space selects, Enter confirms — none is fine)" \
        "${labels[@]}")"

    if [ -z "$selection" ]; then
        echo "No optional modules selected."
        return 0
    fi

    # Loop over an array, not `while read <<<"$selection"`: with the
    # selection on stdin, pacman's [Y/n] question inside the loop would eat
    # the remaining selection lines as its answer and skip those modules.
    local selected_lines=() selection_line
    mapfile -t selected_lines <<<"$selection"

    for selection_line in "${selected_lines[@]}"; do
        [ -n "$selection_line" ] || continue
        name="${selection_line%% —*}"
        dir="$REPO_DIR/modules/$name/"
        [ -f "$dir/module.sh" ] || continue

        echo
        echo "Setting up module $name..."
        install_module_packages "$dir" "$name"
        install_module_sudoers "$dir" "$name"
        run_module_install_hook "$dir" "$name"
    done
}

# Set when a display manager will greet the next boot — either one that was
# already enabled or the greetd stack this installer sets up. Decides
# whether --start offers a reboot instead of exec'ing Hyprland raw.
GREETER_ENABLED=0

# Session entry that starts Hyprland with this repo's config. Kept in its
# own function so reruns refresh it even when greetd is already enabled.
install_greeter_session() {
    # start-hyprland is Hyprland's own watchdog launcher (>= 0.56); starting
    # the compositor binary directly is discouraged upstream and prints a
    # warning. Arguments after -- are passed through to Hyprland.
    sudo tee /usr/local/bin/aquatic-abyss-session >/dev/null <<'EOF'
#!/usr/bin/env bash
if command -v start-hyprland >/dev/null 2>&1; then
    exec start-hyprland -- --config "$HOME/.config/hypr/hyprland.lua"
fi
exec Hyprland --config "$HOME/.config/hypr/hyprland.lua"
EOF
    sudo chmod 755 /usr/local/bin/aquatic-abyss-session

    sudo tee /usr/share/wayland-sessions/aquatic-abyss.desktop >/dev/null <<'EOF'
[Desktop Entry]
Name=Aquatic Abyss
Comment=Hyprland with the Aquatic Abyss configuration
Exec=/usr/local/bin/aquatic-abyss-session
Type=Application
DesktopNames=Hyprland
EOF
}

install_greeter() {
    [ "$INSTALL_DEPS" -eq 1 ] || return 0
    command -v pacman >/dev/null 2>&1 || return 0
    command -v systemctl >/dev/null 2>&1 || return 0

    # display-manager.service is the systemd alias every enabled DM claims.
    local dm_unit="/etc/systemd/system/display-manager.service"
    if [ -e "$dm_unit" ]; then
        GREETER_ENABLED=1
        local dm_name
        dm_name="$(basename "$(readlink -f "$dm_unit")")"
        if [ "$dm_name" = "greetd.service" ]; then
            echo "greetd already enabled; refreshing the Aquatic Abyss session entry."
            install_greeter_session
        else
            echo "Display manager already enabled ($dm_name); leaving it as is."
        fi
        return 0
    fi

    header "Login screen" \
        "Without a display manager the machine boots to a text console. greetd + ReGreet is a small Wayland greeter using the theme wallpaper."

    if ! ui_confirm "Install and enable the themed login screen (greetd + ReGreet)?" yes; then
        echo "Skipping the login screen. Start Hyprland manually from the TTY after logging in."
        return 0
    fi

    install_packages greetd greetd-regreet cage

    local wallpaper="$REPO_DIR/appendix/wallpapers/Middle Of The Ocean.png"
    local greeter_bg="/usr/share/backgrounds/aquatic-abyss/greeter.png"
    if [ -f "$wallpaper" ]; then
        sudo install -Dm644 "$wallpaper" "$greeter_bg"
    else
        echo "Theme wallpaper not found at $wallpaper; the greeter will use a plain background."
    fi

    if [ -f /etc/greetd/config.toml ] && ! sudo grep -q regreet /etc/greetd/config.toml 2>/dev/null; then
        sudo cp /etc/greetd/config.toml /etc/greetd/config.toml.bak
    fi

    sudo tee /etc/greetd/config.toml >/dev/null <<'EOF'
[terminal]
vt = 1

[default_session]
# cage hosts the GTK greeter on a minimal Wayland compositor; -s allows
# VT switching.
command = "cage -s -- regreet"
user = "greeter"
EOF

    sudo tee /etc/greetd/regreet.toml >/dev/null <<EOF
[background]
path = "$greeter_bg"
fit = "Cover"

[GTK]
application_prefer_dark_theme = true
EOF

    # The stock hyprland.desktop session launches the default config path
    # (hyprland.conf), but this desktop lives in hyprland.lua — ship a
    # session entry that starts Hyprland with the right config.
    install_greeter_session

    # Pre-select this user and the Aquatic Abyss session on the first
    # login; ReGreet keeps the file updated by itself afterwards.
    local login_user="${USER:-$(id -un)}"
    if ! sudo test -f /var/lib/regreet/state.toml; then
        sudo install -d -o greeter -g greeter /var/lib/regreet
        sudo tee /var/lib/regreet/state.toml >/dev/null <<EOF
last_user = "$login_user"

[user_to_last_sess]
"$login_user" = "Aquatic Abyss"
EOF
        sudo chown greeter:greeter /var/lib/regreet/state.toml
    fi

    if sudo systemctl enable greetd.service; then
        GREETER_ENABLED=1
        echo "Login screen enabled. Pick the \"Aquatic Abyss\" session in ReGreet after reboot."
    else
        echo "Could not enable greetd; enable it manually with: sudo systemctl enable greetd" >&2
    fi
}

install_plugins() {
    if ! command -v hyprpm >/dev/null 2>&1; then
        echo "hyprpm is not available. Install Hyprland first, then rerun ./install.sh --plugins." >&2
        exit 1
    fi

    echo "Installing plugin build dependencies..."
    sudo pacman -S --needed ${PAC_OPTS[@]+"${PAC_OPTS[@]}"} "${PLUGIN_BUILD_PACKAGES[@]}"

    # Every hyprpm subcommand — update included, whose final reload/notify
    # step is what dies with "no $HOME or $HYPRLAND_INSTANCE_SIGNATURE" —
    # needs the running Hyprland instance. On a bare TTY leave a marker
    # instead; hyprpm-reload-notify.sh, which runs at every Hyprland start,
    # performs the whole update/add/enable inside the first session.
    if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/aquatic-abyss"
        mkdir -p "$state_dir"
        : >"$state_dir/hyprpm-setup-pending"
        echo "No running Hyprland session — plugin headers and Hyprbars will be built automatically on first start."
        return 0
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
        if [ "$GREETER_ENABLED" -eq 1 ]; then
            # Hyprland upstream advises against launching from wrapper
            # scripts; a reboot into the display manager gives a clean
            # session (logind seat, session environment) instead.
            if ui_confirm "Setup complete. Reboot now and log in through the login screen?" yes; then
                sudo systemctl reboot
                return
            fi
            echo "Reboot when ready — the login screen will start Hyprland."
            return
        fi
        echo "Setup complete. No display manager is enabled: log in on the TTY and run 'Hyprland' to start the desktop."
        return
    fi

    echo "Config installed. Log out and start Hyprland from a TTY or display manager."
}

bootstrap_repo "$@"
print_banner
offer_snapshot
ensure_gum
ui_init
choose_backend
choose_apps

if [ "$INSTALL_DEPS" -eq 1 ]; then
    install_dependencies
fi

install_config
install_user_config
apply_backend_choice
install_wallpapers
install_modules
install_greeter

if [ "$INSTALL_PLUGINS" -eq 1 ]; then
    install_plugins
fi

# Before start_hyprland: a confirmed reboot would swallow this output.
show_snapshot_info

if [ "$START_HYPRLAND" -eq 1 ]; then
    start_hyprland
else
    echo "Restart Hyprland or run: hyprctl reload"
fi
