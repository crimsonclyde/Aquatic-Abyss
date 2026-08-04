# Aquatic Abyss desktop backend interface — shared dispatch helper.
#
# Sourced by the aa-* wrapper commands in scripts/aa/. Loads the AA_*
# configuration (config/defaults.env, then ~/.config/aquatic-abyss/config.env)
# and dispatches to the backend implementation selected by AA_BACKEND.
#
# A wrapper defines one backend_<name>() function per backend it supports and
# ends with `aa_dispatch "$@"`. An unknown or unimplemented AA_BACKEND value
# falls back to classic with a warning, so the desktop keeps working even if
# AA_BACKEND is set to a backend that has not landed yet.
#
# See docs/prompts/NOCTALIA.md section 0 for the architecture.

AA_BACKEND_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${AQUATIC_ABYSS_DIR:-$(cd "$AA_BACKEND_LIB_DIR/../.." && pwd)}"

aa_load_config() {
    local defaults="$REPO/config/defaults.env"
    local user_config="${XDG_CONFIG_HOME:-$HOME/.config}/aquatic-abyss/config.env"

    if [ -f "$defaults" ]; then
        # shellcheck disable=SC1090
        . "$defaults"
    fi

    if [ -f "$user_config" ]; then
        # shellcheck disable=SC1090
        . "$user_config"
    fi
}

aa_load_config
AA_BACKEND="${AA_BACKEND:-classic}"

aa_dispatch() {
    local backend="$AA_BACKEND"

    if ! [[ "$backend" =~ ^[a-z][a-z0-9_]*$ ]] || ! declare -F "backend_$backend" >/dev/null; then
        printf 'aa: backend "%s" is not implemented by %s, falling back to classic\n' "$backend" "${0##*/}" >&2
        backend="classic"
    fi

    # Non-classic backends run without exec so a failure (daemon not running,
    # unmapped subcommand) can fall back to the classic implementation —
    # generic shell keys must never go dead. usage() exits directly and is
    # not caught here.
    if [ "$backend" != "classic" ]; then
        if "backend_$backend" "$@"; then
            return 0
        fi

        printf 'aa: %s backend failed in %s, falling back to classic\n' "$backend" "${0##*/}" >&2
    fi

    backend_classic "$@"
}
