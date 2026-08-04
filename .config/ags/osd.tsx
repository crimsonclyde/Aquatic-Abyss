#!/usr/bin/env -S ags run
import app from "ags/gtk4/app"
import { Astal, Gtk } from "ags/gtk4"
import { createState } from "ags"
import { timeout } from "ags/time"
import css from "./osd.css"

type Kind = "brightness" | "volume" | "mic"

const [visible, setVisible] = createState(false)
const [kind, setKind] = createState<Kind>("brightness")
const [value, setValue] = createState(0)
const [valueText, setValueText] = createState("0%")
const [muted, setMuted] = createState(false)

let hideTimer: ReturnType<typeof timeout> | null = null

const icons: Record<Kind, string> = {
    brightness: "display-brightness-symbolic",
    volume: "audio-volume-high-symbolic",
    mic: "microphone-sensitivity-high-symbolic",
}

function show(nextKind: string, nextValue: string, nextMuted = "false") {
    const percent = Math.max(0, Math.min(100, Number.parseInt(nextValue, 10) || 0))

    setKind((nextKind as Kind) ?? "brightness")
    setValue(percent)
    setValueText(`${percent}%`)
    setMuted(nextMuted === "true" || nextMuted === "1")
    setVisible(true)

    hideTimer?.cancel()
    hideTimer = timeout(900, () => setVisible(false))
}

function OSD() {
    const { BOTTOM } = Astal.WindowAnchor

    return (
        <window
            name="osd"
            visible={visible}
            anchor={BOTTOM}
            layer={Astal.Layer.OVERLAY}
            exclusivity={Astal.Exclusivity.IGNORE}
            class="osd-window"
        >
            <box class="osd" orientation={Gtk.Orientation.HORIZONTAL} spacing={14}>
                <image class="osd-icon" iconName={kind((k) => muted() ? "audio-volume-muted-symbolic" : icons[k])} pixelSize={28} />
                <box class="osd-content" orientation={Gtk.Orientation.VERTICAL} spacing={7}>
                    <label class="osd-label" xalign={0} label={kind((k) => muted() ? `${k} muted` : k)} />
                    <levelbar class="osd-bar" widthRequest={210} value={value((v) => v / 100)} />
                </box>
                <label class="osd-value" label={valueText} />
            </box>
        </window>
    )
}

app.start({
    instanceName: "ags-osd",
    css,
    requestHandler(argv, response) {
        const [command, nextKind, nextValue, nextMuted] = argv

        if (command === "ping") {
            response("pong")
            return
        }

        if (command === "show") {
            show(nextKind, nextValue, nextMuted)
            response("ok")
            return
        }

        response("unknown command")
    },
    main() {
        return <OSD />
    },
})
