# wifi

WiFi picker for the quick-settings menu: toggle the radio, list nearby networks
sorted by signal strength, and connect/disconnect on click. A waybar-compatible
`status` verb reports the current connection with signal icon, SSID, and IP.

- Keybind: `SUPER + SHIFT + W` (opens the picker)

## Requirements

- NetworkManager (`nmcli` in `PATH`) with at least one WiFi interface

Without a WiFi interface the picker is hidden.

## CLI

```
module.sh available   # "yes" iff nmcli sees a WiFi interface
module.sh list        # picker rows: "command\ticon\ttitle\tsubtitle\tactive"
module.sh run ACTION  # wifi:on, wifi:off, wifi:disconnect, wifi:connect:<ssid>
module.sh status      # one-line JSON {"text", "tooltip", "class"} for status bars
module.sh menu        # open the quick-settings WiFi picker
module.sh visible     # legacy yes/no alias of available (pre-module callers)
```

Connecting to a new secured network relies on NetworkManager's stored
credentials; networks without a saved profile may need a one-time
`nmcli device wifi connect <ssid> password <psk>` from a terminal.
