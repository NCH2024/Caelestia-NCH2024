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
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    property string searchQuery: ""
    property string categoryFilter: "All"
    property list<var> systemBindings: []
    property list<var> userBindings: []
    property bool loadedUserBinds: false
    property bool showAddShortcut: false

    // Builder state
    property bool modSuper: true
    property bool modCtrl: false
    property bool modShift: false
    property bool modAlt: true
    property string actionKind: "mode" // "mode" | "panel" | "command"
    property string selectedModeId: "gaming"
    property string selectedPanelCmd: "qs -c caelestia ipc call drawers openDashboardTab 3"
    property string statusBanner: ""

    readonly property var panelTargets: [
        { label: "Top Optimization Tab", cmd: "qs -c caelestia ipc call drawers openDashboardTab 3" },
        { label: "Top Performance Tab", cmd: "qs -c caelestia ipc call drawers openDashboardTab 2" },
        { label: "Modes & Routines Settings", cmd: "qs -c caelestia ipc call nexus openPage 0" },
        { label: "Power, Fans & Care Settings", cmd: "qs -c caelestia ipc call nexus openPage 1" },
        { label: "Studio Equalizer Settings", cmd: "qs -c caelestia ipc call nexus openPage 5" },
        { label: "Keybinds & Shortcuts", cmd: "qs -c caelestia ipc call nexus openPage 13" }
    ]

    readonly property var combinedBindings: {
        const q = root.searchQuery.trim().toLowerCase();
        const cat = root.categoryFilter;
        const all = [];
        for (let i = 0; i < root.userBindings.length; i++) {
            all.push(Object.assign({}, root.userBindings[i], { isCustom: true }));
        }
        for (let i = 0; i < root.systemBindings.length; i++) {
            all.push(Object.assign({}, root.systemBindings[i], { isCustom: false }));
        }
        return all.filter(b => {
            if (cat !== "All" && b.category !== cat)
                return false;
            if (q.length > 0) {
                const hay = `${b.combo} ${b.title} ${b.command} ${b.category}`.toLowerCase();
                if (!hay.includes(q))
                    return false;
            }
            return true;
        });
    }

    function currentComboString(): string {
        const mods = [];
        if (root.modCtrl) mods.push("CTRL");
        if (root.modSuper) mods.push("SUPER");
        if (root.modShift) mods.push("SHIFT");
        if (root.modAlt) mods.push("ALT");
        const k = keyInput.text.trim();
        if (!k)
            return "";
        return mods.length > 0 ? `${mods.join(" + ")} + ${k.toUpperCase()}` : k.toUpperCase();
    }

    function syncUserLuaAndReload(): void {
        const jsonStr = JSON.stringify(root.userBindings, null, 4);
        userBindsFile.setText(jsonStr);

        const luaLines = [
            "-- BEGIN CAELESTIA USER KEYBINDS",
            "-- Managed automatically by Nexus Keybinds & Shortcuts"
        ];
        for (let i = 0; i < root.userBindings.length; i++) {
            const b = root.userBindings[i];
            const safeCombo = String(b.combo).replace(/"/g, '\\"');
            const safeCmd = String(b.command).replace(/\\/g, "\\\\").replace(/"/g, '\\"');
            luaLines.push(`hl.bind("${safeCombo}", hl.dsp.exec_cmd("${safeCmd}"))`);
        }
        luaLines.push("-- END CAELESTIA USER KEYBINDS");
        const block = luaLines.join("\n");

        const py = `
import os, re, subprocess
p = os.path.expanduser("~/.config/caelestia/hypr-user.lua")
os.makedirs(os.path.dirname(p), exist_ok=True)
txt = open(p, "r", encoding="utf-8").read() if os.path.exists(p) else ""
block = ${JSON.stringify(block)}
pat = re.compile(r"-- BEGIN CAELESTIA USER KEYBINDS.*?-- END CAELESTIA USER KEYBINDS", re.S)
if pat.search(txt):
    new_txt = pat.sub(lambda _: block, txt)
else:
    sep = "\\n\\n" if txt.strip() else ""
    new_txt = txt.rstrip() + sep + block + "\\n"
with open(p, "w", encoding="utf-8") as f:
    f.write(new_txt)
subprocess.run(["hyprctl", "reload"], check=False)
print("Reloaded Hyprland keybinds cleanly")
`;
        syncProc.command = ["python3", "-c", py];
        syncProc.running = true;
    }

    function addCustomShortcut(): void {
        const combo = currentComboString();
        if (!combo) {
            root.statusBanner = "Please enter a key (e.g. F1, G, M, Space).";
            return;
        }
        let title = "";
        let cmd = "";
        if (root.actionKind === "mode") {
            if (root.selectedModeId === "cycle") {
                title = "Cycle System Mode (with Edge OSD)";
                cmd = "qs -c caelestia ipc call modes cycle";
            } else {
                const m = ExtraConfig.modes.find(x => x.id === root.selectedModeId);
                title = `Activate Mode: ${m ? (m.nameEn || m.name) : root.selectedModeId}`;
                cmd = `qs -c caelestia ipc call modes activate ${root.selectedModeId}`;
            }
        } else if (root.actionKind === "panel") {
            const p = root.panelTargets.find(x => x.cmd === root.selectedPanelCmd) ?? root.panelTargets[0];
            title = p.label;
            cmd = p.cmd;
        } else {
            cmd = customCmdInput.text.trim();
            if (!cmd) {
                root.statusBanner = "Please enter a command or application to launch.";
                return;
            }
            title = customTitleInput.text.trim() || `Run: ${cmd}`;
        }

        const next = root.userBindings.slice();
        next.push({
            id: "kb_" + Date.now(),
            combo: combo,
            title: title,
            command: cmd,
            category: "Custom"
        });
        root.userBindings = next;
        keyInput.text = "";
        customTitleInput.text = "";
        customCmdInput.text = "";
        root.showAddShortcut = false;
        root.statusBanner = `Saved & applied shortcut: ${combo}`;
        syncUserLuaAndReload();
    }

    function removeCustomShortcut(id: string): void {
        root.userBindings = root.userBindings.filter(x => x.id !== id);
        root.statusBanner = "Custom shortcut removed and Hyprland reloaded.";
        syncUserLuaAndReload();
    }

    title: Tr.tr("Keybinds & Shortcuts")

    Component.onCompleted: scanProc.running = true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Process {
            id: scanProc

            command: ["python3", "-c", `
import json, os, re

home = os.path.expanduser("~")
vars_path = os.path.join(home, ".config/hypr/variables.lua")

vars_map = {}
if os.path.exists(vars_path):
    txt = open(vars_path, encoding="utf-8").read()
    for m in re.finditer(r'(kb[A-Za-z0-9_]+)\\s*=\\s*"([^"]+)"', txt):
        vars_map[m.group(1)] = m.group(2)
    for m in re.finditer(r'(kb[A-Za-z0-9_]+)\\s*=\\s*\\{([^}]+)\\}', txt):
        vals = re.findall(r'"([^"]+)"', m.group(2))
        if vals:
            vars_map[m.group(1)] = "  /  ".join(vals)

entries = [
    ("Modes & System", vars_map.get("kbLauncher", "SUPER"), "Open App Launcher", "caelestia:launcher"),
    ("Modes & System", "SUPER + ALT + M", "Cycle System Mode (Edge OSD)", "qs -c caelestia ipc call modes cycle"),
    ("Modes & System", "SUPER + ALT + G", "Toggle Gaming & Turbo Mode", "qs -c caelestia ipc call modes toggleGaming"),
    ("Modes & System", "SUPER + ALT + O", "Open Top Optimization Tab", "qs -c caelestia ipc call drawers openDashboardTab 3"),
    ("Modes & System", "SUPER + ALT + K", "Open Keybinds & Shortcuts", "qs -c caelestia ipc call nexus openPage 13"),
    ("Shell", vars_map.get("kbShowSidebar", "SUPER + N"), "Toggle Notifications Sidebar", "caelestia:sidebar"),
    ("Shell", vars_map.get("kbShowPanels", "SUPER + K"), "Toggle All HUD Panels", "caelestia:showall"),
    ("Shell", vars_map.get("kbClearNotifs", "CTRL + ALT + C"), "Clear All Notifications", "caelestia:clearNotifs"),
    ("Shell", vars_map.get("kbSession", "CTRL + ALT + Delete"), "Open Session Power Menu", "caelestia:session"),
    ("Shell", "CTRL + ALT + Backspace", "Exit Hyprland Session cleanly", "hyprctl dispatch exit"),
    ("Shell", vars_map.get("kbLock", "SUPER + L"), "Lock Screen", "caelestia:lock"),
    ("Shell", vars_map.get("kbSleep", "SUPER + SHIFT + L"), "Suspend System", "systemctl suspend-then-hibernate"),
    ("Apps & Tools", vars_map.get("kbTerminal", "SUPER + T"), "Open Terminal", "foot"),
    ("Apps & Tools", vars_map.get("kbBrowser", "SUPER + W"), "Open Web Browser", "firefox"),
    ("Apps & Tools", vars_map.get("kbEditor", "SUPER + C"), "Open Code Editor", "codium"),
    ("Apps & Tools", vars_map.get("kbFileExplorer", "SUPER + E"), "Open File Manager", "thunar"),
    ("Apps & Tools", vars_map.get("kbClipboard", "SUPER + V"), "Open Clipboard History", "caelestia clipboard"),
    ("Apps & Tools", vars_map.get("kbEmoji", "SUPER + Period"), "Open Emoji Picker", "caelestia emoji -p"),
    ("Apps & Tools", vars_map.get("kbScreenshotFreeze", "SUPER + SHIFT + S"), "Screenshot Region (Freeze)", "caelestia:screenshotFreeze"),
    ("Apps & Tools", vars_map.get("kbRecord", "CTRL + ALT + R"), "Toggle Screen Recording", "caelestia record"),
    ("Apps & Tools", vars_map.get("kbColorPicker", "SUPER + SHIFT + C"), "Pick Screen Colour", "hyprpicker -a"),
    ("Windows", vars_map.get("kbCloseWindow", "SUPER + Q"), "Close Active Window", "window.close"),
    ("Windows", vars_map.get("kbWindowFullscreen", "SUPER + F"), "Toggle Fullscreen", "window.fullscreen"),
    ("Windows", vars_map.get("kbToggleWindowFloating", "SUPER + ALT + Space"), "Toggle Floating Window", "window.float"),
    ("Windows", vars_map.get("kbPinWindow", "SUPER + P"), "Pin Window Across Workspaces", "window.pin"),
    ("Windows", vars_map.get("kbWindowCycleNext", "ALT + TAB"), "Cycle Next Window", "window.cycle_next"),
    ("Windows", "SUPER + Arrow Keys", "Focus Window Left/Right/Up/Down", "focus direction"),
    ("Windows", "SUPER + SHIFT + Arrow Keys", "Move Window Left/Right/Up/Down", "window.move"),
    ("Workspaces", "SUPER + 1..9, 0", "Switch to Workspace 1–10", "workspace focus"),
    ("Workspaces", "SUPER + SHIFT + 1..9, 0", "Move Window Silently to Workspace", "workspace move_silent"),
    ("Workspaces", vars_map.get("kbNextWs", "SUPER + Page_Down"), "Next Workspace", "workspace +1"),
    ("Workspaces", vars_map.get("kbPrevWs", "SUPER + Page_Up"), "Previous Workspace", "workspace -1"),
    ("Workspaces", vars_map.get("kbSystemMonitorWs", "CTRL + SHIFT + Escape"), "Toggle System Monitor Workspace", "sysmon special"),
    ("Workspaces", vars_map.get("kbMusicWs", "SUPER + M"), "Toggle Music Workspace", "music special"),
]

out = [{"category": c, "combo": k, "title": t, "command": cmd} for c, k, t, cmd in entries]
print(json.dumps(out))
`]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        root.systemBindings = JSON.parse(text.trim());
                    } catch (e) {}
                }
            }
        }

        Process {
            id: syncProc
        }

        FileView {
            id: userBindsFile

            printErrors: false
            path: `${Paths.config}/user-keybinds.json`
            onLoaded: {
                try {
                    const parsed = JSON.parse(text());
                    if (Array.isArray(parsed))
                        root.userBindings = parsed;
                } catch (e) {}
                root.loadedUserBinds = true;
            }
            onLoadFailed: err => {
                root.loadedUserBinds = true;
                if (err === FileViewError.FileNotFound)
                    userBindsFile.setText("[]");
            }
        }

        // Hero & Add Shortcut Button
        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: heroCol.implicitHeight + Tokens.padding.large * 2
            first: true
            last: !root.showAddShortcut

            ColumnLayout {
                id: heroCol

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: 44
                        implicitHeight: 44
                        radius: 22
                        color: Colours.palette.m3primaryContainer

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "keyboard"
                            color: Colours.palette.m3onPrimaryContainer
                            fontStyle: Tokens.font.icon.medium
                            fill: 1
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: "Keyboard Shortcuts & Mode Hotkeys"
                            font: Tokens.font.title.medium
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.statusBanner.length > 0
                                ? root.statusBanner
                                : `${root.userBindings.length} custom shortcuts • ${root.systemBindings.length} built-in Hyprland bindings`
                            color: root.statusBanner.length > 0 ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }
                    }

                    StyledRect {
                        implicitWidth: addBtnRow.implicitWidth + Tokens.padding.large * 2
                        implicitHeight: 38
                        radius: 19
                        color: Colours.palette.m3primary

                        StateLayer {
                            radius: parent.radius
                            color: Colours.palette.m3onPrimary
                            onClicked: root.showAddShortcut = !root.showAddShortcut
                        }

                        RowLayout {
                            id: addBtnRow

                            anchors.centerIn: parent
                            spacing: 6

                            MaterialIcon {
                                text: root.showAddShortcut ? "expand_less" : "add"
                                color: Colours.palette.m3onPrimary
                                fontStyle: Tokens.font.icon.small
                            }

                            StyledText {
                                text: root.showAddShortcut ? "Close Builder" : "Add Shortcut"
                                color: Colours.palette.m3onPrimary
                                font: Tokens.font.label.medium
                            }
                        }
                    }
                }

                // Search input
                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3surfaceContainerHighest

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: "search"
                            color: Colours.palette.m3outline
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledTextField {
                            Layout.fillWidth: true
                            verticalAlignment: TextInput.AlignVCenter
                            background: null
                            placeholderText: "Search shortcuts (e.g. Mode, Gaming, SUPER, Screenshot)..."
                            onTextChanged: root.searchQuery = text
                        }
                    }
                }

                // Category Chips
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    Repeater {
                        model: ["All", "Custom", "Modes & System", "Shell", "Apps & Tools", "Windows", "Workspaces"]

                        delegate: StyledRect {
                            required property string modelData
                            readonly property bool active: root.categoryFilter === modelData

                            implicitWidth: catChipTxt.implicitWidth + Tokens.padding.medium * 2
                            implicitHeight: 28
                            radius: 14
                            color: active ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHighest

                            StateLayer {
                                radius: parent.radius
                                onClicked: root.categoryFilter = modelData
                            }

                            StyledText {
                                id: catChipTxt

                                anchors.centerIn: parent
                                text: modelData
                                font: Tokens.font.label.small
                                color: active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                            }
                        }
                    }
                }
            }
        }

        // Custom Shortcut Builder Card
        ConnectedRect {
            visible: root.showAddShortcut
            Layout.fillWidth: true
            implicitHeight: builderCol.implicitHeight + Tokens.padding.large * 2
            last: true

            ColumnLayout {
                id: builderCol

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledText {
                    text: "Create Custom Shortcut (Saved to hypr-user.lua)"
                    font: Tokens.font.title.small
                }

                // Modifiers + Key Input Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: [
                            { key: "super", label: "SUPER" },
                            { key: "ctrl", label: "CTRL" },
                            { key: "shift", label: "SHIFT" },
                            { key: "alt", label: "ALT" }
                        ]

                        delegate: StyledRect {
                            required property var modelData
                            readonly property bool active: modelData.key === "super" ? root.modSuper
                                : (modelData.key === "ctrl" ? root.modCtrl
                                : (modelData.key === "shift" ? root.modShift : root.modAlt))

                            implicitWidth: modTxt.implicitWidth + Tokens.padding.medium * 2
                            implicitHeight: 34
                            radius: Tokens.rounding.small
                            color: active ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest

                            StateLayer {
                                radius: parent.radius
                                onClicked: {
                                    if (modelData.key === "super") root.modSuper = !root.modSuper;
                                    else if (modelData.key === "ctrl") root.modCtrl = !root.modCtrl;
                                    else if (modelData.key === "shift") root.modShift = !root.modShift;
                                    else root.modAlt = !root.modAlt;
                                }
                            }

                            StyledText {
                                id: modTxt

                                anchors.centerIn: parent
                                text: modelData.label
                                font: Tokens.font.label.medium
                                color: active ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                            }
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: Tokens.rounding.small
                        color: Colours.palette.m3surfaceContainerHighest

                        StyledTextField {
                            id: keyInput

                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.medium
                            verticalAlignment: TextInput.AlignVCenter
                            placeholderText: "Key (e.g. G, M, F1, Space)..."
                        }
                    }
                }

                // Target Action Type
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: [
                            { id: "mode", label: "Switch Mode (with OSD)" },
                            { id: "panel", label: "Open UI Panel / Tab" },
                            { id: "command", label: "Custom App / Command" }
                        ]

                        delegate: StyledRect {
                            required property var modelData
                            readonly property bool active: root.actionKind === modelData.id

                            Layout.fillWidth: true
                            implicitHeight: 32
                            radius: Tokens.rounding.small
                            color: active ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHighest

                            StateLayer {
                                radius: parent.radius
                                onClicked: root.actionKind = modelData.id
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: modelData.label
                                font: Tokens.font.label.small
                                color: active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                            }
                        }
                    }
                }

                // Mode Picker
                Flow {
                    visible: root.actionKind === "mode"
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    StyledRect {
                        id: cycChip

                        readonly property bool sel: root.selectedModeId === "cycle"
                        implicitWidth: cycTxt.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: 30
                        radius: 15
                        color: cycChip.sel ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                        StateLayer {
                            radius: parent.radius
                            onClicked: root.selectedModeId = "cycle"
                        }

                        StyledText {
                            id: cycTxt
                            anchors.centerIn: parent
                            text: "Cycle Next Mode"
                            font: Tokens.font.label.small
                            color: cycChip.sel ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                        }
                    }

                    Repeater {
                        model: ExtraConfig.modes

                        delegate: StyledRect {
                            id: mpChip

                            required property var modelData
                            readonly property bool sel: root.selectedModeId === modelData.id

                            implicitWidth: mpTxt.implicitWidth + Tokens.padding.medium * 2
                            implicitHeight: 30
                            radius: 15
                            color: mpChip.sel ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                            StateLayer {
                                radius: parent.radius
                                onClicked: root.selectedModeId = modelData.id
                            }

                            StyledText {
                                id: mpTxt
                                anchors.centerIn: parent
                                text: modelData.nameEn || modelData.name
                                font: Tokens.font.label.small
                                color: mpChip.sel ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                            }
                        }
                    }
                }

                // Panel Picker
                Flow {
                    visible: root.actionKind === "panel"
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    Repeater {
                        model: root.panelTargets

                        delegate: StyledRect {
                            id: pnlChip

                            required property var modelData
                            readonly property bool sel: root.selectedPanelCmd === modelData.cmd

                            implicitWidth: pnlTxt.implicitWidth + Tokens.padding.medium * 2
                            implicitHeight: 30
                            radius: 15
                            color: pnlChip.sel ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                            StateLayer {
                                radius: parent.radius
                                onClicked: root.selectedPanelCmd = modelData.cmd
                            }

                            StyledText {
                                id: pnlTxt
                                anchors.centerIn: parent
                                text: modelData.label
                                font: Tokens.font.label.small
                                color: pnlChip.sel ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                            }
                        }
                    }
                }

                // Custom Command Fields
                ColumnLayout {
                    visible: root.actionKind === "command"
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: Tokens.rounding.small
                        color: Colours.palette.m3surfaceContainerHighest

                        StyledTextField {
                            id: customTitleInput
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.medium
                            verticalAlignment: TextInput.AlignVCenter
                            placeholderText: "Label (e.g. Launch Steam)..."
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: Tokens.rounding.small
                        color: Colours.palette.m3surfaceContainerHighest

                        StyledTextField {
                            id: customCmdInput
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.medium
                            verticalAlignment: TextInput.AlignVCenter
                            placeholderText: "Shell command (e.g. steam, kitty, pkill mpv)..."
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        Layout.fillWidth: true
                        text: root.currentComboString().length > 0 ? `Combo: ${root.currentComboString()}` : "Select modifiers + enter key"
                        font: Tokens.font.label.medium
                        color: Colours.palette.m3primary
                    }

                    StyledRect {
                        implicitWidth: saveKbTxt.implicitWidth + Tokens.padding.large * 2
                        implicitHeight: 36
                        radius: 18
                        color: Colours.palette.m3primary

                        StateLayer {
                            radius: parent.radius
                            color: Colours.palette.m3onPrimary
                            onClicked: root.addCustomShortcut()
                        }

                        StyledText {
                            id: saveKbTxt
                            anchors.centerIn: parent
                            text: "Save & Apply"
                            font: Tokens.font.label.medium
                            color: Colours.palette.m3onPrimary
                        }
                    }
                }
            }
        }

        // Bindings List
        SectionHeader {
            text: `Active Keybindings (${root.combinedBindings.length})`
        }

        Repeater {
            model: root.combinedBindings

            delegate: ConnectedRect {
                id: kbRow

                required property var modelData
                required property int index

                Layout.fillWidth: true
                implicitHeight: kbLayout.implicitHeight + Tokens.padding.medium * 2
                first: index === 0
                last: index === root.combinedBindings.length - 1

                RowLayout {
                    id: kbLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.large
                    anchors.rightMargin: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    // Keycap Pill
                    StyledRect {
                        implicitWidth: Math.max(120, comboTxt.implicitWidth + 18)
                        implicitHeight: 28
                        radius: Tokens.rounding.small
                        color: kbRow.modelData.isCustom ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest

                        StyledText {
                            id: comboTxt

                            anchors.centerIn: parent
                            text: kbRow.modelData.combo
                            font: Tokens.font.label.medium
                            color: kbRow.modelData.isCustom ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3primary
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        StyledText {
                            Layout.fillWidth: true
                            text: kbRow.modelData.title
                            font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: `${kbRow.modelData.category}  •  ${kbRow.modelData.command}`
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    IconButton {
                        visible: Boolean(kbRow.modelData.isCustom)
                        icon: "delete"
                        type: IconButton.Text
                        padding: Tokens.padding.extraSmall
                        inactiveOnColour: Colours.palette.m3error
                        onClicked: root.removeCustomShortcut(kbRow.modelData.id)
                    }
                }
            }
        }
    }
}
