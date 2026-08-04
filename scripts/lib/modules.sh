#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${AQUATIC_ABYSS_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
MODULES_DIR="$REPO/modules"

usage() {
    echo "Usage: $0 list|manifest" >&2
    exit 2
}

list_modules() {
    local dir

    [ -d "$MODULES_DIR" ] || return 0

    for dir in "$MODULES_DIR"/*/; do
        [ -f "$dir/module.sh" ] || continue
        basename "$dir"
    done
}

module_available() {
    local script="$1"
    local answer

    # A misbehaving module must hide itself, never hang or break the menus.
    if command -v timeout >/dev/null 2>&1; then
        answer="$(timeout 2s bash "$script" available 2>/dev/null)" || return 1
    else
        answer="$(bash "$script" available 2>/dev/null)" || return 1
    fi

    [ "$answer" = "yes" ]
}

manifest() {
    local name dir script rows

    if ! command -v jq >/dev/null 2>&1; then
        echo "modules.sh: jq is required for manifest" >&2
        exit 1
    fi

    {
        for name in $(list_modules); do
            dir="$MODULES_DIR/$name"
            script="$dir/module.sh"

            module_available "$script" || continue

            rows="[]"
            if [ -f "$dir/menu.json" ]; then
                if ! rows="$(jq -c . "$dir/menu.json" 2>/dev/null)"; then
                    echo "modules.sh: invalid menu.json in $dir, ignoring rows" >&2
                    rows="[]"
                fi
            fi

            jq -cn --arg name "$name" --arg script "$script" --argjson rows "$rows" \
                '{name: $name, script: $script, rows: $rows}'
        done
    } | jq -s .
}

case "${1:-}" in
    list)
        list_modules
        ;;
    manifest)
        manifest
        ;;
    *)
        usage
        ;;
esac
