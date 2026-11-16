pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property string editingModeId: ExtraConfig.activeModeId
    property bool showAddRoutine: false
    property string newRoutineType: "process"
    property string newRoutineActionType: "mode"
    property string newRoutineActionMode: "gaming"

    readonly property var editingMode: ExtraConfig.modes.find(m => m.id === root.editingModeId) ?? ExtraConfig.modes[0]

    readonly property list<MenuItem> powerProfileItems: [
        MenuItem { text: "Power Saver"; property string profId: "power-saver"; icon: "energy_savings_leaf" },
        MenuItem { text: "Balanced"; property string profId: "balanced"; icon: "balance" },
        MenuItem { text: "Performance"; property string profId: "performance"; icon: "rocket_launch" }
    ]

    readonly property list<MenuItem> thermalModeItems: [
        MenuItem { text: "Balanced / Quiet Fans"; property string tId: "balanced"; icon: "air" },
        MenuItem { text: "Performance Thermal Curve"; property string tId: "performance"; icon: "speed" },
        MenuItem { text: "G-Mode Turbo (100% Fans)"; property string tId: "gmode"; icon: "mode_fan" }
    ]

    title: Tr.tr("Modes & Routines")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Active Mode Hero Card
        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: heroLayout.implicitHeight + Tokens.padding.large * 2
            first: true
            last: true

            RowLayout {
                id: heroLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledRect {
                    implicitWidth: 52
                    implicitHeight: 52
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3primary

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: ExtraConfig.activeModeIcon
                        color: Colours.palette.m3onPrimary
                        fontStyle: Tokens.font.icon.large
                        fill: 1
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: `Active Mode: ${ExtraConfig.activeModeName}`
                        font: Tokens.font.body.builders.large.weight(Font.Medium).build()
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            const tags = [`Power: ${ExtraConfig.powerProfileName}`];
                            if (GameMode.enabled)
                                tags.push("Game Mode FPS");
                            if (Notifs.dnd)
                                tags.push("Do Not Disturb");
                            if (IdleInhibitor.enabled)
                                tags.push("Keep Awake");
                            if (ExtraConfig.nightLightEnabled)
                                tags.push(`Night Light ${ExtraConfig.nightLightTemp}K`);
                            if (EqualizerService.enabled)
                                tags.push(`EQ: ${EqualizerService.activePresetName}`);
                            return tags.join(" • ");
                        }
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }

                StyledRect {
                    visible: ExtraConfig.activeModeId !== "standard"
                    implicitWidth: resetModeTxt.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: 34
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3secondaryContainer

                    StateLayer {
                        radius: parent.radius
                        onClicked: {
                            ExtraConfig.activateMode("standard");
                            root.editingModeId = "standard";
                        }
                    }

                    StyledText {
                        id: resetModeTxt

                        anchors.centerIn: parent
                        text: "Reset to Balanced"
                        color: Colours.palette.m3onSecondaryContainer
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        // Modes Grid Section
        SectionHeader {
            text: Tr.tr("System Modes")
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: modesGrid.implicitHeight + Tokens.padding.large * 2
            first: true
            last: true

            GridLayout {
                id: modesGrid

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                columns: 2
                columnSpacing: Tokens.spacing.small
                rowSpacing: Tokens.spacing.small

                Repeater {
                    model: ExtraConfig.modes

                    delegate: StyledRect {
                        id: modeCard

                        required property var modelData
                        readonly property bool isActive: ExtraConfig.activeModeId === modelData.id
                        readonly property bool isEditing: root.editingModeId === modelData.id

                        Layout.fillWidth: true
                        Layout.preferredWidth: Math.floor((modesGrid.width - modesGrid.columnSpacing) / 2)
                        implicitHeight: cardInner.implicitHeight + Tokens.padding.medium * 2
                        radius: Tokens.rounding.medium
                        color: isActive ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest
                        border.width: isEditing ? 2 : 0
                        border.color: Colours.palette.m3primary
                        clip: true

                        StateLayer {
                            radius: parent.radius
                            onClicked: {
                                ExtraConfig.activateMode(modeCard.modelData.id);
                                root.editingModeId = modeCard.modelData.id;
                            }
                        }

                        RowLayout {
                            id: cardInner

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.small

                            StyledRect {
                                implicitWidth: 40
                                implicitHeight: 40
                                radius: Tokens.rounding.full
                                color: modeCard.isActive ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: modeCard.modelData.icon
                                    color: modeCard.isActive ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                                    fontStyle: Tokens.font.icon.medium
                                    fill: modeCard.isActive ? 1 : 0
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modeCard.modelData.nameEn || modeCard.modelData.name
                                    color: modeCard.isActive ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                                    font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modeCard.modelData.descriptionEn || modeCard.modelData.description
                                    color: modeCard.isActive ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3outline
                                    font: Tokens.font.label.small
                                    maximumLineCount: 2
                                    wrapMode: Text.WordWrap
                                    elide: Text.ElideRight
                                }
                            }

                            IconButton {
                                icon: "tune"
                                type: IconButton.Text
                                padding: Tokens.padding.extraSmall
                                inactiveOnColour: modeCard.isActive ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                                onClicked: root.editingModeId = modeCard.modelData.id
                            }
                        }
                    }
                }
            }
        }

        // Mode Customizer Section
        SectionHeader {
            text: `Customize Mode: ${root.editingMode?.nameEn ?? root.editingMode?.name ?? ""}`
        }

        SelectRow {
            first: true
            label: "Power Profile"
            subtext: "System CPU & platform power profile when this mode is active"
            menuItems: root.powerProfileItems
            active: root.powerProfileItems.find(i => i.profId === (root.editingMode?.powerProfile ?? "balanced")) ?? root.powerProfileItems[1]
            onSelected: item => ExtraConfig.updateModeProperty(root.editingModeId, "powerProfile", item.profId)
        }

        SelectRow {
            label: "Thermal & Fan Profile"
            subtext: "Cooling curve and fan boost behavior for this mode"
            menuItems: root.thermalModeItems
            active: root.thermalModeItems.find(i => i.tId === (root.editingMode?.thermalMode ?? "balanced")) ?? root.thermalModeItems[0]
            onSelected: item => ExtraConfig.updateModeProperty(root.editingModeId, "thermalMode", item.tId)
        }

        ToggleRow {
            text: "Hyprland Game Mode (FPS Boost)"
            subtext: "Disable blur, shadows and animations for minimum input latency"
            checked: Boolean(root.editingMode?.gameMode)
            onToggled: ExtraConfig.updateModeProperty(root.editingModeId, "gameMode", checked)
        }

        ToggleRow {
            text: "Do Not Disturb"
            subtext: "Silence popup notifications while in this mode"
            checked: Boolean(root.editingMode?.dnd)
            onToggled: ExtraConfig.updateModeProperty(root.editingModeId, "dnd", checked)
        }

        ToggleRow {
            text: "Keep Screen Awake (Idle Inhibitor)"
            subtext: "Prevent screen blanking and automatic system sleep"
            checked: Boolean(root.editingMode?.keepAwake)
            onToggled: ExtraConfig.updateModeProperty(root.editingModeId, "keepAwake", checked)
        }

        ToggleRow {
            text: "Night Light Eye Comfort"
            subtext: "Warm screen color temperature to reduce blue light"
            checked: Boolean(root.editingMode?.nightLight)
            onToggled: ExtraConfig.updateModeProperty(root.editingModeId, "nightLight", checked)
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: eqPresetCol.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: eqPresetCol

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                StyledText {
                    text: "Associated Studio Equalizer Preset"
                    font: Tokens.font.body.small
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: EqualizerService.presets

                        delegate: StyledRect {
                            required property var modelData
                            readonly property bool selected: (root.editingMode?.eqPreset ?? "flat") === modelData.id

                            implicitWidth: eqChipTxt.implicitWidth + Tokens.padding.medium * 2
                            implicitHeight: 30
                            radius: Tokens.rounding.full
                            color: selected ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                            StateLayer {
                                radius: parent.radius
                                onClicked: ExtraConfig.updateModeProperty(root.editingModeId, "eqPreset", modelData.id)
                            }

                            StyledText {
                                id: eqChipTxt

                                anchors.centerIn: parent
                                text: modelData.name
                                color: selected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                font: Tokens.font.label.small
                            }
                        }
                    }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: launchCmdCol.implicitHeight + Tokens.padding.large * 2
            last: true

            ColumnLayout {
                id: launchCmdCol

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                StyledText {
                    text: "Auto-launch application or command on activation"
                    font: Tokens.font.body.small
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: Tokens.rounding.small
                        color: Colours.palette.m3surfaceContainerHighest

                        StyledTextField {
                            id: modeCmdField

                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.medium
                            verticalAlignment: TextInput.AlignVCenter
                            text: root.editingMode?.launchCmd ?? ""
                            placeholderText: "e.g. steam, code, obsidian, or custom script..."
                            onAccepted: ExtraConfig.updateModeProperty(root.editingModeId, "launchCmd", text.trim())
                        }
                    }

                    StyledRect {
                        implicitWidth: saveCmdLabel.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: 38
                        radius: Tokens.rounding.small
                        color: Colours.palette.m3primary

                        StateLayer {
                            radius: parent.radius
                            onClicked: ExtraConfig.updateModeProperty(root.editingModeId, "launchCmd", modeCmdField.text.trim())
                        }

                        StyledText {
                            id: saveCmdLabel

                            anchors.centerIn: parent
                            text: "Save"
                            color: Colours.palette.m3onPrimary
                            font: Tokens.font.label.medium
                        }
                    }
                }
            }
        }

        // Automated Routines Section (IF / THEN)
        SectionHeader {
            text: Tr.tr("Automated Routines (If / Then)")
        }

        Repeater {
            model: ExtraConfig.routines

            delegate: ConnectedRect {
                id: routineRow

                required property var modelData
                required property int index

                Layout.fillWidth: true
                implicitHeight: rLayout.implicitHeight + Tokens.padding.large * 2
                first: index === 0

                RowLayout {
                    id: rLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: 40
                        implicitHeight: 40
                        radius: Tokens.rounding.full
                        color: routineRow.modelData.enabled ? Colours.palette.m3tertiaryContainer : Colours.palette.m3surfaceContainerHighest

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: routineRow.modelData.triggerType === "time" ? "schedule" : (routineRow.modelData.triggerType === "wifi" ? "wifi" : "memory")
                            color: routineRow.modelData.enabled ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3outline
                            fontStyle: Tokens.font.icon.medium
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: routineRow.modelData.name
                            font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: `IF: ${routineRow.modelData.triggerLabel}  →  THEN: ${routineRow.modelData.actionLabel}`
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            wrapMode: Text.WordWrap
                        }
                    }

                    IconButton {
                        icon: "play_arrow"
                        type: IconButton.Text
                        padding: Tokens.padding.extraSmall
                        onClicked: ExtraConfig.executeRoutineAction(routineRow.modelData)
                    }

                    IconButton {
                        icon: "delete"
                        type: IconButton.Text
                        padding: Tokens.padding.extraSmall
                        inactiveOnColour: Colours.palette.m3error
                        onClicked: ExtraConfig.removeRoutine(routineRow.modelData.id)
                    }

                    StyledSwitch {
                        checked: Boolean(routineRow.modelData.enabled)
                        onToggled: ExtraConfig.setRoutineEnabled(routineRow.modelData.id, checked)
                    }
                }
            }
        }

        // Add New Routine Builder
        RowButton {
            last: !root.showAddRoutine
            icon: root.showAddRoutine ? "expand_less" : "add_circle"
            text: root.showAddRoutine ? "Close Routine Builder" : "Add New Routine (If / Then)"
            subtext: "Automatically switch modes or run commands based on time, running app, or Wi-Fi"
            onClicked: root.showAddRoutine = !root.showAddRoutine
        }

        ConnectedRect {
            visible: root.showAddRoutine
            Layout.fillWidth: true
            implicitHeight: builderCol.implicitHeight + Tokens.padding.large * 2
            last: true

            ColumnLayout {
                id: builderCol

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledText {
                    text: "Create Automated Routine"
                    font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3surfaceContainerHighest

                    StyledTextField {
                        id: rNameInput

                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        verticalAlignment: TextInput.AlignVCenter
                        placeholderText: "Routine name (e.g. Auto Gaming on CS2)..."
                    }
                }

                StyledText {
                    text: "1. Trigger Condition (IF):"
                    color: Colours.palette.m3primary
                    font: Tokens.font.label.medium
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: [
                            { id: "process", label: "Running App / Process", icon: "apps" },
                            { id: "time", label: "Time Schedule", icon: "schedule" },
                            { id: "wifi", label: "Wi-Fi Network", icon: "wifi" }
                        ]

                        delegate: StyledRect {
                            required property var modelData
                            readonly property bool active: root.newRoutineType === modelData.id

                            Layout.fillWidth: true
                            implicitHeight: 34
                            radius: Tokens.rounding.small
                            color: active ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest

                            StateLayer {
                                radius: parent.radius
                                onClicked: root.newRoutineType = modelData.id
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: active ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                                font: Tokens.font.label.small
                            }
                        }
                    }
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3surfaceContainerHighest

                    StyledTextField {
                        id: rTriggerInput

                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        verticalAlignment: TextInput.AlignVCenter
                        placeholderText: {
                            if (root.newRoutineType === "process")
                                return "Process names (e.g. steam|cs2|dota2 or code|zed)...";
                            if (root.newRoutineType === "time")
                                return "24h time range (e.g. 22:00-06:00 or 08:00-17:30)...";
                            return "Wi-Fi SSID name...";
                        }
                    }
                }

                StyledText {
                    text: "2. Action to Execute (THEN):"
                    color: Colours.palette.m3primary
                    font: Tokens.font.label.medium
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: [
                            { id: "mode", label: "Activate Mode" },
                            { id: "command", label: "Run Command" }
                        ]

                        delegate: StyledRect {
                            required property var modelData
                            readonly property bool active: root.newRoutineActionType === modelData.id

                            Layout.fillWidth: true
                            implicitHeight: 34
                            radius: Tokens.rounding.small
                            color: active ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest

                            StateLayer {
                                radius: parent.radius
                                onClicked: root.newRoutineActionType = modelData.id
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: active ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                                font: Tokens.font.label.small
                            }
                        }
                    }
                }

                Flow {
                    visible: root.newRoutineActionType === "mode"
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: ExtraConfig.modes

                        delegate: StyledRect {
                            required property var modelData
                            readonly property bool selected: root.newRoutineActionMode === modelData.id

                            implicitWidth: mChipTxt.implicitWidth + Tokens.padding.medium * 2
                            implicitHeight: 32
                            radius: Tokens.rounding.full
                            color: selected ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                            StateLayer {
                                radius: parent.radius
                                onClicked: root.newRoutineActionMode = modelData.id
                            }

                            StyledText {
                                id: mChipTxt

                                anchors.centerIn: parent
                                text: modelData.nameEn || modelData.name
                                color: selected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                font: Tokens.font.label.small
                            }
                        }
                    }
                }

                StyledRect {
                    visible: root.newRoutineActionType === "command"
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3surfaceContainerHighest

                    StyledTextField {
                        id: rActionCmdInput

                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        verticalAlignment: TextInput.AlignVCenter
                        placeholderText: "Command or package to run..."
                    }
                }

                StyledRect {
                    Layout.alignment: Qt.AlignRight
                    implicitWidth: addRoutineBtnTxt.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: 38
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3primary

                    StateLayer {
                        radius: parent.radius
                        onClicked: {
                            const trigVal = rTriggerInput.text.trim();
                            if (!trigVal)
                                return;
                            const trigLabel = root.newRoutineType === "process"
                                ? `App: ${trigVal}`
                                : (root.newRoutineType === "time" ? `${trigVal}` : `Wi-Fi: ${trigVal}`);

                            let actVal = "";
                            let actLabel = "";
                            if (root.newRoutineActionType === "mode") {
                                actVal = root.newRoutineActionMode;
                                const mObj = ExtraConfig.modes.find(m => m.id === actVal);
                                actLabel = mObj ? (mObj.nameEn || mObj.name) : actVal;
                            } else {
                                actVal = rActionCmdInput.text.trim();
                                if (!actVal)
                                    return;
                                actLabel = `Command: ${actVal}`;
                            }

                            ExtraConfig.addRoutine(
                                rNameInput.text.trim() || trigLabel,
                                root.newRoutineType,
                                trigVal,
                                trigLabel,
                                root.newRoutineActionType,
                                actVal,
                                actLabel
                            );
                            rNameInput.text = "";
                            rTriggerInput.text = "";
                            rActionCmdInput.text = "";
                            root.showAddRoutine = false;
                        }
                    }

                    StyledText {
                        id: addRoutineBtnTxt

                        anchors.centerIn: parent
                        text: "Save Routine"
                        color: Colours.palette.m3onPrimary
                        font: Tokens.font.label.medium
                    }
                }
            }
        }
    }
}
