#!/usr/bin/env -S ags run
import app from "ags/gtk4/app"
import { Astal, Gtk } from "ags/gtk4"
import { For, createState } from "ags"
import { timeout } from "ags/time"
import GLib from "gi://GLib"
import css from "./system-stats.css"

const home = GLib.getenv("HOME") ?? ""
// Checkouts from before the 2026-08 "Acquatic"→"Aquatic" rename keep the old directory name.
const defaultRepo = `${home}/Documents/Repositories/github/Aquatic-Abyss`
const legacyRepo = `${home}/Documents/Repositories/github/Acquatic-Abyss`
const repo = GLib.getenv("AQUATIC_ABYSS_DIR") ?? (GLib.file_test(defaultRepo, GLib.FileTest.IS_DIR) ? defaultRepo : legacyRepo)

const [visible, setVisible] = createState(false)
const [cpuText, setCpuText] = createState("CPU --")
const [memoryText, setMemoryText] = createState("RAM --")
const [diskText, setDiskText] = createState("Disk --")
const [tempText, setTempText] = createState("Temp --")
const [gpuText, setGpuText] = createState("GPU --")
const [batteryText, setBatteryText] = createState("Battery --")
const [powerText, setPowerText] = createState("Power --")
const [volumeText, setVolumeText] = createState("Volume --")
const [micText, setMicText] = createState("Mic --")
const [networkRows, setNetworkRows] = createState<string[][]>([])
const [monitorText, setMonitorText] = createState("Monitor --")
const [internalMonitorText, setInternalMonitorText] = createState("Internal monitor --")
const [externalMonitorText, setExternalMonitorText] = createState("External none")

type ModuleButton = { icon: string; action: string; tooltip?: string }
type ModuleRowData = {
    key: string
    script: string
    icon: string
    text: string
    status?: string
    buttons: ModuleButton[]
    refreshDelayMs: number
}

const [moduleRows, setModuleRows] = createState<ModuleRowData[]>([])
let hideTimer: ReturnType<typeof timeout> | null = null

function commandOutput(command: string) {
    try {
        const [, stdout] = GLib.spawn_command_line_sync(command)
        return new TextDecoder().decode(stdout).trim()
    } catch {
        return ""
    }
}

function exec(command: string) {
    GLib.spawn_command_line_async(command)
}

function shellQuote(value: string) {
    return `'${value.replace(/'/g, "'\\''")}'`
}

function fetchModuleRows() {
    const manifestJson = commandOutput(`${repo}/scripts/lib/modules.sh manifest`)
    const rows: ModuleRowData[] = []

    try {
        for (const entry of JSON.parse(manifestJson)) {
            if (!Array.isArray(entry?.rows)) {
                continue
            }

            entry.rows.forEach((row: any, index: number) => {
                if (row?.menu !== "system-stats") {
                    return
                }

                if (row?.type !== "stat" && row?.type !== "control-row") {
                    return
                }

                const buttons = row.type === "control-row" && Array.isArray(row.buttons)
                    ? row.buttons.filter((button: any) => button?.icon && button?.action)
                    : []

                rows.push({
                    key: `${entry.name}:${index}`,
                    script: entry.script,
                    icon: typeof row.icon === "string" ? row.icon : "",
                    text: "--",
                    status: typeof row.status === "string" ? row.status : undefined,
                    buttons,
                    refreshDelayMs: typeof row.refreshDelayMs === "number" ? row.refreshDelayMs : 300,
                })
            })
        }
    } catch {
        return []
    }

    return rows
}

function moduleStatusText(row: ModuleRowData) {
    if (!row.status) {
        return ""
    }

    try {
        const parsed = JSON.parse(commandOutput(`bash ${shellQuote(row.script)} ${shellQuote(row.status)}`))
        return typeof parsed.text === "string" ? parsed.text : "--"
    } catch {
        return "--"
    }
}

function refreshModuleManifest() {
    setModuleRows(fetchModuleRows())
}

function runModuleAction(row: ModuleRowData, action: string) {
    exec(`bash ${shellQuote(row.script)} ${shellQuote(action)}`)
    armHideTimer()
    timeout(row.refreshDelayMs, () => refreshStats())
}

