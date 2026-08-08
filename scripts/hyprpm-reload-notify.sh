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

finish_pending_setup() {
    local out
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
        "hyprpm" "First start: building the Hyprbars plugin, this can take a minute..."
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
else
    notify-send --app-name=hyprpm --urgency=low \
        "hyprpm" "Plugins loaded."
fi

exit "$status"
