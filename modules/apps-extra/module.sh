#!/usr/bin/env bash
set -euo pipefail

# Binds-only module: launchers for optional applications. There is no menu
# UI — binds.lua gates each keybind on its app being installed. `available`
# is always yes so the installers offer this module's packages; with no
# menu.json it contributes nothing to the menus.
case "${1:-}" in
    available)
        echo yes
        ;;
    *)
        echo "Usage: $(basename "$0") available" >&2
        exit 2
        ;;
esac
