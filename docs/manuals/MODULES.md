# Modules

Optional features live in `modules/` and are discovered dynamically — menu
rows, keybinds, packages, and sudoers rules all ship inside the module
directory.

The rule is **hidden, not broken**: a module that cannot work on your machine
(missing tool, missing hardware, missing configuration) simply does not appear
in any menu, instead of showing a dead button.

## Available modules

| Module | What it does | Appears when |
| :--- | :--- | :--- |
| `wifi` | WiFi network picker (`SUPER + SHIFT + W`) | a WiFi interface exists |
| `vpn-tailscale` | VPN/Tailscale picker (`SUPER + SHIFT + V`) | `tailscale` or a NetworkManager VPN profile exists |
| `framework-fan` | Fan control row (ChromeOS-EC laptops, e.g. Framework) | `/dev/cros_ec` + `ectool` exist |
| `bt-soundbar` | One-key Bluetooth speaker toggle (`SUPER + SHIFT + B`) | `bluetoothctl`, an adapter, **and** a configured device exist |
| `apps-extra` | Keybinds for optional apps (Element, Joplin, Signal) | always listed; each bind registers only if its app is installed |

Each module has its own `README.md` in `modules/<name>/` describing what it
needs and what it does.

## Installing modules

The installer presents a multi-select menu of modules and asks per module
whether to install its packages. Modules can also be installed later by
rerunning the installer.

Installing a module may add packages, a keybind, and — where the feature needs
root for a specific command — a `sudoers` rule at
`/etc/sudoers.d/zz-aquatic-<module>`, validated with `visudo -cf` before it is
written and scoped to only the commands that module needs.

## Configuring modules

Modules that need machine-specific values read them from
`~/.config/aquatic-abyss/<module>.env`, and ship a committed
`<name>.env.example` template with empty values.

`bt-soundbar` requires one-time configuration before it appears at all:

```bash
cp modules/bt-soundbar/bt-soundbar.env.example ~/.config/aquatic-abyss/bt-soundbar.env
$EDITOR ~/.config/aquatic-abyss/bt-soundbar.env    # set your paired device's MAC address
```

Until that file exists with a valid address, the module stays hidden — this is
the "hidden, not broken" rule working as intended.

## Checking which modules are active

```bash
bash scripts/lib/modules.sh manifest | jq .
```

This prints exactly the modules that are *available* on this machine, which is
what the menus render. A module missing from that list is not broken; its
preconditions are not met.

## Writing your own module

A module is one directory with a small `module.sh` CLI. Menus pick it up on
their next open, without restarting anything.

The full API — the `module.sh` contract, `menu.json` row types, `binds.lua`,
package lists, and sudoers rules — is documented in
[`modules/README.md`](../../modules/README.md).
