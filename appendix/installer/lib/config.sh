#!/usr/bin/env bash

CONFIG_NAMES=(
    hypr
    hyprdynamicmonitors
    waypaper
    waybar
    ags
    wlogout
)

ensure_config_possible() {
    if [ "$STEP_CONFIG" -ne 1 ]; then
        return 0
    fi

    if [ "$HYPRLAND_INSTALLED" -eq 0 ] && [ "$STEP_DEPS" -eq 0 ]; then
        if [ "$MODE" = "auto" ]; then
            ui_error "Hyprland is not installed and dependency installation is disabled."
            return 1
        fi

        ui_warn "Hyprland is not installed. Config-only install may not be usable until Hyprland is installed."
        ui_confirm "Continue with config install anyway?" || return 1
    fi
}

install_config_links() {
    local name
    local source
    local target

    [ "$STEP_CONFIG" -eq 1 ] || return 0
    ensure_config_possible || return

    if [ "$DRY_RUN" -eq 1 ]; then
        for name in "${CONFIG_NAMES[@]}"; do
            source="$REPO_DIR/.config/$name"
            target="$HOME/.config/$name"
            ui_info "Would link $target -> $source"
        done
        return 0
    fi

    mkdir -p "$HOME/.config"

    for name in "${CONFIG_NAMES[@]}"; do
        source="$REPO_DIR/.config/$name"
        target="$HOME/.config/$name"
        link_one_config "$name" "$source" "$target"
    done

    return 0
}

link_one_config() {
    local name="$1"
    local source="$2"
    local target="$3"

    if [ ! -e "$source" ]; then
        ui_warn "Config source missing: $source"
        return
    fi

    if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
        CONFIG_LINKED+=("$target already linked")
        return
    fi

    if [ -e "$target" ] || [ -L "$target" ]; then
        mkdir -p "$BACKUP_DIR"
        mv "$target" "$BACKUP_DIR/"
        BACKED_UP_CONFIGS+=("$target")
        RESTORE_TARGETS+=("$target")
    fi

    ln -s "$source" "$target"
    CONFIG_LINKED+=("$target -> $source")
    ui_info "Linked $name."

    return 0
}

install_user_config() {
    local source="$REPO_DIR/config/defaults.env"
    local target_dir="${XDG_CONFIG_HOME:-$HOME/.config}/aquatic-abyss"
    local target="$target_dir/config.env"

    [ "$STEP_CONFIG" -eq 1 ] || return 0
    [ -f "$source" ] || return 0

    if [ -f "$target" ]; then
        CONFIG_LINKED+=("$target already present")
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        ui_info "Would copy $source -> $target"
        return 0
    fi

    if [ "$MODE" = "manual" ]; then
        ui_confirm "Copy default app choices to $target (edit it to change terminal, browser, etc.)?" || {
            ui_info "Skipping user config. Repo defaults will be used."
            return 0
        }
    fi

    mkdir -p "$target_dir"
    cp "$source" "$target"
    CONFIG_LINKED+=("$target (app choices copied from defaults)")
    ui_info "Created user config at $target."

    return 0
}

restore_command() {
    local target

    if [ "${#BACKED_UP_CONFIGS[@]}" -eq 0 ]; then
        printf 'No previous configs were backed up.\n'
        return
    fi

    printf 'rm -rf'
    for target in "${RESTORE_TARGETS[@]}"; do
        printf ' %q' "$target"
    done
    printf '\n'
    printf 'mv %q/* %q/\n' "$BACKUP_DIR" "$HOME/.config"
}
