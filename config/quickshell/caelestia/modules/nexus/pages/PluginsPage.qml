pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property list<var> systemTimers: []
    property list<var> daemonsList: []
    property list<var> topProcesses: []

    readonly property list<MenuItem> nightTempItems: [
        MenuItem { text: "3500K (Warm)"; property int tempVal: 3500 },
        MenuItem { text: "4500K (Balanced)"; property int tempVal: 4500 },
        MenuItem { text: "5500K (Soft)"; property int tempVal: 5500 }
    ]

    function refreshAll(): void {
        if (!inspectProc.running)
            inspectProc.running = true;
    }

    function toggleDaemon(item: var): void {
        if (!item)
            return;
        if (item.kind === "systemd") {
            const act = item.active ? "stop" : "start";
            TaskRunner.run(`${act === "start" ? "Start" : "Stop"} ${item.name}`, `systemctl ${act} ${item.unit}`, true, item.icon);
        } else if (item.id === "fcitx5") {
            if (item.active)
                Quickshell.execDetached(["pkill", "-x", "fcitx5"]);
            else
                Quickshell.execDetached(["fcitx5", "-d", "--replace"]);
        } else if (item.id === "gammastep") {
            ExtraConfig.applyNightLight(!item.active, ExtraConfig.nightLightTemp);
        } else if (item.id === "cliphist") {
            if (item.active)
                Quickshell.execDetached(["pkill", "-f", "cliphist store"]);
            else
                Quickshell.execDetached(["sh", "-c", "wl-paste --type text --watch cliphist store </dev/null >/dev/null 2>&1 & wl-paste --type image --watch cliphist store </dev/null >/dev/null 2>&1 &"]);
        } else if (item.id === "mpris") {
            if (item.active)
                Quickshell.execDetached(["pkill", "-x", "mpris-proxy"]);
            else
                Quickshell.execDetached(["sh", "-c", "nohup mpris-proxy </dev/null >/dev/null 2>&1 &"]);
        }
        refreshTimer.restart();
    }

    function triggerTimerUnit(serviceUnit: string): void {
        if (!serviceUnit)
            return;
        TaskRunner.run(`Trigger ${serviceUnit}`, `systemctl start ${serviceUnit}`, true, "schedule");
        refreshTimer.restart();
    }

    function stopProcess(pid: int): void {
        Quickshell.execDetached(["kill", "-15", String(pid)]);
        refreshTimer.restart();
    }

    title: Tr.tr("Daemons, Timers & Processes")

    Component.onCompleted: refreshAll()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Timer {
            id: refreshTimer

            interval: 700
            onTriggered: root.refreshAll()
        }

        Process {
            id: inspectProc

            command: ["python3", "-c", `
import subprocess, json

def sh(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""

# 1. Scheduled Systemd Timers
timers = []
raw_timers = sh("systemctl list-timers --all --no-legend --no-pager")
for line in raw_timers.splitlines():
    parts = line.split()
    if len(parts) >= 4:
        # Find the .timer and .service tokens from the right
        unit = parts[-2] if parts[-2].endswith(".timer") else parts[-1]
        activates = parts[-1] if parts[-2].endswith(".timer") else ""
        idx = line.find(unit)
        schedule_info = line[:idx].strip()
        left_parts = schedule_info.split(";")
        next_run = left_parts[0].strip() if left_parts else schedule_info
        timers.append({
            "unit": unit,
            "activates": activates,
            "schedule": next_run[:52]
        })

# 2. Companion Daemons & System Services
def pgrep(pat, exact=True):
    flag = "-x" if exact else "-f"
    return bool(sh(f"pgrep {flag} '{pat}'"))

def is_active(unit):
    return sh(f"systemctl is-active {unit}") == "active"

daemons = [
    {"id": "fcitx5", "name": "Fcitx5 Input Method", "desc": "Multi-language & Vietnamese input engine", "icon": "keyboard", "kind": "user_proc", "active": pgrep("fcitx5", True)},
    {"id": "gammastep", "name": "Gammastep Night Light", "desc": "Blue light filter & eye comfort daemon", "icon": "nightlight", "kind": "user_proc", "active": pgrep("gammastep", True)},
    {"id": "cliphist", "name": "Cliphist Clipboard Watcher", "desc": "Clipboard history recorder (SUPER + V)", "icon": "content_paste", "kind": "user_proc", "active": pgrep("cliphist store", False)},
    {"id": "mpris", "name": "Bluetooth MPRIS Proxy", "desc": "Forwards headset media controls", "icon": "headphones", "kind": "user_proc", "active": pgrep("mpris-proxy", True)},
    {"id": "ppd", "name": "Power Profiles Daemon", "desc": "System CPU & platform power profile service", "icon": "bolt", "kind": "systemd", "unit": "power-profiles-daemon.service", "active": is_active("power-profiles-daemon.service")},
    {"id": "bluetooth", "name": "BlueZ Bluetooth Stack", "desc": "System Bluetooth controller daemon", "icon": "bluetooth", "kind": "systemd", "unit": "bluetooth.service", "active": is_active("bluetooth.service")},
    {"id": "nm", "name": "NetworkManager", "desc": "Wi-Fi, Ethernet & DNS connection manager", "icon": "wifi", "kind": "systemd", "unit": "NetworkManager.service", "active": is_active("NetworkManager.service")},
    {"id": "docker", "name": "Docker Engine", "desc": "Container runtime daemon", "icon": "deployed_code", "kind": "systemd", "unit": "docker.service", "active": is_active("docker.service")}
]

# 3. Top Active Processes
procs = []
raw_ps = sh("ps -eo pid=,comm=,%cpu=,%mem=,rss= --sort=-rss | head -n 8")
for l in raw_ps.splitlines():
    p = l.split()
    if len(p) >= 5:
        procs.append({
            "pid": int(p[0]),
            "name": p[1],
            "cpu": p[2],
            "mem": p[3],
            "mb": f"{int(p[4]) // 1024} MB"
        })

print(json.dumps({"timers": timers, "daemons": daemons, "procs": procs}))
`]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const d = JSON.parse(text.trim());
                        root.systemTimers = d.timers || [];
                        root.daemonsList = d.daemons || [];
                        root.topProcesses = d.procs || [];
                        const g = root.daemonsList.find(x => x.id === "gammastep");
                        if (g && ExtraConfig.nightLightEnabled !== g.active)
                            ExtraConfig.nightLightEnabled = g.active;
                    } catch (e) {}
                }
            }
        }

        // ---- 1. Background Daemons & System Services -------------------------
        SectionHeader {
            first: true
            text: Tr.tr("Background Daemons & System Services")
        }

        Repeater {
            model: root.daemonsList

            delegate: ConnectedRect {
                id: dmRow

                required property var modelData
                required property int index

                Layout.fillWidth: true
                implicitHeight: dmLayout.implicitHeight + Tokens.padding.medium * 2
                first: index === 0
                last: index === root.daemonsList.length - 1

                RowLayout {
                    id: dmLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.large
                    anchors.rightMargin: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: 38
                        implicitHeight: 38
                        radius: 19
                        color: dmRow.modelData.active ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: dmRow.modelData.icon
                            color: dmRow.modelData.active ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.small
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        StyledText {
                            Layout.fillWidth: true
                            text: dmRow.modelData.name
                            font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: `${dmRow.modelData.active ? "Running" : "Stopped"}  •  ${dmRow.modelData.desc}`
                            color: dmRow.modelData.active ? Colours.palette.m3primary : Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    StyledSwitch {
                        checked: Boolean(dmRow.modelData.active)
                        onToggled: root.toggleDaemon(dmRow.modelData)
                    }
                }
            }
        }

        SelectRow {
            first: true
            last: true
            label: "Night Light Color Temperature"
            subtext: "Adjust blue light warmth when Gammastep is active"
            menuItems: root.nightTempItems
            active: root.nightTempItems.find(i => i.tempVal === ExtraConfig.nightLightTemp) ?? root.nightTempItems[1]
            onSelected: item => {
                ExtraConfig.nightLightTemp = item.tempVal;
                if (ExtraConfig.nightLightEnabled)
                    ExtraConfig.applyNightLight(true, item.tempVal);
            }
        }

        // ---- 2. Scheduled Systemd Timers -------------------------------------
        SectionHeader {
            text: `Scheduled Systemd Timers (${root.systemTimers.length})`
        }

        Repeater {
            model: root.systemTimers

            delegate: ConnectedRect {
                id: tmrRow

                required property var modelData
                required property int index

                Layout.fillWidth: true
                implicitHeight: tmrLayout.implicitHeight + Tokens.padding.medium * 2
                first: index === 0
                last: index === root.systemTimers.length - 1

                RowLayout {
                    id: tmrLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.large
                    anchors.rightMargin: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: "schedule"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.medium
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        StyledText {
                            Layout.fillWidth: true
                            text: `${tmrRow.modelData.unit}  →  ${tmrRow.modelData.activates}`
                            font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: `Next / Last Schedule: ${tmrRow.modelData.schedule}`
                            color: Colours.palette.m3outline
                            font: Tokens.font.mono.small
                            elide: Text.ElideRight
                        }
                    }

                    StyledRect {
                        visible: Boolean(tmrRow.modelData.activates)
                        implicitWidth: runNowTxt.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: 28
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3secondaryContainer

                        StateLayer {
                            radius: parent.radius
                            onClicked: root.triggerTimerUnit(tmrRow.modelData.activates)
                        }

                        StyledText {
                            id: runNowTxt

                            anchors.centerIn: parent
                            text: "Run Now"
                            color: Colours.palette.m3onSecondaryContainer
                            font: Tokens.font.label.small
                        }
                    }
                }
            }
        }

        // ---- 3. Active Processes (Memory & CPU) ------------------------------
        SectionHeader {
            text: Tr.tr("Active Processes (Top Memory Usage)")
        }

        Repeater {
            model: root.topProcesses

            delegate: ConnectedRect {
                id: procRow

                required property var modelData
                required property int index

                Layout.fillWidth: true
                implicitHeight: pLayout.implicitHeight + Tokens.padding.medium * 2
                first: index === 0
                last: index === root.topProcesses.length - 1

                RowLayout {
                    id: pLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.large
                    anchors.rightMargin: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: "memory"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.small
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: `${procRow.modelData.name}  (PID ${procRow.modelData.pid})`
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    StyledText {
                        text: `CPU ${procRow.modelData.cpu}%  •  ${procRow.modelData.mb} (${procRow.modelData.mem}%)`
                        color: Colours.palette.m3outline
                        font: Tokens.font.mono.small
                    }

                    StyledRect {
                        implicitWidth: stopTxt.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: 28
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3errorContainer

                        StateLayer {
                            radius: parent.radius
                            onClicked: root.stopProcess(procRow.modelData.pid)
                        }

                        StyledText {
                            id: stopTxt

                            anchors.centerIn: parent
                            text: "Stop"
                            color: Colours.palette.m3onErrorContainer
                            font: Tokens.font.label.small
                        }
                    }
                }
            }
        }

        // ---- 4. Caelestia Shell Modules --------------------------------------
        SectionHeader {
            text: Tr.tr("Shell Modules & UI Extensions")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Desktop clock & weather overlay")
            subtext: Tr.tr("Render interactive clock and live weather widget on desktop")
            checked: Config.background.desktopClock.enabled
            onToggled: GlobalConfig.background.desktopClock.enabled = checked
        }

        ToggleRow {
            text: Tr.tr("Desktop audio visualiser (Cava)")
            subtext: Tr.tr("Real-time audio frequency spectrum on the desktop background")
            checked: Config.background.visualiser.enabled
            onToggled: GlobalConfig.background.visualiser.enabled = checked
        }

        ToggleRow {
            text: Tr.tr("Dashboard panel")
            subtext: Tr.tr("Top overview panel with calendar, media, performance & weather")
            checked: Config.dashboard.enabled
            onToggled: GlobalConfig.dashboard.enabled = checked
        }

        ToggleRow {
            text: Tr.tr("Application launcher")
            subtext: Tr.tr("Fuzzy app launcher, calculator, scheme switcher & actions")
            checked: Config.launcher.enabled
            onToggled: GlobalConfig.launcher.enabled = checked
        }

        ToggleRow {
            text: Tr.tr("Notification sidebar")
            subtext: Tr.tr("Grouped notification center and action dock")
            checked: Config.sidebar.enabled
            onToggled: GlobalConfig.sidebar.enabled = checked
        }

        ToggleRow {
            text: Tr.tr("Utilities & Quick Settings drawer")
            subtext: Tr.tr("Quick toggles, screen recorder and volume drawer")
            checked: Config.utilities.enabled
            onToggled: GlobalConfig.utilities.enabled = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("On-screen display (OSD)")
            subtext: Tr.tr("Floating volume and brightness overlay indicators")
            checked: Config.osd.enabled
            onToggled: GlobalConfig.osd.enabled = checked
        }
    }
}
