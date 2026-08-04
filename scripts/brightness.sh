#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
    up)
        exec "$SCRIPT_DIR/osd.sh" brightness-up
        ;;
    down)
        exec "$SCRIPT_DIR/osd.sh" brightness-down
        ;;
    *)
        echo "Usage: $0 up|down" >&2
        exit 2
        ;;
esac
