-- Optional application launchers — nothing here is required for the desktop
-- to function. Each bind registers only if its application is installed, so
-- machines without these apps get no dead keybinds. Core app binds (terminal,
-- browser, file manager, launcher, IDE) stay in hyprland.lua and honor the
-- AA_* config values.
--
-- Availability is probed with filesystem checks, not os.execute: Hyprland's
-- signal handling reaps children before Lua can read their exit status, so
-- os.execute always returns nil ("No child processes") in this environment.

local function path_exists(path)
    local handle = io.open(path, "r")
    if handle then
        handle:close()
        return true
    end
    return false
end

local function in_path(name)
    for dir in (os.getenv("PATH") or ""):gmatch("[^:]+") do
        if path_exists(dir .. "/" .. name) then
            return true
        end
    end
    return false
end

local function flatpak_app(app_id)
    local data_home = os.getenv("XDG_DATA_HOME") or ((os.getenv("HOME") or "") .. "/.local/share")
    return in_path("flatpak")
        and (path_exists(data_home .. "/flatpak/exports/bin/" .. app_id)
            or path_exists("/var/lib/flatpak/exports/bin/" .. app_id))
end

local function bind_if(present, combo, command)
    if present then
        hl.bind(combo, hl.dsp.exec_cmd(command))
    end
end

bind_if(in_path("element-desktop"), "SUPER + X", "element-desktop")
bind_if(in_path("joplin-desktop"), "SUPER + J", "joplin-desktop")
bind_if(flatpak_app("org.signal.Signal"), "SUPER + Y", "flatpak run org.signal.Signal")