function refreshStats() {
    const statsJson = commandOutput(`${repo}/scripts/quick-settings-stats.sh`)

    try {
        const stats = JSON.parse(statsJson)
        setCpuText(stats.cpu ?? "CPU --")
        setMemoryText(stats.memory ?? "RAM --")
        setDiskText(stats.disk ?? "Disk --")
        setTempText(stats.temperature ?? "Temp --")
        setGpuText(stats.gpu ?? "GPU --")
        setBatteryText(stats.battery ?? "Battery --")
        setPowerText(stats.power ?? "Power --")
        setVolumeText(stats.volume ?? "Volume --")
        setMicText(stats.mic ?? "Mic --")
        setNetworkRows(Array.isArray(stats.network) ? stats.network : [])
    } catch {
        setCpuText("CPU --")
        setMemoryText("RAM --")
        setDiskText("Disk --")
        setTempText("Temp --")
        setGpuText("GPU --")
        setBatteryText("Battery --")
        setPowerText("Power --")
        setVolumeText("Volume --")
        setMicText("Mic --")
        setNetworkRows([])
    }

    setModuleRows(moduleRows.get().map((row) => ({ ...row, text: moduleStatusText(row) })))
    refreshMonitorStatus()
}

function refreshMonitorStatus() {
    const monitorJson = commandOutput(`${repo}/scripts/monitor-control.sh status`)

    try {
        const monitor = JSON.parse(monitorJson)
        setMonitorText(`Monitor ${monitor.text ?? "--"}`)
        setInternalMonitorText(`Internal monitor ${monitor.internal ?? "--"}`)
        setExternalMonitorText(`External ${monitor.external ?? "none"}`)
    } catch {
        setMonitorText("Monitor --")
        setInternalMonitorText("Internal monitor --")
        setExternalMonitorText("External none")
    }
}

function cyclePowerProfile() {
    exec(`${repo}/scripts/powerprofile_cycle.sh switch >/dev/null 2>&1`)
    armHideTimer()
    timeout(350, () => refreshStats())
}

function runAudioAction(action: string) {
    exec(`${repo}/scripts/osd.sh ${action}`)
    armHideTimer()
    timeout(300, () => refreshStats())
}

function toggleInternalMonitor() {
    exec(`${repo}/scripts/monitor-control.sh internal-toggle`)
    armHideTimer()
    timeout(500, () => refreshMonitorStatus())
}

function armHideTimer() {
    hideTimer?.cancel()
    hideTimer = timeout(5000, () => setVisible(false))
}

