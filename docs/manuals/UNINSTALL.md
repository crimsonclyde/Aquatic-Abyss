# Uninstall

Aquatic Abyss installs itself by **symlinking** config directories into
`~/.config` and backing up whatever was there before to
`~/.config/hypr_backup_<timestamp>`. Removing it is correspondingly simple.

If you took a rollback point during installation and want the whole system
returned to its pre-install state instead, use
[ROLLBACK.md](ROLLBACK.md) — it undoes packages and system changes too.

## 1. Remove the config symlinks

The installer symlinks these seven directories:

```
~/.config/hypr    ~/.config/hyprdynamicmonitors    ~/.config/waypaper
~/.config/waybar  ~/.config/ags                    ~/.config/wlogout
~/.config/noctalia
```

Check what they point at before deleting anything, then remove the ones that
link into the Aquatic Abyss checkout:

```bash
ls -l ~/.config/{hypr,hyprdynamicmonitors,waypaper,waybar,ags,wlogout,noctalia}
ls -d ~/.config/hypr_backup_*           # the backup taken at install time
```

Afterwards, move the contents of the backup directory back into `~/.config` if
you want your old configuration returned.

## 2. Remove user configuration

Your machine-specific settings live outside the repository:

```bash
rm -rf ~/.config/aquatic-abyss
```

Wallpapers copied to `~/Pictures/Wallpapers` are ordinary files and are never
removed automatically.

## 3. Delete the repository clone

```bash
rm -rf ~/Documents/Repositories/github/Aquatic-Abyss
```

## 4. Remove module sudoers rules

Modules install their rules as `/etc/sudoers.d/zz-aquatic-<module>`:

```bash
sudo rm -f /etc/sudoers.d/zz-aquatic-*
```

## 5. Remove the login screen, if it was installed

If the installer set up greetd + ReGreet:

```bash
sudo systemctl disable greetd
sudo rm -f /etc/greetd/config.toml /etc/greetd/regreet.toml
sudo rm -f /usr/local/bin/aquatic-abyss-session
sudo rm -f /usr/share/wayland-sessions/aquatic-abyss.desktop
sudo rm -rf /usr/share/backgrounds/aquatic-abyss/
```

Disable greetd **before** uninstalling its packages, so the machine still has a
way to log in.

## 6. Remove packages

Installed packages are ordinary pacman packages and can be removed with your
package manager. The full lists are in [INSTALL.md](INSTALL.md); nothing
removes them automatically, since many (Hyprland itself, `git`, `jq`) are
likely wanted regardless.
