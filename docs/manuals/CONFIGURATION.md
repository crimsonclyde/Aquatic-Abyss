# Configuration

Nothing about Aquatic Abyss is hardcoded to one machine. App choices, the
desktop backend, and every module setting live in plain files under
`~/.config/aquatic-abyss/`, outside the repository — so updating the checkout
never overwrites your preferences, and nothing personal ever needs to be
committed.

## `config.env`

Defaults ship in `config/defaults.env`. To override them, copy that file to
`~/.config/aquatic-abyss/config.env` (the installer offers to do this) and
edit it:

```bash
AA_BACKEND="noctalia"
AA_TERMINAL="kitty"
AA_BROWSER="chromium --disable-vulkan --ozone-platform=wayland"
AA_FILE_MANAGER="nautilus"
AA_MENU="wofi --show drun"
AA_IDE="vscodium"
AA_UPDATE_CMD="cachy-update"
```

| Variable | Bound to | Notes |
| :--- | :--- | :--- |
| `AA_BACKEND` | — | Desktop shell backend, see below |
| `AA_TERMINAL` | `SUPER + RETURN` | Full command line, arguments allowed |
| `AA_BROWSER` | `SUPER + B` | |
| `AA_FILE_MANAGER` | `SUPER + E` | |
| `AA_MENU` | `SUPER + SPACE` | Application launcher |
| `AA_IDE` | `SUPER + I` | |
| `AA_UPDATE_CMD` | `SUPER + SHIFT + U` | System update command |

Each value is a full command, so arguments and flags work as shown for
`AA_BROWSER`. If the file already exists the installer keeps it and asks no
questions.

Reload Hyprland (`SUPER + SHIFT + R`, or `hyprctl reload`) after editing.

## Desktop backends

`AA_BACKEND` selects the desktop backend behind the generic shell actions —
launcher, notifications, control centre, wallpaper, OSD, lock, and session UI.
Keybindings and bar buttons call the `scripts/aa/aa-*` wrapper commands, and
the wrappers dispatch to the selected backend.

| Value | Stack | Status |
| :--- | :--- | :--- |
| `noctalia` | The Noctalia shell — Quickshell bar, menus, OSD. Config in `.config/noctalia/` | Default |
| `classic` | Waybar + wofi + swaync + AGS | Deprecated, but complete |

`noctalia` requires the `noctalia` package (or `noctalia-git` from the AUR on
distributions whose repositories lack it). The startup in `hyprland.lua`
launches the matching stack. Unknown values, and any Noctalia call that fails
at runtime, fall back to classic with a warning — so a broken or missing
Noctalia never leaves you without a desktop.

## Module configuration

Machine-specific module settings — VPN accounts, Bluetooth device addresses —
live in `~/.config/aquatic-abyss/<module>.env`. Each module ships a committed
`<name>.env.example` template with empty values and a comment per setting.

See [MODULES.md](MODULES.md) for the per-module details.

## Shortcut overlay

Press `SUPER + H` to toggle the centered shortcut overlay. It runs as an AGS
layer-shell overlay via `scripts/shortcut-overlay.sh`, so it appears above
current windows without taking a workspace or becoming a tiled app window.
Press `SUPER + H` again, `Esc`, or the close button to hide it.

Shortcut data is maintained in `.config/ags/shortcut-overlay.json`. Add or edit
entries by changing the relevant section object:

```json
{ "key": "SUPER + Example", "action": "Describe the action" }
```

The view and styling live in `.config/ags/shortcut-overlay.tsx` and
`.config/ags/shortcut-overlay.css`. Dependencies are the existing AGS stack
used by the other popups; no additional package is required beyond the
configured `aylurs-gtk-shell` dependency.

The overlay's data is static, so module keybinds cannot be shown or hidden per
machine — optional entries are annotated *"(if installed)"* or *"(if
configured)"* instead.

## Checking your changes

After editing config files:

```bash
luac -p .config/hypr/hyprland.lua modules/*/binds.lua
Hyprland --verify-config --config .config/hypr/hyprland.lua
hyprdynamicmonitors validate --config .config/hyprdynamicmonitors/config.toml
```

See [INSTALL.md](INSTALL.md#verifying-the-installation) for the full list.
