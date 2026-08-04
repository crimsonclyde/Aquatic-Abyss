#!/usr/bin/env bash
set -uo pipefail

# Run hyprpm reload and mirror its result into the desktop notification
# daemon. hyprpm itself only uses Hyprland's transient on-screen overlay,
# which disappears after a few seconds and cannot be copied or reviewed.

output=$(hyprpm reload 2>&1)
status=$?

# Strip ANSI color codes and box-drawing noise for the notification body.
clean=$(printf '%s\n' "$output" | sed -e 's/\x1b\[[0-9;]*m//g' | sed -e '/^\s*$/d')

if [ "$status" -ne 0 ]; then
    notify-send --app-name=hyprpm --urgency=critical \
        "hyprpm reload failed" "${clean:-hyprpm reload exited with status $status}"
else
    notify-send --app-name=hyprpm --urgency=low \
        "hyprpm" "Plugins loaded."
fi

exit "$status"
