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
# Unattended mode (--auto): every question answers itself with the value a
# careful user would pick, and the optional-module menu selects everything
# available instead of nothing. Deliberately NOT a blanket yes — the AUR
# question still answers "no" (its default), so an unattended run never builds
# unreviewed packages, and the closing reboot is never taken without a human.
AUTO=0
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
  --auto       Unattended install: implies --deps and --plugins, answers every
               question with its default, creates the Btrfs rollback point,
               and enables all available optional modules. Still skips the AUR
               and never reboots on its own.
  --start      Deprecated no-op, accepted for compatibility. The installer
               always finishes by reloading a running Hyprland, or offering a
               reboot into the login screen when one was set up.
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
        --auto)
            AUTO=1
            INSTALL_DEPS=1
            INSTALL_PLUGINS=1
            ;;
        --start)
            # Kept accepted so existing one-liners and scripts do not abort on
            # "Unknown option". The finishing step is unconditional now.
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
# defaults instead of stalling or aborting on EOF. --auto wants the same
# treatment even on a perfectly good terminal.
PAC_OPTS=()
if [ "$INTERACTIVE" -eq 0 ] || [ "$AUTO" -eq 1 ]; then
    PAC_OPTS=(--noconfirm)
fi

# True when no question may be put to a human: either there is nobody there,
# or --auto promised there would be no questions.
prompts_disabled() {
    [ "$INTERACTIVE" -eq 0 ] || [ "$AUTO" -eq 1 ]
}

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

    if prompts_disabled; then
        if [ "$AUTO" -eq 1 ]; then
            echo "${C_DIM}auto: $prompt -> $default${C_RESET}"
        fi
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

    if prompts_disabled; then
        if [ "$AUTO" -eq 1 ]; then
            echo "${C_DIM}auto: $prompt -> $default${C_RESET}" >&2
        fi
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
# line; empty selection is valid (and the headless default).
#
# --auto is the one case that selects *everything*: a headless run takes the
# cautious path and adds nothing, but an unattended install was asked for the
# full desktop. Selecting a module that cannot work here is harmless — it
# installs its packages (AUR-only ones are skipped like everywhere else) and
# then stays hidden from every menu until its hardware or config shows up.
ui_multichoose() {
    local prompt="$1"
    shift
    local opts=("$@") answer n i

    if [ "$AUTO" -eq 1 ]; then
        echo "${C_DIM}auto: $prompt -> all (${#opts[@]})${C_RESET}" >&2
        printf '%s\n' ${opts[@]+"${opts[@]}"}
        return 0
    fi

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

# ---------------------------------------------------------------------------
# Rollback point (Btrfs only)
#
# An install writes packages, symlinks, sudoers rules, greeter config, and
# user files all over the disk, so replaying individual file changes back
# (snapper undochange) cannot reliably undo it. Instead every subvolume that
# holds system or user state is snapshotted before anything is touched, and
# the generated rollback script swaps those snapshots back in — the same
# rename-and-reboot mechanism snapper's own rollback uses.
#
# CachyOS splits /, /root and /home into separate subvolumes (@, @root,
# @home), and a rollback of @ alone would leave both home directories
# behind, so each one is snapshotted separately.
# ---------------------------------------------------------------------------

ROLLBACK_CREATED=0
ROLLBACK_DIR=""
ROLLBACK_SUBVOLUMES=()
ROLLBACK_BASE="@aquatic-abyss-rollback"
ROLLBACK_SCRIPT="/usr/local/bin/aquatic-abyss-rollback"
# Mount points whose subvolumes are restored. Anything not listed here keeps
# its contents: /var/log (test logs stay readable) and /var/cache (the pacman
# download cache) hold no state that defines the installed system.
ROLLBACK_MOUNTPOINTS=(/ /root /home)

mount_fsroot() { findmnt -n -o FSROOT --target "$1" 2>/dev/null; }
mount_uuid() { findmnt -n -o UUID --target "$1" 2>/dev/null; }
mount_fstype() { findmnt -n -o FSTYPE --target "$1" 2>/dev/null; }

# fstab options for a mount point, ignoring comments.
fstab_options() {
    awk -v mp="$1" '!/^[[:space:]]*#/ && $2 == mp { print $4 }' /etc/fstab 2>/dev/null
}

# Prints the subvolumes to snapshot, one per line. A mount point whose
# subvolume is already listed (/root inside @, say) is skipped: restoring @
# covers it.
rollback_subvolumes() {
    local root_uuid mp fsroot seen=()

    root_uuid="$(mount_uuid /)"
    for mp in "${ROLLBACK_MOUNTPOINTS[@]}"; do
        [ -d "$mp" ] || continue
        [ "$(mount_fstype "$mp")" = "btrfs" ] || continue
        # Only subvolumes of the root filesystem can be swapped together.
        [ "$(mount_uuid "$mp")" = "$root_uuid" ] || continue

        fsroot="$(mount_fsroot "$mp")"
        fsroot="${fsroot#/}"
        [ -n "$fsroot" ] || continue
        contains_item "$fsroot" ${seen[@]+"${seen[@]}"} && continue
        seen+=("$fsroot")
    done

    printf '%s\n' ${seen[@]+"${seen[@]}"}
}

# Swapping subvolumes only survives a reboot when the system finds them by
# name. A subvolid= in fstab or on the kernel command line pins the *old*
# subvolume, and a non-top-level default subvolume does the same, so both
# rule the rollback out.
rollback_blocker() {
    local mp opts

    command -v btrfs >/dev/null 2>&1 || {
        echo "btrfs-progs is not installed"
        return 0
    }

    if grep -q 'subvolid=' /proc/cmdline 2>/dev/null; then
        echo "the kernel command line pins a subvolume by id"
        return 0
    fi

    for mp in "${ROLLBACK_MOUNTPOINTS[@]}"; do
        opts="$(fstab_options "$mp")"
        [ -n "$opts" ] || continue
        case "$opts" in
            *subvolid=*)
                echo "/etc/fstab mounts $mp by subvolume id"
                return 0
                ;;
            *subvol=*) ;;
            *)
                echo "/etc/fstab does not name a subvolume for $mp"
                return 0
                ;;
        esac
    done

    local default_id
    default_id="$(sudo btrfs subvolume get-default / 2>/dev/null | awk '{print $2}')"
    if [ -n "$default_id" ] && [ "$default_id" != "5" ]; then
        echo "the filesystem has a default subvolume set (id $default_id)"
        return 0
    fi

    return 1
}

