# Aquatic Abyss

An advanced, keyboard-first Hyprland desktop inspired by the deep sea,
bioluminescence, and the timeless cosmic horror of the Great Old Ones.

![Waybar and AGS popups](docs/screenshots/waybar-popups.png)

The screenshot is a sanitized mock preview, not a live desktop capture.

## Features

| Area | What is included |
| :--- | :--- |
| Compositor | Hyprland Lua config, Dwindle layout, blur, animated borders, sane keybindings |
| Visibility | Hyprbars titlebars, compact Waybar clock, styled calendar tooltip, clear status buttons |
| Controls | AGS quick settings for WiFi, Bluetooth, VPN/Tailscale, wallpaper, idle inhibit, audio, updates, and notifications |
| Monitoring | AGS system stats popup for CPU, RAM, disk, temperature, GPU, power profile, and volume/mic controls |
| Help | AGS shortcut overlay with grouped keybinding reference |
| Monitors | HyprDynamicMonitors clamshell profiles for laptop and external display setups |
| Lock/Idle | Hypridle and Hyprlock with DPMS handling |
| Wallpaper | Hyprpaper startup, AGS thumbnail picker, random/apply actions, wallpaper rotation helper |
| Power | Wlogout layer-shell power menu |
| Screenshots | Hyprshot region/window capture piped into Satty |

![Wallpaper picker](docs/screenshots/wallpaper-picker-preview.png)

Wallpapers are picked from a thumbnail grid — see the
[wallpaper manual](docs/manuals/WALLPAPER.md).

## Install

Aquatic Abyss targets Arch/CachyOS-style systems. On an up-to-date machine:

```bash
curl -fsSL https://raw.githubusercontent.com/crimsonclyde/Aquatic-Abyss/master/install.sh | bash -s -- --deps --plugins
```

The installer asks before it changes anything: it offers a rollback point on
Btrfs, lets you pick the desktop shell and your terminal/browser/file manager,
and backs up existing config directories before symlinking its own into
`~/.config`.

For a step-by-step walkthrough on a fresh machine, the full list of installer
options, and what each package is for, see
**[docs/manuals/INSTALL.md](docs/manuals/INSTALL.md)**.

## Keybindings

`SUPER + key` opens applications and manages windows; `SUPER + SHIFT + key`
controls Aquatic Abyss panels, services, and hardware integrations.

| Key | Action |
| :--- | :--- |
| `SUPER + RETURN` | Open terminal (Kitty) |
| `SUPER + B` | Open browser (Chromium) |
| `SUPER + E` | Open file manager (Nautilus) |
| `SUPER + I` | Open IDE (VSCodium) |
| `SUPER + SPACE` | Open app launcher (Wofi) |
| `SUPER + H` | Toggle shortcut overlay |
| `SUPER + ESCAPE` | Open Wlogout (lock, logout, shutdown) |
| `SUPER + SHIFT + Q` | Toggle Quick Settings |
| `SUPER + SHIFT + T` | Toggle System Stats panel |
| `SUPER + SHIFT + R` | Reload Hyprland |
| `SUPER + SHIFT + U` | Run system update |
| `SUPER + Q` | Kill active window |
| `SUPER + F` | Toggle fullscreen |
| `SUPER + V` | Toggle floating |
| `SUPER + P` | Toggle pseudo tiling |
| `SUPER + G` | Toggle split direction |
| `SUPER + S` | Toggle special workspace |
| `SUPER + SHIFT + S` | Move window to special workspace |
| `SUPER + Arrow` | Move focus |
| `SUPER + SHIFT + Arrow` | Move window |
| `SUPER + CTRL + Arrow` | Resize window |
| `SUPER + [0-9]` | Switch workspace |
| `SUPER + SHIFT + [0-9]` | Move window to workspace |
| `SUPER + M` | Open nwg-displays |
| `SUPER + SHIFT/CTRL/ALT + M` | Monitor rescue (internal off / on / re-apply) |
| `PRINT` | Screenshot region |
| `SHIFT + PRINT` | Screenshot window |

Press `SUPER + H` at any time for the on-screen shortcut overlay.

`SUPER + RETURN`, `+ B`, `+ E`, `+ I`, and `+ SPACE` launch whichever apps you
configured — see [configuration](docs/manuals/CONFIGURATION.md). Additional
keybinds come from [modules](docs/manuals/MODULES.md): `SUPER + SHIFT + W` and
`+ V` open the WiFi and VPN pickers, `SUPER + SHIFT + B` toggles a Bluetooth
soundbar once configured, and optional apps bind only when installed.

## Documentation

| Manual | Contents |
| :--- | :--- |
| [Installation](docs/manuals/INSTALL.md) | Fresh-machine walkthrough, installer options, packages, post-install checks |
| [Configuration](docs/manuals/CONFIGURATION.md) | `config.env`, app choices, desktop backends, shortcut overlay |
| [Modules](docs/manuals/MODULES.md) | Optional features, how to enable and configure them, writing your own |
| [Wallpapers](docs/manuals/WALLPAPER.md) | Wallpaper directory, picker, rotation, fallbacks |
| [Rollback](docs/manuals/ROLLBACK.md) | Undoing the whole install from a Btrfs snapshot |
| [Uninstall](docs/manuals/UNINSTALL.md) | Removing the config, packages, and login screen |

## Security, privacy & disclaimer

Aquatic Abyss is a personal open-source project, shared in the hope that it is
useful to others. Please read this section before installing it.

**How it is built.** Development is AI-assisted ("vibe coding"): large parts of
the code and documentation are drafted by an AI coding agent, then reviewed and
functionally tested by a human maintainer before release. That workflow is fast
and honest about its limits — mistakes and bugs can still slip through.

**What it touches.** The installer installs packages, symlinks configuration
directories into `~/.config`, and — for some optional modules — writes
`sudoers` rules and enables system services. It is a shell script you can read
end to end before running it, and you are encouraged to do exactly that rather
than piping an unknown script into `bash`. Every prompt is opt-in, and existing
configuration is backed up to `~/.config/hypr_backup_<timestamp>` rather than
overwritten. On Btrfs systems the installer can take a
[rollback point](docs/manuals/ROLLBACK.md) before it changes anything.

**No AUR required.** A standard installation completes entirely from your
distribution's own repositories. A few optional extras (automatic monitor
profiles, and the Noctalia shell on distributions whose repos do not carry it)
live only in the AUR; the installer offers those separately, defaults to
**skipping** them, and never builds anything from the AUR without an explicit
yes.

**Privacy.** Nothing is phoned home, and no telemetry of any kind is collected.
The repository ships no personal data: committed configuration contains
defaults and empty `*.env.example` templates only. Everything
machine-specific — VPN accounts, Bluetooth device addresses, app
choices — stays in `~/.config/aquatic-abyss/` on your machine and never needs
to be committed anywhere. Module `sudoers` rules are installed per-module after
`visudo -cf` validation as `/etc/sudoers.d/zz-aquatic-<module>` and grant only
the specific commands that module needs.

**Disclaimer.** This software is provided "as is", without warranty of any
kind. The maintainer cannot guarantee that it works on your hardware or
distribution, and accepts no responsibility for damage, data loss, broken
systems, or downtime resulting from its use. Review what you install, keep
backups, and use it at your own risk. See [LICENSE](LICENSE) for the full
terms.

## License

[MIT](LICENSE).
