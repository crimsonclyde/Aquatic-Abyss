#!/usr/bin/env -S ags run
import app from "ags/gtk4/app"
import { Astal, Gtk } from "ags/gtk4"
import { For, createState } from "ags"
import { timeout } from "ags/time"
import GLib from "gi://GLib"
import css from "./quick-settings.css"

const home = GLib.getenv("HOME") ?? ""
const repo = GLib.getenv("AQUATIC_ABYSS_DIR") ?? `${home}/Documents/Repositories/github/Acquatic-Abyss`
const wallpaperDir = `${home}/Pictures/Wallpapers`
const terminal = commandOutput(`${repo}/scripts/lib/config.sh get AA_TERMINAL`) || "kitty"
const updateCmd = commandOutput(`${repo}/scripts/lib/config.sh get AA_UPDATE_CMD`) || "cachy-update"

const [visible, setVisible] = createState(false)
const [wallpaperVisible, setWallpaperVisible] = createState(false)
const [wallpapers, setWallpapers] = createState<string[]>([])
const [wallpaperRows, setWallpaperRows] = createState<string[][]>([])
const [currentWallpaper, setCurrentWallpaper] = createState("")

type ModuleButtonRow = { key: string; script: string; icon: string; label: string; action: string }
type ModulePickerDef = { key: string; name: string; script: string; icon: string; label: string; title: string; emptyText: string }
const [moduleButtons, setModuleButtons] = createState<ModuleButtonRow[]>([])
const [modulePickers, setModulePickers] = createState<ModulePickerDef[]>([])
const [pickerVisible, setPickerVisible] = createState(false)
const [pickerIcon, setPickerIcon] = createState("")
const [pickerTitle, setPickerTitle] = createState("")
const [pickerEmptyText, setPickerEmptyText] = createState("")
const [pickerRows, setPickerRows] = createState<string[][]>([])
let activePickerScript = ""
let hideTimer: ReturnType<typeof timeout> | null = null

function exec(command: string) {
    GLib.spawn_command_line_async(command)
}

function commandOutput(command: string) {
    try {
        const [, stdout] = GLib.spawn_command_line_sync(command)
        return new TextDecoder().decode(stdout).trim()
    } catch {
        return ""
    }
}

function shellQuote(value: string) {
    return `'${value.replace(/'/g, "'\\''")}'`
}

function displayName(path: string) {
    const name = path.split("/").pop() ?? path
    return name.replace(/\.[^.]+$/, "")
}

function chunk<T>(items: T[], size: number) {
    const rows: T[][] = []

    for (let index = 0; index < items.length; index += size) {
        rows.push(items.slice(index, index + size))
    }

    return rows
}

function armHideTimer() {
    hideTimer?.cancel()
    hideTimer = timeout(5000, () => setVisible(false))
}

function show() {
    setVisible(true)
    armHideTimer()
}

function toggle() {
    if (visible.get()) {
        setVisible(false)
        hideTimer?.cancel()
        return
    }

    show()
}

function action(command: string) {
    exec(command)
    setVisible(false)
    hideTimer?.cancel()
}

function refreshModuleButtons() {
    const manifestJson = commandOutput(`${repo}/scripts/lib/modules.sh manifest`)
    const buttons: ModuleButtonRow[] = []
    const pickers: ModulePickerDef[] = []

    try {
        for (const entry of JSON.parse(manifestJson)) {
            if (!Array.isArray(entry?.rows)) {
                continue
            }

            entry.rows.forEach((row: any, index: number) => {
                if (row?.menu !== "quick-settings" || typeof row.label !== "string") {
                    return
                }

                if (row?.type === "button" && typeof row.action === "string") {
                    buttons.push({
                        key: `${entry.name}:${index}`,
                        script: entry.script,
                        icon: typeof row.icon === "string" ? row.icon : "",
                        label: row.label,
                        action: row.action,
                    })
                }

                if (row?.type === "picker") {
                    pickers.push({
                        key: `${entry.name}:${index}`,
                        name: entry.name,
                        script: entry.script,
                        icon: typeof row.icon === "string" ? row.icon : "",
                        label: row.label,
                        title: typeof row.title === "string" ? row.title : row.label,
                        emptyText: typeof row.emptyText === "string" ? row.emptyText : "Nothing found",
                    })
                }
            })
        }
    } catch {
        setModuleButtons([])
        setModulePickers([])
        return
    }

    setModuleButtons(buttons)
    setModulePickers(pickers)
}

