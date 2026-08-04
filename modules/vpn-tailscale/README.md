# vpn-tailscale

VPN picker for the quick-settings menu. Lists Tailscale (including multi-account
switching) plus every NetworkManager OpenVPN/WireGuard profile, and
connects/disconnects them on click. A waybar-compatible `status` verb reports
the current connection state.

- Keybind: `SUPER + SHIFT + V` (opens the picker)

## Requirements

At least one provider must be present, otherwise the picker is hidden:

- `tailscale` in `PATH` (package: `tailscale`), or
- NetworkManager with at least one VPN/WireGuard profile
  (`networkmanager-openvpn` / `networkmanager-wireguard`)

## Configuration (optional)

Copy `vpn-tailscale.env.example` to `~/.config/aquatic-abyss/vpn-tailscale.env`
to give Tailscale accounts and one OpenVPN profile friendly names. The legacy
location `~/.config/hypr/vpn_menu.env` is still read as a fallback. Without a
config file, everything is discovered automatically with generic labels.

## CLI

```
module.sh available   # "yes" iff any VPN provider is usable here
module.sh list        # picker rows: "command\ticon\ttitle\tsubtitle\tactive"
module.sh run ACTION  # run a row's command (tailscale:up, nm:up:<name>, ...)
module.sh status      # one-line JSON {"text", "tooltip", "class"} for status bars
module.sh menu        # open the quick-settings VPN picker
module.sh visible     # legacy yes/no alias of available (pre-module callers)
```

Actions are logged to `~/.local/state/aquatic-abyss-vpn.log`; failures raise a
desktop notification.
