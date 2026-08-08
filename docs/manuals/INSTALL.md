# Installing Aquatic Abyss

Aquatic Abyss targets Arch/CachyOS-style systems. This guide walks through a
complete installation on a **fresh CachyOS system**, from first login to a
running Hyprland session. If your machine is already set up and online, jump
straight to [step 4](#4-install-aquatic-abyss).

## 1. Log in

Boot the freshly installed system and log in with the user you created during
installation. Every step below works from a plain TTY — you do **not** need a
running desktop. If CachyOS boots into a graphical greeter (SDDM) with a
desktop you don't want to use, you can switch to a TTY with `Ctrl+Alt+F3` and
work from there.

> **Tip:** If the CachyOS installer offers Hyprland as a desktop edition,
> picking it is convenient — you get a working session and all Hyprland base
> packages up front. Any edition works, though: the installer pulls everything
> it needs.

## 2. Get online

CachyOS ships NetworkManager. Wired connections usually work out of the box.

For WiFi, the menu-driven way:

```bash
nmtui
```

Or directly on the command line:

```bash
nmcli device wifi list
nmcli device wifi connect "YOUR_SSID" password "YOUR_PASSWORD"
```

Verify connectivity:

```bash
ping -c 3 archlinux.org
```

## 3. Update the system

Bring the system fully up to date before installing anything:

```bash
sudo pacman -Syu
```

On CachyOS you can use its update helper instead, if present:

```bash
cachy-update
```

On a fresh installation there are no AUR packages yet, so a full system update
is safe and quick. If the update pulled in a new kernel, reboot before
continuing.

## 4. Install Aquatic Abyss

The one-liner installs dependencies, the config, and the Hyprbars plugin:

```bash
curl -fsSL https://raw.githubusercontent.com/crimsonclyde/Aquatic-Abyss/master/install.sh | bash -s -- --deps --plugins
```

Config-only, when the dependencies are already present:

```bash
curl -fsSL https://raw.githubusercontent.com/crimsonclyde/Aquatic-Abyss/master/install.sh | bash
```

Or clone manually and run the installer yourself — the recommended route if
you want to read the script first:

```bash
git clone https://github.com/crimsonclyde/Aquatic-Abyss.git ~/Documents/Repositories/github/Aquatic-Abyss
cd ~/Documents/Repositories/github/Aquatic-Abyss
./install.sh --deps --plugins
```

## 5. Start Hyprland

If the installer set up the login screen, reboot and pick the **Aquatic Abyss**
session. Otherwise, from a TTY:

```bash
Hyprland
```

Or log out and pick the **Hyprland** session in your display manager.

In an already-running Hyprland session, `hyprctl reload` (or
`SUPER + SHIFT + R`) is enough to pick up the new config.

---

## What the installer does

- On Btrfs root filesystems: offers a rollback point first, before anything is
  installed — snapshots of `/`, `/root`, and `/home`. Undo the whole install
  later with `sudo aquatic-abyss-rollback` (see
  [ROLLBACK.md](ROLLBACK.md)).
- Asks which desktop shell backend you want: **noctalia** (the default) or
  **classic** (Waybar + AGS + Hyprbars, deprecated but complete).
- Asks which terminal, browser, and file manager the keybindings should launch,
  and installs the ones you pick.
- Offers the bundled wallpapers and a multi-select menu of optional modules
  (WiFi picker, VPN picker, Bluetooth soundbar toggle, Framework fan control,
  extra app keybinds).
- Saves every choice to `~/.config/aquatic-abyss/config.env` — edit that file
  to change anything later; rerunning the installer keeps it.
- Clones the repository (or updates an existing clone).
- Installs required packages with `pacman` (`--deps`). Packages your distro
  repos do not carry are offered as an AUR build (`paru`/`yay`) only after an
  explicit confirmation — skipping them is fine and is the default.
- Backs up any existing config directories to
  `~/.config/hypr_backup_<timestamp>`, then symlinks the Aquatic Abyss config
  directories into `~/.config`.
- Sets up the Hyprbars plugin via `hyprpm` (`--plugins`).
- Asks per optional module (VPN, fan control, …) whether to install it — each
  module ships its own package list.
- Offers a themed login screen (greetd + ReGreet with the theme wallpaper) when
  no display manager is enabled yet, so the machine boots into a graphical
  login instead of a text console.

## Installer options

| Option | Action |
| :--- | :--- |
| `--deps` | Install required packages with `pacman`; anything only the AUR carries is offered as an explicitly confirmed `paru`/`yay` fallback |
| `--plugins` | Run `hyprpm update`, add `hyprwm/hyprland-plugins`, enable `hyprbars`, and reload plugins. Outside a running Hyprland session (e.g. TTY install) the add/enable half is deferred and runs automatically on first Hyprland start |
| `--start` | Finish by reloading a running Hyprland; from a TTY with the login screen enabled, offer a reboot into it instead. Optional — the installer never launches Hyprland directly, because starting it from a wrapper script is discouraged upstream |
| `-h`, `--help` | Show installer help |

Two environment variables are honoured:

| Variable | Effect |
| :--- | :--- |
| `AQUATIC_ABYSS_REPO` | Git repository to clone when run as a remote script |
| `AQUATIC_ABYSS_DIR` | Local checkout path (default: `~/Documents/Repositories/github/Aquatic-Abyss`) |

## What the installer asks

The installer is interactive (menus via `gum`, plain prompts as fallback). The
piped `curl | bash` one-liner reattaches your terminal after cloning, so it
asks the same questions as a local run; only truly headless runs (no terminal
at all) fall back to the defaults everywhere and never touch the AUR. It asks:

- **Rollback point** (Btrfs roots only, asked first) — snapshot the system
  before anything is installed, so the whole install can be undone. See
  [ROLLBACK.md](ROLLBACK.md).
- **Desktop shell** — **noctalia** (Quickshell bar, menus, and OSD — the
  default; adds the `noctalia` package — from the `cachyos` repo on CachyOS, or
  `noctalia-git` from the AUR elsewhere) or **classic** (Waybar + AGS menus +
  Hyprbars — deprecated but complete). Stored as `AA_BACKEND`.
- **Default applications** — the terminal, browser, and file manager launched
  by the desktop keybindings; the picked apps are installed with `--deps`.
- **Wallpapers** — copy the bundled set to `~/Pictures/Wallpapers` (never
  overwrites existing files).
- **Optional modules** — one multi-select menu (see [MODULES.md](MODULES.md)).
- **Login screen** (`--deps` only) — install and enable greetd + ReGreet with
  the theme wallpaper as background, plus an "Aquatic Abyss" session entry that
  starts Hyprland with this config. Asked only when no display manager is
  enabled yet; an existing one is always left untouched. Without any display
  manager the machine boots to a text console.

All choices land in `~/.config/aquatic-abyss/config.env` and can be changed
there at any time; if that file already exists the installer keeps it and asks
nothing. See [CONFIGURATION.md](CONFIGURATION.md).

## Packages

The core group installed by `--deps`:

```bash
sudo pacman -S --needed hyprland waybar wofi wlogout network-manager-applet blueman brightnessctl pamixer hypridle hyprlock hyprpaper hyprshot swaync upower jq lm_sensors power-profiles-daemon wireplumber cliphist wl-clipboard satty nwg-displays ksshaskpass git base-devel gum pavucontrol
```

The terminal, browser, and file manager are not in the core list — the
installer installs whichever ones you pick (defaults: kitty, chromium,
nautilus). Packages for optional features (VPN, extra apps, fan control, …) are
not in the core list either; each module ships its own package list and the
installer asks per module. See [MODULES.md](MODULES.md).

`--plugins` additionally installs the toolchain `hyprpm` needs to compile
Hyprland headers and plugins:

```bash
sudo pacman -S --needed base-devel cmake meson cpio git
```

### AUR packages are optional

Three more packages (`hyprdynamicmonitors-bin`, `waypaper`,
`aylurs-gtk-shell`) are not in the official Arch repos everywhere. The
installer checks your configured repositories first — on CachyOS, `waypaper`
comes from the `cachyos` repo via plain `pacman` — and only offers what is left
as an AUR build (`paru`/`yay`), after an explicit confirmation. AUR packages are
user-submitted and unreviewed, so the default is to skip them; the installer
prints the command to add them later.

Skipping costs the automatic monitor profiles (`hyprdynamicmonitors-bin`) and,
on the classic backend, the AGS menus (`aylurs-gtk-shell`). On distributions
whose repositories do not carry Noctalia, the default backend package
(`noctalia-git`) is an AUR build too — skipping it leaves the shell falling
back to classic.

If you use `yay` instead of `paru`, the installer will use it automatically.

### Ambiguous dependency providers

A few dependencies can be satisfied by more than one package, which would make
`pacman` stop and ask mid-install, so the installer names the provider itself:

| Dependency | Installed | When |
| :--- | :--- | :--- |
| `org.freedesktop.secrets` | `gnome-keyring` | always (needed by `ksshaskpass`, NetworkManager, Chromium) |
| `totem-plparser` | `totem-pl-parser` | with nautilus |
| `libliftoff` | `libliftoff` | with the login screen (`cage`) |

`gnome-keyring` is chosen because PAM unlocks it at login, so wifi, SSH, and
browser secrets work without opening anything first. None of these are touched
when something already provides them — install `kwallet`, `keepassxc`, or `oo7`
yourself beforehand and the installer leaves your choice alone.

## Verifying the installation

Useful checks after installing, or after editing any config file:

```bash
luac -p .config/hypr/hyprland.lua modules/*/binds.lua
Hyprland --verify-config --config .config/hypr/hyprland.lua
hyprdynamicmonitors validate --config .config/hyprdynamicmonitors/config.toml
bash -n install.sh scripts/*.sh scripts/lib/*.sh scripts/aa/aa-* modules/*/module.sh
bash scripts/lib/modules.sh manifest | jq .
```

The last command prints the modules that are currently *available* on this
machine — a module missing from that list is hidden on purpose, not broken.
See [MODULES.md](MODULES.md).

To confirm which desktop backend is active:

```bash
grep AA_BACKEND ~/.config/aquatic-abyss/config.env
```

## Undoing an installation

- **Whole system, back to before the install** — [ROLLBACK.md](ROLLBACK.md)
  (Btrfs only, requires a rollback point taken during install).
- **Just the Aquatic Abyss config and packages** —
  [UNINSTALL.md](UNINSTALL.md).
