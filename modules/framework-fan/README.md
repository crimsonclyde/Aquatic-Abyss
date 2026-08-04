# framework-fan

Manual fan control for laptops with a ChromeOS embedded controller (Framework
13/16, Chromebooks) in the system-stats menu: a duty-cycle ladder from off to
max plus an "A" button that hands control back to the EC's automatic curve.

## Requirements

- `/dev/cros_ec` (the EC device — this is what makes the row appear)
- `ectool` or `fw-ectool` in `PATH` (AUR: `fw-ectool-git`)
- The bundled `sudoers` rule (installed by the installer as
  `/etc/sudoers.d/zz-aquatic-framework-fan`), because `ectool` needs root and
  the menu runs `sudo -n`.

Without any of these the row is hidden.

## CLI

```
module.sh available   # "yes" iff /dev/cros_ec exists and ectool is in PATH
module.sh status      # {"text": "Fan <rpm> RPM · <mode>", ...}
module.sh up|down     # step the manual duty ladder (0/20/40/60/80/100%)
module.sh auto        # back to EC automatic control
```
