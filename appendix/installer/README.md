# Aquatic Abyss Experimental Installer

This is a modular replacement candidate for the root `install.sh`. Do not remove the root installer yet.

## Structure

- `install.sh`: entry point, mode selection, flow orchestration.
- `lib/ui.sh`: whiptail/dialog/text UI helpers.
- `lib/distro.sh`: `/etc/os-release` detection and support checks.
- `lib/checks.sh`: Hyprland/session checks, dependency reports, hardcoded path scan.
- `lib/packages.sh`: package groups and Arch/Debian install logic.
- `lib/config.sh`: config backup and symlink installation.
- `lib/wallpapers.sh`: safe copy from `appendix/wallpapers` to `~/Pictures/Wallpapers`.
- `lib/plugins.sh`: optional Hyprbars install through `hyprpm`.
- `lib/services.sh`: optional systemd service setup and Hyprland reload/start.
- `lib/summary.sh`: install plan, final summary, restore command.

## Modes

Run with:

```bash
bash appendix/installer/install.sh
bash appendix/installer/install.sh --auto
bash appendix/installer/install.sh --manual
bash appendix/installer/install.sh --dry-run
```

- Automatic: installs required package groups, config, safe wallpapers, and safe desktop services.
- Manual/custom: checklist for dependencies, config, wallpapers, Hyprbars, optional apps, GPU tools, services, and Hyprland reload/start.
- Dry run: detects the system and prints what would happen without changing files.

## Distros

Primary support is Arch/CachyOS through `pacman` plus AUR helpers (`paru` or `yay`) for AUR packages.

Debian, Ubuntu, and Linux Mint use best-effort `apt` package groups. Packages that are unavailable or not consistently named are reported as manual items instead of failing the whole install.

Unsupported distros do not run package installation automatically. Config-only install is allowed when Hyprland is already present.

## Package Groups

Packages are split into core, Hyprland tools, desktop tools, AUR, optional apps, GPU tools, and per-module package lists (`modules/<name>/packages.*`, e.g. the VPN tools in `modules/vpn-tailscale`). Optional personal apps are never installed in automatic mode.

## Restore Behavior

Existing config directories are moved to:

```text
~/.config/hypr_backup_YYYYMMDD_HHMMSS
```

The final summary prints an accurate restore command for configs that were actually backed up.

## Known Limitations

- Debian package coverage is best effort; some Hyprland ecosystem tools may need manual install.
- The installer reports hardcoded `/home/<user>/...` paths so they do not slip into public releases.
- Hyprbars installation is optional and non-fatal if `hyprpm` or the plugin repo fails.
- Tailscale is not started or logged in automatically.
