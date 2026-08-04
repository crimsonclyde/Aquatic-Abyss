--------------------------------------------------------------------------------
-- HYPRLAND LUA CONFIGURATION
--------------------------------------------------------------------------------

local home = os.getenv("HOME") or ""
local repo = os.getenv("AQUATIC_ABYSS_DIR") or (home .. "/Documents/Repositories/github/Acquatic-Abyss")
local hdm_monitors = home .. "/.cache/hyprdynamicmonitors/monitors.conf"

local mainMod = "SUPER"

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function load_env_file(path, values)
    local file = io.open(path, "r")
    if not file then
        return
    end

    for line in file:lines() do
        local clean_line = trim(line:gsub("#.*$", ""))
        local key, value = clean_line:match('^([A-Za-z_][A-Za-z0-9_]*)%s*=%s*"(.*)"%s*$')

        if not key then
            key, value = clean_line:match("^([A-Za-z_][A-Za-z0-9_]*)%s*=%s*(.-)%s*$")
        end

        if key and value and value ~= "" then
            values[key] = value
        end
    end

    file:close()
end

local app_config = {}
load_env_file(repo .. "/config/defaults.env", app_config)
load_env_file((os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")) .. "/aquatic-abyss/config.env", app_config)

local terminal = app_config.AA_TERMINAL or "kitty"
local fileManager = app_config.AA_FILE_MANAGER or "nautilus"
local menu = app_config.AA_MENU or "wofi --show drun"
local browser = app_config.AA_BROWSER or "chromium --disable-vulkan --ozone-platform=wayland"
local ide = app_config.AA_IDE or "vscodium"
local updateCmd = app_config.AA_UPDATE_CMD or "cachy-update"
local backend = app_config.AA_BACKEND or "classic"

-- Generic shell actions (launcher, session UI, control centre, OSD keys)
-- go through the desktop backend interface in scripts/aa/ — never through
-- tool names. The wrappers dispatch on AA_BACKEND (see config/defaults.env).
local aa = repo .. "/scripts/aa"

local function parse_scale(value)
    local number = tonumber(value)
    if number ~= nil then
        return number
    end

    return value
end

local function load_monitor_file(path)
    local file = io.open(path, "r")
    if not file then
        return
    end

    for line in file:lines() do
        local clean_line = trim(line:gsub("#.*$", ""))
        local disabled_output = clean_line:match("^monitor%s*=%s*([^,]*),%s*disable%s*$")
        local output, mode, position, scale = clean_line:match("^monitor%s*=%s*([^,]*),%s*([^,]*),%s*([^,]*),%s*([^,]*)")

        if disabled_output then
            hl.monitor({ output = trim(disabled_output), disabled = true })
        elseif output and mode and position and scale then
            hl.monitor({
                output = trim(output),
                mode = trim(mode),
                position = trim(position),
                scale = parse_scale(trim(scale)),
            })
        end
    end

    file:close()
end

local function setup_hyprbars()
    if hl.plugin == nil or hl.plugin.hyprbars == nil then
        return
    end

    hl.config({
        plugin = {
            hyprbars = {
                enabled = true,
                bar_height = 28,
                bar_color = "rgba(181c22f2)",
                bar_blur = true,
                bar_title_enabled = true,
                bar_text_size = 11,
                bar_text_font = "JetBrainsMono Nerd Font",
                bar_text_align = "left",
                bar_buttons_alignment = "right",
                bar_part_of_window = true,
                bar_precedence_over_border = true,
                bar_padding = 10,
                bar_button_padding = 6,
                icon_on_hover = false,
                inactive_button_color = "rgba(7d879655)",
                on_double_click = "hyprctl dispatch fullscreen 1",
                col = {
                    text = "rgba(f4f7fbff)",
                },
            },
        },
    })

    hl.plugin.hyprbars.add_button({
        bg_color = "rgba(33ccffee)",
        fg_color = "rgba(181c22ff)",
        size = 12,
        icon = "",
        action = "hyprctl dispatch fullscreen 1",
    })

    hl.plugin.hyprbars.add_button({
        bg_color = "rgba(eb4d4bee)",
        fg_color = "rgba(f4f7fbff)",
        size = 12,
        icon = "󰖭",
        action = "hyprctl dispatch killactive",
    })
end

--------------------------------------------------------------------------------
-- Monitors
--------------------------------------------------------------------------------

-- Laptop-first baseline for initial parsing. Do not load the
-- HyprDynamicMonitors cache here; it can contain a stale eDP-1 disable rule.
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1.5, disabled = false })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

--------------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------------

hl.on("hyprland.start", function()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE")
    hl.exec_cmd(repo .. "/scripts/hyprpm-reload-notify.sh")
    hl.exec_cmd(repo .. "/scripts/monitor-control.sh start-watch")
    hl.exec_cmd(repo .. "/scripts/monitor-control.sh apply")

    if backend == "noctalia" then
        -- Noctalia owns bar, notifications, OSD, and the wallpaper layer
        -- (config: .config/noctalia/). swaync must not start (both daemons
        -- claim the notification DBus name) and hyprpaper must not start
        -- (two wallpaper painters fight over the layer).
        hl.exec_cmd("noctalia -d")
    else
        hl.exec_cmd("waybar")
        hl.exec_cmd("swaync")
        hl.exec_cmd(repo .. "/scripts/ags-osd.sh start")
        hl.exec_cmd(repo .. "/scripts/wallpaper-start.sh")
        hl.exec_cmd(repo .. "/scripts/wallpaper_menu.sh rotate-start-if-enabled")
    end

    -- hypridle stays the single idle/lock owner in every backend; Noctalia's
    -- idle behaviors ship disabled (docs/prompts/NOCTALIA.md section 8, R7).
    hl.exec_cmd("hypridle")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)

