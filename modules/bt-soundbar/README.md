# bt-soundbar

Quick connect/disconnect toggle for one Bluetooth audio device (e.g. a
soundbar), via `bluetoothctl`.

- Quick-settings button: **Soundbar** (runs `toggle`)
- Keybind: `SUPER + SHIFT + B` (runs `toggle`)

## Requirements

- `bluetoothctl` (bluez) and a Bluetooth adapter
- The device must already be **paired** once (e.g. via `bluetoothctl` or
  blueman) — this module only connects/disconnects it
- A configured device (below)

## Configuration

Machine-specific settings live outside the repo. Copy
[`bt-soundbar.env.example`](bt-soundbar.env.example) to
`~/.config/aquatic-abyss/bt-soundbar.env` and set:

```bash
BT_SOUNDBAR_MAC="XX:XX:XX:XX:XX:XX"   # bluetoothctl devices
BT_SOUNDBAR_NAME="Living Room Soundbar"
```

Until `BT_SOUNDBAR_MAC` is set the module reports unavailable, so no button or
menu row appears ("hidden, not broken"). The `SUPER + SHIFT + B` keybind still
exists but only shows a "not configured" notification.

## CLI

```
module.sh available    # yes iff bluetoothctl + adapter + configured MAC
module.sh status       # {"text":"<name> connected|disconnected", ...}
module.sh connect
module.sh disconnect
module.sh toggle       # default
```

All bluetoothctl calls are capped at 10 s so a wedged bluetoothd cannot hang
the menus; failed actions notify and exit nonzero.
