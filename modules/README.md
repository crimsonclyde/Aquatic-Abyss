# Modules

Acquatic Abyss extensions live here. A module is just a directory — drop or clone
a folder into `modules/` and its menu rows, keybinds, and packages are picked up
automatically. If a module cannot function on the current machine (missing tool,
missing hardware), it is **hidden from every menu**, never shown broken.

## Layout

```
modules/<name>/
  module.sh          # REQUIRED — the module CLI (contract below)
  menu.json          # optional — menu rows this module contributes
  binds.lua          # optional — Hyprland keybinds/autostart (plain Lua, `hl` + REPO in scope)
  packages.arch      # optional — one pacman package per line
  packages.aur       # optional — one AUR package per line
  packages.debian    # optional — one apt package per line
  sudoers            # optional — installed as /etc/sudoers.d/zz-aquatic-<name>
  install.sh         # optional — extra install hook, run with repo root as $1
  <name>.env.example # optional — template for the module's user configuration
  README.md          # what it does, what hardware/tools it needs
```

Machine-specific values (device MACs, account IDs, …) must NEVER be committed.
A module that needs them reads `~/.config/aquatic-abyss/<name>.env` and ships a
committed `<name>.env.example` with empty/placeholder values. A module may
treat missing configuration as unavailable (see bt-soundbar) so it stays
hidden until the user configures it.

A missing `packages.<distro>` file means "no packages on this distro" — that is
fine and does not disable the module.

## module.sh contract

```
module.sh available   # print "yes" and exit 0 iff the module can function HERE
                      # (tools installed AND hardware present AND, if the module
                      # needs user config, that config exists). Anything else = hidden.
module.sh status      # (if menu.json references it) print one-line JSON, at least {"text": "..."}
module.sh <action>    # any action referenced by menu.json buttons
```

Modules may expose extra CLI subcommands beyond the contract (e.g.
`connect`/`disconnect`/`toggle`); binds.lua and external callers may use them
freely. Failed actions should notify the user and exit nonzero, and anything
that can hang (network, D-Bus) should run under `timeout`.

Rules for `module.sh`:

- `available` must be fast (**< 50 ms, no network**) — it runs every time a menu
  opens. Check `command -v <tool>` and device files, nothing heavier.
- Use `#!/usr/bin/env bash` and `set -euo pipefail`.
- No hardcoded personal paths; resolve the repo via `AQUATIC_ABYSS_DIR` with a
  fallback, like the scripts in `scripts/` do.
- Degrade gracefully when a tool is missing
  (`command -v X >/dev/null 2>&1 || ...`).

## menu.json schema

A JSON array. Three row types, matching the three existing UI patterns:

```jsonc
[
  { // stat/control row in the system-stats panel
    "menu": "system-stats",
    "type": "control-row",       // or "stat" for a read-only row (no buttons)
    "icon": "󰈐",
    "status": "status",          // module.sh subcommand whose JSON "text" becomes the label
    "buttons": [                  // omit for type "stat"
      { "icon": "−", "action": "down" },
      { "icon": "A", "action": "auto", "tooltip": "Back to automatic" },
      { "icon": "󰐕", "action": "up" }
    ],
    "refreshDelayMs": 300        // re-poll status this long after a button press
  },
  { // launcher button in quick-settings
    "menu": "quick-settings",
    "type": "button",
    "icon": "󰂯",
    "label": "Bluetooth",
    "action": "launch"           // module.sh subcommand; menu closes after
  },
  { // full-screen picker (the wifi/vpn pattern)
    "menu": "quick-settings",
    "type": "picker",
    "icon": "󰖂",
    "label": "VPN",
    "title": "VPN Connections",
    "emptyText": "No VPN providers found"
    // picker rows come from: module.sh list  → lines of "command\ticon\ttitle\tsubtitle\tactive"
    // row click runs:        module.sh run '<command>'
  }
]
```

### Picker protocol

`module.sh list` prints one row per line, five tab-separated fields:

```
command \t icon \t title \t subtitle \t active
```

- `command` — opaque string handed back to `module.sh run '<command>'` on click
- `icon` — a Nerd Font glyph
- `active` — `true` marks the row with a check; anything else means inactive

## binds.lua

Plain Lua, executed after the core Hyprland binds with the globals `hl` (the
Hyprland Lua API), `REPO` (repo root path), and the Phase 1 config values
(`AA_TERMINAL`, `AA_BROWSER`, ...) in scope. Errors are caught — a broken
module must not take down the Hyprland config — but keep it to binds and
autostart entries.

Two gotchas:

- `binds.lua` files load **regardless of `available`** (only menus consult the
  manifest). A bind whose feature may be unconfigured must fail politely when
  pressed — e.g. bt-soundbar notifies "not configured" instead of doing
  nothing.
- **`os.execute` does not work** under Hyprland's embedded Lua: the compositor
  reaps child processes before Lua can collect the exit status, so it always
  returns `nil, "No child processes"`. Gate binds with filesystem probes
  (`io.open` on `$PATH` entries, device files, flatpak `exports/bin`) — see
  `apps-extra/binds.lua`.

## sudoers

If a module ships a `sudoers` file, the installer validates it with `visudo -cf`
and installs it as `/etc/sudoers.d/zz-aquatic-<name>` (mode 0440). The `zz-`
prefix is load-bearing: sudoers is last-match-wins and reads `sudoers.d`
alphabetically, so the rule must sort after the distro's generic `%wheel` file
(e.g. `10-installer` on CachyOS) for `NOPASSWD` to take effect. Do not remove
the prefix.

## Discovery

`scripts/lib/modules.sh` provides:

- `modules.sh list` — names of all directories under `modules/` containing `module.sh`
- `modules.sh manifest` — one JSON array combining, for each **available**
  module: its name, absolute `module.sh` path, and the parsed `menu.json` rows.
  Unavailable modules are omitted entirely — this is the single place where
  "hidden, not broken" is enforced.

The AGS menus fetch the manifest at startup and on every `show`/`toggle`, so a
newly dropped-in module (or a newly installed tool) appears without restarting
anything.
