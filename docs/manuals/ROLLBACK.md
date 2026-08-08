# Rollback

Rollback undoes an **entire** Aquatic Abyss installation — packages, config,
sudoers rules, login screen, everything — by restoring the system to a snapshot
taken before the installer touched anything.

It requires a Btrfs root filesystem and a rollback point created during
installation. To only remove the config and packages, see
[UNINSTALL.md](UNINSTALL.md).

## Creating a rollback point

On a Btrfs root the installer offers, before it touches anything, to snapshot
every subvolume that holds system or user state. CachyOS keeps `/`, `/root`,
and `/home` in separate subvolumes (`@`, `@root`, `@home`), and restoring `@`
alone would leave both home directories behind, so each one is snapshotted.

The offer is the very first prompt of the install — cloning the repository and
installing `git` are already changes, and a rollback should undo those too.

The offer is skipped, with the reason printed, when a rollback could not be
made to work — a non-Btrfs root, or fstab/kernel command line pinning
subvolumes by id rather than by name, which would keep booting the old
subvolume after a swap.

## Rolling back

```bash
sudo aquatic-abyss-rollback --dry-run   # show exactly what would happen
sudo aquatic-abyss-rollback             # restore and reboot
```

Always run `--dry-run` first and read what it plans to replace.

## How it works

The snapshots are read-only copies stored at the Btrfs top level, outside every
subvolume, so they survive the rollback itself. Restoring renames the current
subvolumes aside and puts the snapshots back under the original names — the
same mechanism `snapper rollback` uses, and the reason a reboot is required. If
a step fails partway, the script puts the original subvolumes back rather than
leaving a half-restored system.

## What is not restored

`/var/log` and `/var/cache` are separate subvolumes on CachyOS and are left
alone, so logs and downloaded packages survive a rollback.

## Cleaning up

The replaced subvolumes are kept as `*.pre-rollback-<timestamp>` and removed on
the next rollback. The final output of the rollback shows the command to delete
the rollback point itself once you no longer need it.
