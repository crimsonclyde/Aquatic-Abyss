#!/usr/bin/env -S ags run
import app from "ags/gtk4/app"
import { Astal, Gtk } from "ags/gtk4"
import { createState } from "ags"
import Gdk from "gi://Gdk"
import GLib from "gi://GLib"
import css from "./shortcut-overlay.css"

type Shortcut = {
    key: string
    action: string
}

type ShortcutSection = {
    title: string
    items: Shortcut[]
}

const home = GLib.getenv("HOME") ?? ""
const repo = GLib.getenv("AQUATIC_ABYSS_DIR") ?? `${home}/Documents/Repositories/github/Acquatic-Abyss`
const dataFile = `${repo}/.config/ags/shortcut-overlay.json`
const [visible, setVisible] = createState(false)

function loadSections(): ShortcutSection[] {
    try {
        const [, contents] = GLib.file_get_contents(dataFile)
        return JSON.parse(new TextDecoder().decode(contents)) as ShortcutSection[]
    } catch (error) {
        printerr(`shortcut-overlay: failed to load ${dataFile}: ${error}`)
        return []
    }
}

const sections = loadSections()
const columns = [
    sections.filter((_, index) => index % 2 === 0),
    sections.filter((_, index) => index % 2 === 1),
]

function show() {
    setVisible(true)
}

function hide() {
    setVisible(false)
}

function toggle() {
    setVisible(!visible.get())
}

function ShortcutRow(props: { item: Shortcut }) {
    return (
        <box class="shortcut-row" orientation={Gtk.Orientation.HORIZONTAL} spacing={12}>
            <label class="shortcut-key" xalign={0} label={props.item.key} />
            <label class="shortcut-action" xalign={0} hexpand wrap label={props.item.action} />
        </box>
    )
}

function ShortcutSection(props: { section: ShortcutSection }) {
    return (
        <box class="shortcut-section" orientation={Gtk.Orientation.VERTICAL} spacing={4}>
            <label class="shortcut-section-title" xalign={0} label={props.section.title} />
            <box orientation={Gtk.Orientation.VERTICAL}>
                {props.section.items.map((item) => (
                    <ShortcutRow item={item} />
                ))}
            </box>
        </box>
    )
}

function ShortcutOverlay() {
    return (
        <window
            name="shortcut-overlay"
            visible={visible}
            layer={Astal.Layer.OVERLAY}
            exclusivity={Astal.Exclusivity.IGNORE}
            keymode={Astal.Keymode.ON_DEMAND}
            class="shortcut-window"
            $={(self) => {
                const controller = new Gtk.EventControllerKey()
                controller.connect("key-pressed", (_controller, keyval) => {
                    if (keyval === Gdk.KEY_Escape) {
                        hide()
                        return true
                    }

                    return false
                })
                self.add_controller(controller)
            }}
        >
            <box class="shortcut-panel" orientation={Gtk.Orientation.VERTICAL} spacing={10}>
                <box class="shortcut-header" orientation={Gtk.Orientation.HORIZONTAL}>
                    <label class="shortcut-title" xalign={0} hexpand label="Keyboard shortcuts" />
                    <button class="shortcut-close" tooltipText="Close" onClicked={hide}>
                        <label label="󰅖" />
                    </button>
                </box>

                <scrolledwindow
                    class="shortcut-scroll"
                    hscrollbarPolicy={Gtk.PolicyType.NEVER}
                    widthRequest={860}
                    heightRequest={560}
                >
                    <box class="shortcut-grid" orientation={Gtk.Orientation.HORIZONTAL} spacing={10}>
                        {columns.map((column) => (
                            <box class="shortcut-column" orientation={Gtk.Orientation.VERTICAL} spacing={10}>
                                {column.map((section) => (
                                    <ShortcutSection section={section} />
                                ))}
                            </box>
                        ))}
                    </box>
                </scrolledwindow>

                <label class="shortcut-hint" xalign={0} label="Toggle with SUPER + H. Hide with SUPER + H, Esc, or the close button." />
            </box>
        </window>
    )
}

app.start({
    instanceName: "ags-shortcut-overlay",
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
            hide()
            response("ok")
            return
        }

        response("unknown command")
    },
    main() {
        return <ShortcutOverlay />
    },
})