function runModuleButton(row: ModuleButtonRow) {
    action(`bash ${shellQuote(row.script)} ${shellQuote(row.action)}`)
}

function refreshPickerRows() {
    if (!activePickerScript) {
        return
    }

    const rows = commandOutput(`bash ${shellQuote(activePickerScript)} list`)
        .split("\n")
        .map((line) => line.split("\t"))
        .filter((row) => row.length >= 5)

    setPickerRows(rows)
}

function showModulePicker(picker: ModulePickerDef) {
    hideTimer?.cancel()
    activePickerScript = picker.script
    setPickerIcon(picker.icon)
    setPickerTitle(picker.title)
    setPickerEmptyText(picker.emptyText)
    refreshPickerRows()
    setVisible(false)
    setPickerVisible(true)
}

function hideModulePicker() {
    setPickerVisible(false)
}

function runPickerAction(command: string) {
    exec(`bash ${shellQuote(activePickerScript)} run ${shellQuote(command)}`)
    timeout(700, () => refreshPickerRows())
    timeout(2500, () => refreshPickerRows())
    // Slow providers (e.g. a Tailscale account switch) settle well after the click.
    timeout(12500, () => refreshPickerRows())
}

function refreshWallpapers() {
    const list = commandOutput(`${repo}/scripts/wallpaper_menu.sh list`)
        .split("\n")
        .map((path) => path.trim())
        .filter(Boolean)

    setWallpapers(list)
    setWallpaperRows(chunk(list, 3))
    setCurrentWallpaper(commandOutput(`${repo}/scripts/wallpaper_menu.sh current`))
}

function showWallpaperPicker() {
    hideTimer?.cancel()
    refreshWallpapers()
    setVisible(false)
    setWallpaperVisible(true)
}

function hideWallpaperPicker() {
    setWallpaperVisible(false)
}

function setWallpaper(path: string) {
    exec(`${repo}/scripts/wallpaper_menu.sh set ${shellQuote(path)}`)
    setCurrentWallpaper(path)
}

function randomWallpaper() {
    exec(`${repo}/scripts/wallpaper_menu.sh random`)
    timeout(450, () => refreshWallpapers())
}

function openWallpaperFolder() {
    exec(`nautilus ${shellQuote(wallpaperDir)}`)
}

function QuickButton(props: { icon: string; label: string; command?: string; onClicked?: () => void }) {
    return (
        <button
            class="quick-button"
            onClicked={() => {
                if (props.onClicked) {
                    props.onClicked()
                } else if (props.command) {
                    action(props.command)
                }
            }}
        >
            <box orientation={Gtk.Orientation.HORIZONTAL} spacing={10}>
                <label class="quick-icon" label={props.icon} />
                <label class="quick-label" xalign={0} label={props.label} />
            </box>
        </button>
    )
}

function NetworkButton(props: { row: string[]; command: (command: string) => void }) {
    const [command, icon, title, subtitle, active] = props.row

    return (
        <button
            class={active === "true" ? "network-row network-active" : "network-row"}
            onClicked={() => props.command(command)}
        >
            <box orientation={Gtk.Orientation.HORIZONTAL} spacing={10}>
                <label class="network-icon" label={icon} />
                <box orientation={Gtk.Orientation.VERTICAL} hexpand>
                    <label class="network-title" xalign={0} label={title} />
                    <label class="network-subtitle" xalign={0} label={subtitle} />
                </box>
                <label class="network-state" visible={active === "true"} label="󰄬" />
            </box>
        </button>
    )
}

