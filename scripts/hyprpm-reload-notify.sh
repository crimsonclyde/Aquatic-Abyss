#!/usr/bin/env bash
set -uo pipefail

# Run hyprpm reload and mirror its result into the desktop notification
# daemon. hyprpm itself only uses Hyprland's transient on-screen overlay,
# which disappears after a few seconds and cannot be copied or reviewed.

strip_ansi() {
    sed -e 's/\x1b\[[0-9;]*m//g' -e '/^\s*$/d'
}

# The installer cannot add/enable plugins from a TTY (hyprpm needs the
# running instance), so ./install.sh --plugins leaves this marker for the
# first session to finish the job here.
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/aquatic-abyss"
pending="$state_dir/hyprpm-setup-pending"
plugin_cache="/var/cache/hyprpm/${USER:-$(id -un)}"

# hyprland 0.56.2-3 split hyprpm into its own package, so an upgrade can
# remove it. Stay silent when plugins were never set up; otherwise say what
# to install instead of a bare "command not found".
if ! command -v hyprpm >/dev/null 2>&1; then
    if [ -f "$pending" ] || [ -d "$plugin_cache" ]; then
        notify-send --app-name=hyprpm --urgency=critical \
            "hyprpm is not installed" "Plugins cannot load. Install it with: sudo pacman -S hyprpm"
        exit 1
    fi
    exit 0
fi

# hyprpm reload reports "Loaded <plugin>" even when Hyprland rejected it
# (e.g. "[hb] Version mismatch" after a distro rebuild against newer
# aquamarine/hyprutils at the same Hyprland commit, which plain hyprpm
# update does not detect). Ask the compositor instead: retry every enabled
# plugin it does not list and collect the real load errors.
check_loaded() {
    local loaded enabled name so out errors=""
    loaded=$(hyprctl plugin list -j 2>/dev/null | jq -r '.[].name' 2>/dev/null)
    enabled=$(hyprpm list 2>/dev/null | strip_ansi | awk '/Plugin /{n=$NF} /enabled: true/{print n}')
    for name in $enabled; do
        grep -qxF "$name" <<<"$loaded" && continue
        so=$(find "$plugin_cache" -name "$name.so" -print -quit 2>/dev/null)
        [ -n "$so" ] || { errors+="$name: plugin not built"$'\n'; continue; }
        # A plugin reporting a different name than hyprpm's answers
        # "Cannot load a plugin twice!" here, which is fine.
        out=$(hyprctl plugin load "$so" 2>&1)
        case "$out" in
            *"could not be loaded"*) errors+="$name: ${out##*: }"$'\n' ;;
        esac
    done
    [ -z "$errors" ] && return 0
    printf '%s' "$errors"
    return 1
}

finish_pending_setup() {
    local out
    # Headers first: the TTY install skips hyprpm update entirely (it needs
    # the running instance), so this may be the first headers build.
    out=$(hyprpm update 2>&1) || {
        printf '%s\n' "$out"
        return 1
    }
    # The repo may already be added by a partial earlier attempt.
    if out=$(hyprpm enable hyprbars 2>&1); then
        return 0
    fi
    out=$(hyprpm add https://github.com/hyprwm/hyprland-plugins 2>&1) || {
        printf '%s\n' "$out"
        return 1
    }
    out=$(hyprpm enable hyprbars 2>&1) || {
        printf '%s\n' "$out"
        return 1
    }
    return 0
}

if [ -f "$pending" ]; then
    notify-send --app-name=hyprpm --urgency=low \
        "hyprpm" "First start: building plugin headers and Hyprbars — this can take a few minutes..."
    if err=$(finish_pending_setup); then
        rm -f "$pending"
    else
        clean=$(printf '%s\n' "$err" | strip_ansi)
        notify-send --app-name=hyprpm --urgency=critical \
            "hyprpm plugin setup failed" "${clean:-hyprpm add/enable failed; run ./install.sh --plugins inside Hyprland}"
    fi
fi

output=$(hyprpm reload 2>&1)
status=$?

# Strip ANSI color codes and box-drawing noise for the notification body.
clean=$(printf '%s\n' "$output" | strip_ansi)

if [ "$status" -ne 0 ]; then
    notify-send --app-name=hyprpm --urgency=critical \
        "hyprpm reload failed" "${clean:-hyprpm reload exited with status $status}"
elif ! err=$(check_loaded); then
    status=1
    notify-send --app-name=hyprpm --urgency=critical \
        "Plugins failed to load" "${err}Rebuild headers and plugins with: hyprpm update -f"
else
    notify-send --app-name=hyprpm --urgency=low \
        "hyprpm" "Plugins loaded."
fi

exit "$status"