# Asked before the terminal can be reattached (in a piped run bash is still
# reading the script itself from stdin), so talk to /dev/tty directly.
rollback_confirm() {
    local prompt="$1" answer

    # A rollback point is the whole safety net of an unattended install, so
    # --auto always takes it. This runs before bootstrap_repo re-execs, where
    # INTERACTIVE is still 0 on a piped run — check AUTO first.
    if [ "$AUTO" -eq 1 ]; then
        echo "auto: $prompt -> yes"
        return 0
    fi

    if [ "$INTERACTIVE" -eq 1 ]; then
        ui_confirm "$prompt" yes
        return $?
    fi

    # Readable is not enough: in a container /dev/tty can exist but refuse
    # to open. Default to yes when it does.
    { : </dev/tty; } 2>/dev/null || return 0

    while true; do
        printf '%s [Y/n] ' "$prompt" >/dev/tty 2>/dev/null || return 0
        read -r answer </dev/tty 2>/dev/null || return 0
        case "${answer,,}" in
            ""|y|yes) return 0 ;;
            n|no) return 1 ;;
            *) printf 'Please answer yes or no.\n' >/dev/tty ;;
        esac
    done
}

write_rollback_script() {
    local uuid="$1" dir="$2"
    shift 2

    sudo tee "$ROLLBACK_SCRIPT" >/dev/null <<EOF
#!/usr/bin/env bash
# Restore the subvolumes snapshotted before Aquatic Abyss was installed.
# Generated by install.sh; this copy disappears with the rollback itself.
# -E matters: without it the ERR trap that undoes a half-finished swap
# would not fire for failures inside a function.
set -Eeuo pipefail

FS_UUID="$uuid"
SNAPSHOT_DIR="$dir"
SUBVOLUMES=($*)
EOF

    sudo tee -a "$ROLLBACK_SCRIPT" >/dev/null <<'EOF'

DRY_RUN=0
ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help)
            echo "Usage: aquatic-abyss-rollback [--dry-run] [-y]"
            echo "Restores ${SUBVOLUMES[*]} from $SNAPSHOT_DIR and reboots."
            exit 0
            ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "This must run as root: sudo aquatic-abyss-rollback $*" >&2
    exit 1
fi

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'would run:'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

top="$(mktemp -d)"
cleanup() {
    if mountpoint -q "$top"; then
        umount "$top" || true
    fi
    rmdir "$top" 2>/dev/null || true
}
trap cleanup EXIT