function WallpaperTile(props: { path: string }) {
    const preview = Gtk.Picture.new_for_filename(props.path)
    preview.set_size_request(222, 130)
    preview.set_content_fit(Gtk.ContentFit.COVER)
    preview.add_css_class("wallpaper-thumb")

    return (
        <button
            class={currentWallpaper((current) =>
                current === props.path ? "wallpaper-tile wallpaper-active" : "wallpaper-tile",
            )}
            tooltipText={props.path}
            onClicked={() => setWallpaper(props.path)}
        >
            <box orientation={Gtk.Orientation.VERTICAL} spacing={6}>
                {preview}
                <box orientation={Gtk.Orientation.HORIZONTAL} spacing={6}>
                    <label
                        class="wallpaper-active-dot"
                        visible={currentWallpaper((current) => current === props.path)}
                        label="󰄬"
                    />
                    <label class="wallpaper-name" xalign={0} hexpand label={displayName(props.path)} />
                </box>
            </box>
        </button>
    )
}

function QuickSettings() {
    const { TOP, RIGHT } = Astal.WindowAnchor

    return (
        <window
            name="quick-settings"
            visible={visible}
            anchor={TOP | RIGHT}
            layer={Astal.Layer.OVERLAY}
            exclusivity={Astal.Exclusivity.IGNORE}
            class="quick-window"
        >
            <box class="quick-panel" orientation={Gtk.Orientation.VERTICAL} spacing={8}>
                <box class="quick-header" orientation={Gtk.Orientation.HORIZONTAL}>
                    <label class="quick-title" xalign={0} hexpand label="Quick settings" />
                    <button class="quick-close" onClicked={() => setVisible(false)}>
                        <label label="󰅖" />
                    </button>
                </box>

                <box orientation={Gtk.Orientation.VERTICAL} spacing={6}>
                    <QuickButton icon="󰂯" label="Bluetooth" command="blueman-manager" />
                    <QuickButton icon="󰸉" label="Wallpaper" onClicked={showWallpaperPicker} />
                    <QuickButton icon="󰈈" label="Toggle idle inhibit" command={`${repo}/scripts/idle-inhibit-toggle.sh`} />
                    <QuickButton icon="󰕾" label="Audio" command="pavucontrol" />
                    <QuickButton icon="󰂚" label="Notifications" command={`${repo}/scripts/aa/aa-notify panel`} />
                    <QuickButton icon="󰏖" label="System update" command={`${terminal} -e ${updateCmd}`} />
                    <QuickButton icon="󰓅" label="System monitor" command={`${terminal} -e btop`} />
                    <For each={moduleButtons}>
                        {(row) => <QuickButton icon={row.icon} label={row.label} onClicked={() => runModuleButton(row)} />}
                    </For>
                    <For each={modulePickers}>
                        {(picker) => <QuickButton icon={picker.icon} label={picker.label} onClicked={() => showModulePicker(picker)} />}
                    </For>
                </box>
            </box>
        </window>
    )
}

function ModulePicker() {
    return (
        <window
            name="module-picker"
            visible={pickerVisible}
            layer={Astal.Layer.OVERLAY}
            exclusivity={Astal.Exclusivity.IGNORE}
            class="vpn-window"
        >
            <box class="vpn-panel" orientation={Gtk.Orientation.VERTICAL} spacing={10}>
                <box class="menu-header" orientation={Gtk.Orientation.HORIZONTAL} spacing={10}>
                    <label class="menu-header-icon" label={pickerIcon} />
                    <box class="menu-title-group" orientation={Gtk.Orientation.VERTICAL} hexpand>
                        <label class="menu-title" xalign={0} label={pickerTitle} />
                        <label
                            class="menu-subtitle"
                            xalign={0}
                            label={pickerRows((rows) => `${rows.length} available`)}
                        />
                    </box>
                    <button class="vpn-control" tooltipText="Refresh" onClicked={refreshPickerRows}>
                        <label label="󰑓" />
                    </button>
                    <button class="vpn-close" onClicked={hideModulePicker}>
                        <label label="󰅖" />
                    </button>
                </box>

                <scrolledwindow
                    hscrollbarPolicy={Gtk.PolicyType.NEVER}
                    propagateNaturalHeight
                    maxContentHeight={408}
                >
                    <box class="vpn-list" orientation={Gtk.Orientation.VERTICAL} spacing={6}>
                        <label
                            class="vpn-empty"
                            visible={pickerRows((rows) => rows.length === 0)}
                            label={pickerEmptyText}
                        />
                        <For each={pickerRows}>{(row) => <NetworkButton row={row} command={runPickerAction} />}</For>
                    </box>
                </scrolledwindow>
            </box>
        </window>
    )
}

