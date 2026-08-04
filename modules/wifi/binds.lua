-- Open the Quick Settings WiFi picker directly. Loads even when no WiFi
-- interface exists (binds.lua files load regardless of `available`); the
-- picker then shows its empty state instead of breaking.
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd(REPO .. "/scripts/quick-settings.sh wifi"))
