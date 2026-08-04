-- Toggle the configured Bluetooth soundbar. If no device is configured the
-- action notifies instead of failing silently; the quick-settings button is
-- hidden entirely via `module.sh available`.
hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd(REPO .. "/modules/bt-soundbar/module.sh toggle"))