function WallpaperPicker() {
    return (
        <window
            name="wallpaper-picker"
            visible={wallpaperVisible}
            layer={Astal.Layer.OVERLAY}
            exclusivity={Astal.Exclusivity.IGNORE}
            class="wallpaper-window"
        >
            <box class="wallpaper-panel" orientation={Gtk.Orientation.VERTICAL} spacing={10}>
                <box class="menu-header" orientation={Gtk.Orientation.HORIZONTAL} spacing={10}>
                    <label class="menu-header-icon" label="󰸉" />
                    <box class="menu-title-group" orientation={Gtk.Orientation.VERTICAL} hexpand>
                        <label class="menu-title" xalign={0} label="Wallpaper Picker" />
                        <label
                            class="menu-subtitle"
                            xalign={0}
                            label={wallpapers((paths) => `${paths.length} wallpapers`)}
                        />
                    </box>
                    <button class="wallpaper-control" tooltipText="Open wallpapers folder" onClicked={openWallpaperFolder}>
                        <label label="" />
                    </button>
                    <button class="wallpaper-control" tooltipText="Random wallpaper" onClicked={randomWallpaper}>
                        <label label="" />
                    </button>
                    <button class="wallpaper-close" onClicked={hideWallpaperPicker}>
                        <label label="󰅖" />
                    </button>
                </box>

                <scrolledwindow
                    class="wallpaper-scroll"
                    hscrollbarPolicy={Gtk.PolicyType.NEVER}
                    widthRequest={760}
                    heightRequest={588}
                >
                    <box class="wallpaper-grid" orientation={Gtk.Orientation.VERTICAL} spacing={8}>
                        <label
                            class="wallpaper-empty"
                            visible={wallpapers((paths) => paths.length === 0)}
                            label="No wallpapers found"
                        />
                        <For each={wallpaperRows}>
                            {(row) => (
                                <box orientation={Gtk.Orientation.HORIZONTAL} spacing={8}>
                                    <For each={() => row}>{(path) => <WallpaperTile path={path} />}</For>
                                </box>
                            )}
                        </For>
                    </box>
                </scrolledwindow>
            </box>
        </window>
    )
}

app.start({
    instanceName: "ags-quick-settings",
    css,
    requestHandler(argv, response) {
        const [command] = argv

        if (command === "ping") {
            response("pong")
            return
        }

        if (command === "show") {
            refreshModuleButtons()
            show()
            response("ok")
            return
        }

        if (command === "toggle") {
            refreshModuleButtons()
            toggle()
            response("ok")
            return
        }

        if (command === "hide") {
            setVisible(false)
            setWallpaperVisible(false)
            setPickerVisible(false)
            hideTimer?.cancel()
            response("ok")
            return
        }

        if (command === "picker" || command === "vpn" || command === "wifi") {
            // "vpn"/"wifi" predate the generic picker; they map onto the modules.
            const name = command === "vpn" ? "vpn-tailscale" : command === "wifi" ? "wifi" : argv[1]

            refreshModuleButtons()
            const picker = modulePickers.get().find((entry) => entry.name === name)

            if (!picker) {
                response("unknown picker")
                return
            }

            showModulePicker(picker)
            response("ok")
            return
        }

        if (command === "wallpaper") {
            showWallpaperPicker()
            response("ok")
            return
        }

        response("unknown command")
    },
    main() {
        refreshModuleButtons()

        return (
            <>
                <QuickSettings />
                <ModulePicker />
                <WallpaperPicker />
            </>
        )
    },
})