--------------------------------------------------------------------------------
-- Environment
--------------------------------------------------------------------------------

hl.env("XCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("SSH_ASKPASS", "/usr/bin/ksshaskpass")
hl.env("SSH_ASKPASS_REQUIRE", "prefer")

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

hl.config({
    input = {
        kb_layout = "de",
        kb_variant = "",
        kb_model = "",
        kb_options = "",
        kb_rules = "",
        follow_mouse = 1,
        sensitivity = 0,

        touchpad = {
            natural_scroll = false,
        },
    },

    general = {
        gaps_in = 5,
        gaps_out = 10,
        border_size = 2,
        col = {
            active_border = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },
        layout = "dwindle",
        allow_tearing = false,
    },

    decoration = {
        rounding = 10,
        blur = {
            enabled = true,
            size = 3,
            passes = 1,
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
        smart_split = true,
    },
})

hl.curve("myBezier", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })

hl.animation({ leaf = "windows", enabled = true, speed = 7, bezier = "myBezier" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 7, bezier = "default", style = "popin 80%" })
hl.animation({ leaf = "border", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 8, bezier = "default" })
hl.animation({ leaf = "fade", enabled = true, speed = 7, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 6, bezier = "default" })

setup_hyprbars()

--------------------------------------------------------------------------------
-- Keybindings
--------------------------------------------------------------------------------

hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd(repo .. "/scripts/monitor-control.sh internal-off"))
hl.bind("SUPER + CTRL + M", hl.dsp.exec_cmd(repo .. "/scripts/monitor-control.sh internal-on"))
hl.bind("SUPER + ALT + M", hl.dsp.exec_cmd(repo .. "/scripts/monitor-control.sh apply"))

hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload"))
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("nwg-displays"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd(ide))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd(aa .. "/aa-launcher"))
hl.bind(mainMod .. " + H", hl.dsp.exec_cmd(repo .. "/scripts/shortcut-overlay.sh toggle"))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + G", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mainMod .. " + ESCAPE", hl.dsp.exec_cmd(aa .. "/aa-session"))
hl.bind(mainMod .. " + SHIFT + U", hl.dsp.exec_cmd(terminal .. " -e " .. updateCmd))

-- Aquatic Abyss panels (SUPER + SHIFT = Aquatic Abyss controls; exiting
-- Hyprland goes through the session UI on SUPER + ESCAPE instead of a
-- direct bind).
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.exec_cmd(aa .. "/aa-control-center toggle"))
hl.bind(mainMod .. " + SHIFT + T", hl.dsp.exec_cmd(repo .. "/scripts/system-stats.sh toggle"))
hl.bind("Print", hl.dsp.exec_cmd("hyprshot -m region --raw | satty -f -"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("hyprshot -m window --raw | satty -f -"))

hl.bind("F7", hl.dsp.exec_cmd(aa .. "/aa-brightness down"), { locked = true, repeating = true })
hl.bind("F8", hl.dsp.exec_cmd(aa .. "/aa-brightness up"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(aa .. "/aa-brightness down"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(aa .. "/aa-brightness up"), { locked = true, repeating = true })

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(aa .. "/aa-volume up"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(aa .. "/aa-volume down"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(aa .. "/aa-volume mute"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd(aa .. "/aa-volume mic-mute"), { locked = true })

hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "l" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "r" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "u" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "d" }))

hl.bind(mainMod .. " + SHIFT + left", hl.dsp.window.move({ direction = "l" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "r" }))
hl.bind(mainMod .. " + SHIFT + up", hl.dsp.window.move({ direction = "u" }))
hl.bind(mainMod .. " + SHIFT + down", hl.dsp.window.move({ direction = "d" }))

hl.bind(mainMod .. " + CTRL + left", hl.dsp.window.resize({ x = -40, y = 0, relative = true }))
hl.bind(mainMod .. " + CTRL + right", hl.dsp.window.resize({ x = 40, y = 0, relative = true }))
hl.bind(mainMod .. " + CTRL + up", hl.dsp.window.resize({ x = 0, y = -40, relative = true }))
hl.bind(mainMod .. " + CTRL + down", hl.dsp.window.resize({ x = 0, y = 40, relative = true }))

for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic", follow = false }))

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

--------------------------------------------------------------------------------
-- Module binds (modules/*/binds.lua — see modules/README.md)
--------------------------------------------------------------------------------

-- Globals available to module binds files.
REPO = repo
AA_BACKEND = backend
AA_TERMINAL = terminal
AA_BROWSER = browser
AA_FILE_MANAGER = fileManager
AA_MENU = menu
AA_IDE = ide
AA_UPDATE_CMD = updateCmd

local function load_module_binds()
    local ok, pipe = pcall(io.popen, "find '" .. repo .. "/modules' -mindepth 2 -maxdepth 2 -name binds.lua 2>/dev/null | sort")
    if not ok or pipe == nil then
        return
    end

    for path in pipe:lines() do
        local loaded, err = pcall(dofile, path)
        if not loaded then
            print("aquatic-abyss: skipping broken module binds " .. path .. ": " .. tostring(err))
        end
    end

    pipe:close()
end

load_module_binds()