# The top level (subvolid=5) holds the subvolumes themselves, so the swap
# happens there rather than inside any mounted subvolume.
mount -U "$FS_UUID" -o subvolid=5 "$top"

for sv in "${SUBVOLUMES[@]}"; do
    if [ ! -d "$top/$SNAPSHOT_DIR/$sv" ]; then
        echo "Snapshot for $sv is missing under $SNAPSHOT_DIR." >&2
        echo "Nothing was changed." >&2
        exit 1
    fi
done

echo "Restoring ${SUBVOLUMES[*]} from $SNAPSHOT_DIR"
echo
echo "Everything written since the installer ran — packages, configs, and"
echo "files in the restored home directories — will be gone after the reboot."
echo

if [ "$DRY_RUN" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
    read -r -p "Roll back and reboot now? [y/N] " answer
    case "${answer,,}" in
        y|yes) ;;
        *) echo "Aborted; nothing was changed."; exit 0 ;;
    esac
fi

# Replaced subvolumes from an earlier rollback are not in use any more.
for old in "$top"/*.pre-rollback-*; do
    [ -e "$old" ] || continue
    echo "Removing leftover $(basename "$old")"
    run btrfs subvolume delete "$old" || \
        echo "  could not delete it; remove it by hand later"
done

stamp="$(date +%Y%m%d_%H%M%S)"

# A failure halfway through would leave the machine with some subvolumes
# swapped and others renamed out of the way — the one state that does not
# boot. Undo whatever was already done before giving up.
swapped=()
undo_swaps() {
    echo "Rollback failed; putting the original subvolumes back." >&2
    local done_sv
    for done_sv in ${swapped[@]+"${swapped[@]}"}; do
        if [ -d "$top/$done_sv" ]; then
            btrfs subvolume delete "$top/$done_sv" >/dev/null 2>&1 || true
        fi
        if [ -d "$top/$done_sv.pre-rollback-$stamp" ]; then
            mv "$top/$done_sv.pre-rollback-$stamp" "$top/$done_sv" || \
                echo "  could not restore $done_sv — do NOT reboot; ask for help" >&2
        fi
    done
}
trap undo_swaps ERR

for sv in "${SUBVOLUMES[@]}"; do
    echo "Restoring $sv"
    # Renaming works while the subvolume is mounted: the running system
    # keeps using it by id until the reboot, and fstab finds the restored
    # copy under the original name.
    run mv "$top/$sv" "$top/$sv.pre-rollback-$stamp"
    swapped+=("$sv")
    run btrfs subvolume snapshot "$top/$SNAPSHOT_DIR/$sv" "$top/$sv"
done

trap - ERR

if [ "$DRY_RUN" -eq 1 ]; then
    echo
    echo "Dry run only; nothing was changed."
    exit 0
fi

echo
echo "Done. The replaced subvolumes are kept as *.pre-rollback-$stamp and"
echo "are deleted the next time this script runs. To drop the rollback point"
echo "itself once the machine is back the way you want it:"
echo "  mkdir /mnt/btrfs-top && mount -U $FS_UUID -o subvolid=5 /mnt/btrfs-top"
echo "  btrfs subvolume delete /mnt/btrfs-top/$SNAPSHOT_DIR/*"
echo "  rm -r /mnt/btrfs-top/$SNAPSHOT_DIR && umount /mnt/btrfs-top"
echo
echo "Rebooting in 5 seconds — the restored system comes up after that."
sleep 5
systemctl reboot
EOF

    sudo chmod 755 "$ROLLBACK_SCRIPT"
}

offer_rollback_point() {
    # bootstrap_repo re-executes the installer from the clone; the rollback
    # point belongs to the run as a whole, so it is created once and the
    # result handed to the second pass.
    if [ -n "${AQUATIC_ABYSS_ROLLBACK_STATE+x}" ]; then
        if [ -n "$AQUATIC_ABYSS_ROLLBACK_STATE" ]; then
            ROLLBACK_DIR="${AQUATIC_ABYSS_ROLLBACK_STATE%%|*}"
            read -r -a ROLLBACK_SUBVOLUMES <<<"${AQUATIC_ABYSS_ROLLBACK_STATE#*|}"
            ROLLBACK_CREATED=1
        fi
        return 0
    fi

    export AQUATIC_ABYSS_ROLLBACK_STATE=""

    [ "$(mount_fstype /)" = "btrfs" ] || return 0

    local subvolumes=()
    mapfile -t subvolumes < <(rollback_subvolumes)
    [ "${#subvolumes[@]}" -gt 0 ] || return 0

    header "Rollback point" \
        "The root filesystem is Btrfs. Snapshotting it now makes this install completely reversible: ${subvolumes[*]}."

    local blocker
    if blocker="$(rollback_blocker)"; then
        echo "No rollback point: $blocker."
        echo "The install continues, but it cannot be undone automatically."
        return 0
    fi

    if ! rollback_confirm "Create a rollback point before installing anything?"; then
        echo "Continuing without a rollback point."
        return 0
    fi

    local uuid stamp top dir sv
    uuid="$(mount_uuid /)"
    stamp="$(date +%Y%m%d_%H%M%S)"
    dir="$ROLLBACK_BASE/$stamp"

    top="$(mktemp -d)"
    if ! sudo mount -U "$uuid" -o subvolid=5 "$top"; then
        rmdir "$top" 2>/dev/null || true
        echo "Could not open the Btrfs top level; continuing without a rollback point." >&2
        return 0
    fi

    local failed=0
    sudo mkdir -p "$top/$dir"
    for sv in "${subvolumes[@]}"; do
        if ! sudo btrfs subvolume snapshot -r "$top/$sv" "$top/$dir/$sv" >/dev/null; then
            failed=1
            break
        fi
    done

    if [ "$failed" -eq 1 ]; then
        echo "Snapshot failed; cleaning up and continuing without a rollback point." >&2
        for sv in "${subvolumes[@]}"; do
            sudo btrfs subvolume delete "$top/$dir/$sv" >/dev/null 2>&1 || true
        done
        sudo rmdir "$top/$dir" 2>/dev/null || true
        sudo umount "$top" || true
        rmdir "$top" 2>/dev/null || true
        return 0
    fi

    sudo umount "$top"
    rmdir "$top" 2>/dev/null || true

    write_rollback_script "$uuid" "$dir" "${subvolumes[@]}"

    ROLLBACK_CREATED=1
    ROLLBACK_DIR="$dir"
    ROLLBACK_SUBVOLUMES=("${subvolumes[@]}")
    export AQUATIC_ABYSS_ROLLBACK_STATE="$dir|${subvolumes[*]}"

    echo "Rollback point created: ${subvolumes[*]}"
}

show_rollback_info() {
    [ "$ROLLBACK_CREATED" -eq 1 ] || return 0

    echo
    echo "${C_TITLE}==> ${C_BOLD}Rollback point${C_RESET}"
    echo "Snapshotted before the install: ${ROLLBACK_SUBVOLUMES[*]}"
    echo "Stored at: $ROLLBACK_DIR (Btrfs top level)"
    echo
    echo "To put the machine back exactly as it was and reboot:"
    echo "  sudo aquatic-abyss-rollback"
    echo "To see what that would do without changing anything:"
    echo "  sudo aquatic-abyss-rollback --dry-run"
    echo
    echo "Kept out of the rollback: /var/log and /var/cache, so test logs and"
    echo "downloaded packages survive. Everything else returns to this moment."
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

    # The banner and the rollback question already happened in this run.
    export AQUATIC_ABYSS_REEXEC=1
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

contains_item() {
    local needle="$1" item
    shift
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
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
                if contains_item "$trigger" "$@"; then
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
# already enabled or the greetd stack this installer sets up. Decides whether
# the finishing step offers a reboot or tells the user to start Hyprland.
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

# Last step of every run. Never launches the compositor itself — Hyprland
# upstream advises against starting it from a wrapper script — it only tells
# the user, or reboots into the login screen, whichever fits the situation.
finish_session() {
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        echo "Hyprland is already running. Reloading config..."
        hyprctl reload
        return
    fi

    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        if [ "$GREETER_ENABLED" -eq 1 ]; then
            # Rebooting is the one thing --auto will not decide for you: the
            # machine may be doing something else, and "reboot" is not a
            # keystroke anyone should be able to skip by accident.
            if [ "$AUTO" -eq 1 ]; then
                echo "Setup complete. Reboot when ready — the login screen will start Hyprland."
                return
            fi

            # A reboot into the display manager gives a clean session (logind
            # seat, session environment) that a wrapper launch cannot.
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

[ -n "${AQUATIC_ABYSS_REEXEC:-}" ] || print_banner
# Before bootstrap_repo: cloning the repository and installing git are
# already changes, and a rollback should undo those too.
offer_rollback_point
bootstrap_repo "$@"
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

# Before finish_session: a confirmed reboot would swallow this output.
show_rollback_info
finish_session
