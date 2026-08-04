# apps-extra

Keybinds for **optional** applications. Binds-only module: no menu rows, no
status — just `binds.lua`.

| Key         | Application               | Registered only if…                |
| ----------- | ------------------------- | ---------------------------------- |
| `SUPER + X` | Element (Matrix client)   | `element-desktop` in PATH          |
| `SUPER + J` | Joplin                    | `joplin-desktop` in PATH           |
| `SUPER + Y` | Signal (flatpak)          | flatpak app `org.signal.Signal`    |

Missing applications simply produce no keybind — nothing breaks, nothing
launches into the void. Install an app and `hyprctl reload` (or relogin) to
get its bind.

## Core vs optional bindings

**Core** bindings stay in `.config/hypr/hyprland.lua`: everything a basic
desktop needs — terminal, browser, file manager, app launcher, IDE, session
controls, window management, screenshots, monitor rescue. Core app choices are
user-configurable through `~/.config/aquatic-abyss/config.env` (`AA_TERMINAL`,
`AA_BROWSER`, `AA_IDE`, …). The IDE bind (`SUPER + I`) used to live here as a
hardcoded VSCodium launcher; it is core now because the IDE is configurable
like the other core apps.

**Optional** bindings live here: communication clients, note-taking apps,
editors — anything the desktop functions fine without. Add your own by
appending a `bind_if(...)` line to `binds.lua`.

## Packages

`packages.arch` / `packages.debian` list the optional apps the installers
offer for this module. `vscodium` stays in the list as the default `AA_IDE`
even though its keybind is core. The Signal flatpak itself is not
auto-installed — `flatpak install flathub org.signal.Signal` after enabling
flathub.
