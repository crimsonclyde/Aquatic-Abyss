# Installing Acquatic Abyss

Acquatic Abyss targets Arch/CachyOS-style systems. This guide walks through a
complete installation on a **fresh CachyOS system**, from first login to a
running Hyprland session. If your machine is already set up and online, jump
straight to [step 4](#4-install-acquatic-abyss).

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

## 4. Install Acquatic Abyss

One-liner with dependencies, config install, Hyprbars plugin setup, and
Hyprland start:

```bash
curl -fsSL https://raw.githubusercontent.com/crimsonclyde/Acquatic-Abyss/master/install.sh | bash -s -- --deps --plugins --start
```

Or clone manually and run the installer yourself:

```bash
git clone https://github.com/crimsonclyde/Acquatic-Abyss.git ~/Documents/Repositories/github/Acquatic-Abyss
cd ~/Documents/Repositories/github/Acquatic-Abyss
./install.sh --deps --plugins
```

What the installer does:

- Asks which desktop shell backend you want: **noctalia** (newer, beta) or
  **classic** (Waybar + AGS + Hyprbars, deprecated but complete).
- Asks which terminal, browser, and file manager the keybindings should
  launch, and installs the ones you pick.
- Offers the bundled wallpapers and a multi-select menu of optional modules
  (WiFi picker, VPN picker, Bluetooth soundbar toggle, Framework fan
  control, extra app keybinds).
- Saves every choice to `~/.config/aquatic-abyss/config.env` — edit that
  file to change anything later; rerunning the installer keeps it.
- Clones the repository (or updates an existing clone).
- Installs required packages with `pacman` (`--deps`). Packages your distro
  repos do not carry are offered as an AUR build (`paru`/`yay`) only after an
  explicit confirmation — skipping them is fine and is the default.
- Backs up any existing config directories to
  `~/.config/hypr_backup_<timestamp>`, then symlinks the Acquatic Abyss
  config directories into `~/.config`.
- Sets up the Hyprbars plugin via `hyprpm` (`--plugins`).
- Asks per optional module (VPN, fan control, …) whether to install it — each
  module ships its own package list.

See the [README](README.md) for the full list of installer options and
package groups.

## 5. Start Hyprland

If you passed `--start`, Hyprland is already starting. Otherwise, from a TTY:

```bash
Hyprland
```

Or log out and pick the **Hyprland** session in SDDM.

## Uninstall

The installer only symlinks into `~/.config` and keeps a backup of what was
there before. See the [Uninstall section in the README](README.md#uninstall)
for the exact steps.
