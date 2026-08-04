-- Open the Quick Settings VPN picker directly. Loads even when no VPN
-- provider exists (binds.lua files load regardless of `available`); the
-- picker then shows its empty state instead of breaking.
hl.bind("SUPER + SHIFT + V", hl.dsp.exec_cmd(REPO .. "/scripts/quick-settings.sh vpn"))
