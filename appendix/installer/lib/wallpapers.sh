#!/usr/bin/env bash

install_wallpapers() {
    local source_dir="$REPO_DIR/appendix/wallpapers"
    local target_dir="$HOME/Pictures/Wallpapers"
    local wallpapers=()

    [ "$STEP_WALLPAPERS" -eq 1 ] || return 0

    if [ ! -d "$source_dir" ]; then
        ui_warn "Wallpaper source missing: $source_dir"
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        if [ -d "$target_dir" ] && [ -n "$(find "$target_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
            WALLPAPER_RESULT="Wallpaper folder already contains files; skipped to avoid overwriting."
            ui_warn "$WALLPAPER_RESULT"
        else
            mapfile -d '' -t wallpapers < <(find "$source_dir" -maxdepth 1 -type f -print0)
            WALLPAPER_RESULT="Would copy ${#wallpapers[@]} wallpapers to $target_dir."
            ui_info "$WALLPAPER_RESULT"
        fi

        return 0
    fi

    if [ "$MODE" = "manual" ]; then
        ui_confirm "Copy repo wallpapers to $target_dir?" || {
            WALLPAPER_RESULT="Skipped by user."
            return 0
        }
    fi

    if [ -d "$target_dir" ] && [ -n "$(find "$target_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
        if [ "$MODE" = "auto" ] || [ "$DRY_RUN" -eq 1 ]; then
            WALLPAPER_RESULT="Wallpaper folder already contains files; skipped to avoid overwriting."
            ui_warn "$WALLPAPER_RESULT"
            return 0
        fi

        ui_warn "$target_dir already contains files."
        ui_confirm "Proceed without deleting existing wallpapers?" || {
            WALLPAPER_RESULT="Skipped because target folder was not empty."
            return 0
        }
    fi

    mapfile -d '' -t wallpapers < <(find "$source_dir" -maxdepth 1 -type f -print0)

    if [ "${#wallpapers[@]}" -eq 0 ]; then
        WALLPAPER_RESULT="No wallpapers found in $source_dir."
        ui_warn "$WALLPAPER_RESULT"
        return 0
    fi

    mkdir -p "$target_dir"
    cp -n "${wallpapers[@]}" "$target_dir/"
    WALLPAPER_RESULT="Copied ${#wallpapers[@]} wallpapers to $target_dir."
    ui_info "$WALLPAPER_RESULT"

    return 0
}
