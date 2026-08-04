#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${AQUATIC_ABYSS_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

DEFAULTS="$REPO/config/defaults.env"
USER_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/aquatic-abyss/config.env"

usage() {
    echo "Usage: $0 get <VAR>" >&2
    exit 2
}

case "${1:-}" in
    get)
        var="${2:-}"
        if ! [[ "$var" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            usage
        fi

        if [ -f "$DEFAULTS" ]; then
            # shellcheck disable=SC1090
            . "$DEFAULTS"
        fi

        if [ -f "$USER_CONFIG" ]; then
            # shellcheck disable=SC1090
            . "$USER_CONFIG"
        fi

        printf '%s\n' "${!var-}"
        ;;
    *)
        usage
        ;;
esac