function show() {
    refreshModuleManifest()
    refreshStats()
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

function StatRow(props: { icon: string; label: string }) {
    return (
        <box class="stats-row" orientation={Gtk.Orientation.HORIZONTAL} spacing={10}>
            <label class="stats-icon" label={props.icon} />
            <label class="stats-label" xalign={0} label={props.label} />
        </box>
    )
}

function NetworkRow(props: { row: string[] }) {
    const [title, address] = props.row

    return <StatRow icon="󰖟" label={`${title} ${address}`} />
}

function StatButton(props: { icon: string; label: string; onClicked: () => void }) {
    return (
        <button class="stats-row stats-button" onClicked={props.onClicked}>
            <box orientation={Gtk.Orientation.HORIZONTAL} spacing={10}>
                <label class="stats-icon" label={props.icon} />
                <label class="stats-label" xalign={0} label={props.label} />
            </box>
        </button>
    )
}

function IconButton(props: { label: string; onClicked: () => void; tooltip?: string }) {
    return (
        <button class="stats-control" tooltipText={props.tooltip ?? ""} onClicked={props.onClicked}>
            <label label={props.label} />
        </button>
    )
}

function ModuleRow(props: { row: ModuleRowData }) {
    const row = props.row

    if (row.buttons.length === 0) {
        return <StatRow icon={row.icon} label={row.text} />
    }

    return (
        <box class="stats-row stats-control-row" orientation={Gtk.Orientation.HORIZONTAL} spacing={8}>
            <label class="stats-icon" label={row.icon} />
            <label class="stats-label" xalign={0} hexpand label={row.text} />
            {row.buttons.map((button) => (
                <IconButton
                    label={button.icon}
                    tooltip={button.tooltip}
                    onClicked={() => runModuleAction(row, button.action)}
                />
            ))}
        </box>
    )
}

function AudioControlRow(props: {
    icon: string
    label: string
    downAction: string
    muteAction: string
    upAction: string
}) {
    return (
        <box class="stats-row stats-control-row" orientation={Gtk.Orientation.HORIZONTAL} spacing={8}>
            <label class="stats-icon" label={props.icon} />
            <label class="stats-label" xalign={0} hexpand label={props.label} />
            <IconButton label="−" onClicked={() => runAudioAction(props.downAction)} />
            <IconButton label="󰝟" onClicked={() => runAudioAction(props.muteAction)} />
            <IconButton label="󰐕" onClicked={() => runAudioAction(props.upAction)} />
        </box>
    )
}

function SystemStats() {
    const { TOP, RIGHT } = Astal.WindowAnchor

    return (
        <window
            name="system-stats"
            visible={visible}
            anchor={TOP | RIGHT}
            layer={Astal.Layer.OVERLAY}
            exclusivity={Astal.Exclusivity.IGNORE}
            class="stats-window"
        >
            <box class="stats-panel" orientation={Gtk.Orientation.VERTICAL} spacing={8}>
                <box class="stats-header" orientation={Gtk.Orientation.HORIZONTAL}>
                    <label class="stats-title" xalign={0} hexpand label="System stats" />
                    <button class="stats-close" onClicked={() => setVisible(false)}>
                        <label label="󰅖" />
                    </button>
                </box>

                <box orientation={Gtk.Orientation.VERTICAL} spacing={6}>
                    <AudioControlRow
                        icon="󰕾"
                        label={volumeText}
                        downAction="volume-down"
                        muteAction="volume-mute"
                        upAction="volume-up"
                    />
                    <AudioControlRow
                        icon=""
                        label={micText}
                        downAction="mic-down"
                        muteAction="mic-mute"
                        upAction="mic-up"
                    />
                    <StatButton icon="󰸗" label={powerText} onClicked={cyclePowerProfile} />
                </box>

                <box class="stats-divider" />

                <box orientation={Gtk.Orientation.VERTICAL} spacing={6}>
                    <StatRow icon="󰍹" label={monitorText} />
                    <StatButton icon="󰌢" label={internalMonitorText} onClicked={toggleInternalMonitor} />
                    <StatRow icon="󰹑" label={externalMonitorText} />
                </box>

                <box class="stats-divider" />

                <box visible={networkRows((rows) => rows.length > 0)} orientation={Gtk.Orientation.VERTICAL} spacing={6}>
                    <For each={networkRows}>{(row) => <NetworkRow row={row} />}</For>
                </box>

                <box visible={networkRows((rows) => rows.length > 0)} class="stats-divider" />

                <box orientation={Gtk.Orientation.VERTICAL} spacing={6}>
                    <StatRow icon="" label={cpuText} />
                    <StatRow icon="" label={memoryText} />
                    <StatRow icon="󰋊" label={diskText} />
                    <StatRow icon="" label={tempText} />
                    <StatRow icon="󰢮" label={gpuText} />
                    <StatRow icon="󰁹" label={batteryText} />
                </box>

                <box visible={moduleRows((rows) => rows.length > 0)} class="stats-divider" />

                <box visible={moduleRows((rows) => rows.length > 0)} orientation={Gtk.Orientation.VERTICAL} spacing={6}>
                    <For each={moduleRows}>{(row) => <ModuleRow row={row} />}</For>
                </box>
            </box>
        </window>
    )
}

app.start({
    instanceName: "ags-system-stats",
    css,
    requestHandler(argv, response) {
        const [command] = argv

        if (command === "ping") {
            response("pong")
            return
        }

        if (command === "show") {
            show()
            response("ok")
            return
        }

        if (command === "toggle") {
            toggle()
            response("ok")
            return
        }

        if (command === "hide") {
            setVisible(false)
            hideTimer?.cancel()
            response("ok")
            return
        }

        response("unknown command")
    },
    main() {
        return <SystemStats />
    },
})
