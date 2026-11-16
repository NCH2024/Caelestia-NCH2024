pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus

Item {
    id: root

    required property ScreenState screenState

    readonly property color healthAccent: OptimizerService.healthScore >= 90 ? Colours.palette.m3primary : (OptimizerService.healthScore >= 75 ? Colours.palette.m3secondary : Colours.palette.m3error)
    readonly property int maxTemp: Math.max(OptimizerService.cpuTemp, OptimizerService.gpuTemp)

    function friendlyProcessName(raw: string): string {
        const s = String(raw || "").trim();
        if (s === "qs")
            return "Desktop Shell";
        if (s.indexOf("Isolated Web Co") >= 0 || s === "Web Content" || s === "WebExtensions")
            return "Browser Tab";
        if (s === "firefox")
            return "Firefox Browser";
        if (s === "agy" || s === "antigravity")
            return "Antigravity IDE";
        if (s === "Hyprland")
            return "Window Compositor";
        return s.charAt(0).toUpperCase() + s.slice(1);
    }

    implicitWidth: Math.max(840, layout.implicitWidth)
    implicitHeight: layout.implicitHeight

    Component.onCompleted: OptimizerService.refreshTelemetry()

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacing.medium

        // ---- TOP ROW: Simple Health Overview + 1-Tap PC Mode ----
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            // 1. PC Health & One-Click Boost Card
            StyledRect {
                Layout.fillWidth: true
                Layout.preferredWidth: 424
                Layout.fillHeight: true
                implicitHeight: boostCol.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.extraLarge
                color: Colours.tPalette.m3surfaceContainer
                clip: true

                ColumnLayout {
                    id: boostCol

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.large

                        // Health Ring with comfortable inner padding so text never touches arc
                        CircularProgress {
                            implicitSize: healthRingCol.implicitHeight + thickness + Tokens.padding.large * 2
                            startAngle: -225
                            sweepAngle: 270
                            strokeWidth: 7
                            fgColour: root.healthAccent
                            value: OptimizerService.healthScore / 100.0

                            Behavior on clampedVal {
                                Anim {}
                            }

                            ColumnLayout {
                                id: healthRingCol

                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: 2
                                spacing: -2

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: `${OptimizerService.healthScore}`
                                    font: Tokens.font.title.builders.large.weight(Font.Bold).build()
                                    color: root.healthAccent
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: OptimizerService.healthLabel
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3onSurfaceVariant
                                }
                            }
                        }

                        // Plain-English System Summary
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true

                                StyledText {
                                    Layout.fillWidth: true
                                    text: OptimizerService.healthScore >= 90 ? "Your PC is Healthy" : (OptimizerService.healthScore >= 75 ? "Running Well" : "Cleanup Recommended")
                                    font: Tokens.font.title.medium
                                    color: Colours.palette.m3onSurface
                                    elide: Text.ElideRight
                                }

                                StyledRect {
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    radius: 14
                                    color: Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)

                                    StateLayer {
                                        radius: parent.radius
                                        onClicked: OptimizerService.refreshTelemetry()
                                    }

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        text: "refresh"
                                        fontStyle: Tokens.font.icon.small
                                        color: Colours.palette.m3onSurfaceVariant
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: `RAM: ${OptimizerService.ramFreeText} (${OptimizerService.ramPct}% used)`
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurfaceVariant
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: `Storage: ${OptimizerService.rootDiskPct}% full on main drive`
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurfaceVariant
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: OptimizerService.lastOptimizedTime.length > 0
                                    ? `Last boosted at ${OptimizerService.lastOptimizedTime}`
                                    : "Frees unused RAM & temporary files safely"
                                font: Tokens.font.label.small
                                color: Colours.palette.m3outline
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // Progress bar shown cleanly during optimization
                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 6
                        radius: 3
                        visible: OptimizerService.optimizingNow
                        color: Colours.palette.m3surfaceContainerHighest
                        clip: true

                        StyledRect {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * Math.max(0.06, OptimizerService.optimizeProgress)
                            radius: 3
                            color: Colours.palette.m3primary

                            Behavior on width {
                                Anim {}
                            }
                        }
                    }

                    // Main Action Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        StyledText {
                            Layout.fillWidth: true
                            text: OptimizerService.optimizingNow ? OptimizerService.optimizeStageText : OptimizerService.optimizeStatusText
                            font: Tokens.font.body.small
                            color: OptimizerService.optimizingNow ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            elide: Text.ElideRight
                        }

                        StyledRect {
                            implicitWidth: boostBtnRow.implicitWidth + Tokens.padding.extraLarge * 2
                            implicitHeight: 38
                            radius: 19
                            color: OptimizerService.optimizingNow ? Colours.palette.m3surfaceContainerHighest : Colours.palette.m3primary

                            StateLayer {
                                radius: parent.radius
                                disabled: OptimizerService.optimizingNow
                                color: Colours.palette.m3onPrimary
                                onClicked: OptimizerService.runDeepOptimize()
                            }

                            RowLayout {
                                id: boostBtnRow

                                anchors.centerIn: parent
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    text: OptimizerService.optimizingNow ? "autorenew" : "rocket_launch"
                                    fontStyle: Tokens.font.icon.small
                                    color: OptimizerService.optimizingNow ? Colours.palette.m3primary : Colours.palette.m3onPrimary
                                    fill: 1
                                }

                                StyledText {
                                    text: OptimizerService.optimizingNow ? "Boosting..." : "Boost & Clean Now"
                                    font: Tokens.font.label.large
                                    color: OptimizerService.optimizingNow ? Colours.palette.m3onSurface : Colours.palette.m3onPrimary
                                }
                            }
                        }
                    }
                }
            }

            // 2. Smart Performance Mode Card (Zero Jargon 1-Tap Presets)
            StyledRect {
                Layout.fillWidth: true
                Layout.preferredWidth: 400
                Layout.fillHeight: true
                implicitHeight: modeCol.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.extraLarge
                color: Colours.tPalette.m3surfaceContainer
                clip: true

                ColumnLayout {
                    id: modeCol

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.small

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: "speed"
                            color: Colours.palette.m3secondary
                            fontStyle: Tokens.font.icon.medium
                            fill: 1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Tr.tr("Performance Mode")
                            font: Tokens.font.title.medium
                        }

                        // Friendly Temperature Pill
                        StyledRect {
                            implicitWidth: tempPillRow.implicitWidth + 14
                            implicitHeight: 24
                            radius: 12
                            color: root.maxTemp >= 85 ? Colours.palette.m3errorContainer : Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)

                            RowLayout {
                                id: tempPillRow

                                anchors.centerIn: parent
                                spacing: 4

                                MaterialIcon {
                                    text: "device_thermostat"
                                    fontStyle: Tokens.font.icon.small
                                    color: root.maxTemp >= 85 ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSurfaceVariant
                                }

                                StyledText {
                                    text: `${OptimizerService.cpuTemp}°C`
                                    font: Tokens.font.label.small
                                    color: root.maxTemp >= 85 ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSurface
                                }
                            }
                        }
                    }

                    // 3 Intuitive Mode Tiles (automatically tunes Power, Scheduler & Cooling)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        Repeater {
                            model: [
                                { id: "saver", title: "Quiet", sub: "Save battery", icon: "battery_saver" },
                                { id: "balanced", title: "Everyday", sub: "Smooth & cool", icon: "balance" },
                                { id: "gaming", title: "Max Speed", sub: "Games & apps", icon: "bolt" }
                            ]

                            delegate: StyledRect {
                                required property var modelData
                                readonly property bool active: OptimizerService.smartPresetId === modelData.id

                                Layout.fillWidth: true
                                implicitHeight: presetCol.implicitHeight + Tokens.padding.medium * 2
                                radius: Tokens.rounding.large
                                color: active ? Colours.palette.m3primaryContainer : Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)

                                StateLayer {
                                    radius: parent.radius
                                    color: active ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                                    onClicked: OptimizerService.applySmartPreset(modelData.id)
                                }

                                ColumnLayout {
                                    id: presetCol

                                    anchors.centerIn: parent
                                    spacing: 2

                                    MaterialIcon {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.icon
                                        fontStyle: Tokens.font.icon.medium
                                        fill: active ? 1 : 0
                                        color: active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                    }

                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.title
                                        font: Tokens.font.label.medium
                                        color: active ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                                    }

                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.sub
                                        font: Tokens.font.label.small
                                        color: active ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3outline
                                    }
                                }
                            }
                        }
                    }

                    // Single Plain-English Max Cooling Switch
                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: coolRow.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.medium
                        color: OptimizerService.thermalProfile === "gmode" ? Colours.palette.m3tertiaryContainer : Colours.layer(Colours.palette.m3surfaceContainerHighest, 1)

                        StateLayer {
                            radius: parent.radius
                            onClicked: OptimizerService.toggleMaxCooling(OptimizerService.thermalProfile !== "gmode")
                        }

                        RowLayout {
                            id: coolRow

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                text: "mode_fan"
                                fontStyle: Tokens.font.icon.medium
                                fill: OptimizerService.thermalProfile === "gmode" ? 1 : 0
                                color: OptimizerService.thermalProfile === "gmode" ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3tertiary
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    text: "Max Fan Cooling"
                                    font: Tokens.font.label.medium
                                    color: OptimizerService.thermalProfile === "gmode" ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                                }

                                StyledText {
                                    text: OptimizerService.thermalProfile === "gmode" ? "Fans running at maximum speed" : "Automatic quiet fan control"
                                    font: Tokens.font.label.small
                                    color: OptimizerService.thermalProfile === "gmode" ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurfaceVariant
                                    elide: Text.ElideRight
                                }
                            }

                            StyledSwitch {
                                checked: OptimizerService.thermalProfile === "gmode"
                                onToggled: OptimizerService.toggleMaxCooling(checked)
                            }
                        }
                    }
                }
            }
        }

        // ---- BOTTOM ROW: Automatic Care + Heavy Apps Running ----
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            // 1. Automatic Background Care (Simple Switches)
            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: careCol.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.extraLarge
                color: Colours.tPalette.m3surfaceContainer
                clip: true

                ColumnLayout {
                    id: careCol

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.small

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: OptimizerService.protectionActive ? "verified_user" : "shield"
                            color: Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.medium
                            fill: 1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: "Automatic Care"
                            font: Tokens.font.title.small
                        }

                        StyledRect {
                            implicitWidth: protTxt.implicitWidth + 14
                            implicitHeight: 22
                            radius: 11
                            color: OptimizerService.protectionActive ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest

                            StyledText {
                                id: protTxt

                                anchors.centerIn: parent
                                text: OptimizerService.protectionActive ? "Protection On" : "Active"
                                font: Tokens.font.label.small
                                color: OptimizerService.protectionActive ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                            }
                        }
                    }

                    // Simple Smart Balanced Thermal Cooling Switch
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                text: "Cool & quiet balanced tuning"
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurface
                            }

                            StyledText {
                                text: OptimizerService.smartCoolEnabled
                                    ? (OptimizerService._autoCoolLevel > 0 ? "Gentle cooling active now" : "Reduces heat spikes automatically")
                                    : "Standard stock laptop profile"
                                font: Tokens.font.label.small
                                color: OptimizerService._autoCoolLevel > 0 ? Colours.palette.m3primary : Colours.palette.m3outline
                            }
                        }

                        StyledSwitch {
                            checked: OptimizerService.smartCoolEnabled
                            onToggled: {
                                OptimizerService.smartCoolEnabled = checked;
                                OptimizerService.save();
                                OptimizerService.setThermalMode(OptimizerService.thermalProfile);
                            }
                        }
                    }

                    // Simple Auto-Clean Memory Switch
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                text: "Auto-free memory when busy"
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurface
                            }

                            StyledText {
                                text: OptimizerService.autoRamThreshold > 0 ? `Runs automatically above ${OptimizerService.autoRamThreshold}% RAM` : "Currently manual only"
                                font: Tokens.font.label.small
                                color: Colours.palette.m3outline
                            }
                        }

                        StyledSwitch {
                            checked: OptimizerService.autoRamThreshold > 0
                            onToggled: {
                                OptimizerService.autoRamThreshold = checked ? 85 : 0;
                                OptimizerService.save();
                            }
                        }
                    }

                    // Simple Include Update Cache Cleanup Switch
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                text: "Clean old update files during Boost"
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurface
                            }

                            StyledText {
                                text: `Safely frees old installers (${OptimizerService.pacmanCacheSize} cached)`
                                font: Tokens.font.label.small
                                color: Colours.palette.m3outline
                            }
                        }

                        StyledSwitch {
                            checked: OptimizerService.cleanPacman
                            onToggled: {
                                OptimizerService.cleanPacman = checked;
                                OptimizerService.save();
                            }
                        }
                    }
                }
            }

            // 2. Heavy Apps Running + Advanced Settings Button
            StyledRect {
                Layout.preferredWidth: 320
                Layout.fillHeight: true
                implicitHeight: appsCol.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.extraLarge
                color: Colours.tPalette.m3surfaceContainer
                clip: true

                ColumnLayout {
                    id: appsCol

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.extraSmall

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: "apps"
                            color: Colours.palette.m3secondary
                            fontStyle: Tokens.font.icon.medium
                            fill: 1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: "Top Memory Apps"
                            font: Tokens.font.title.small
                        }
                    }

                    Repeater {
                        model: OptimizerService.topProcesses.slice(0, 3)

                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            StyledText {
                                Layout.fillWidth: true
                                text: root.friendlyProcessName(modelData.name)
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurface
                                elide: Text.ElideRight
                            }

                            StyledText {
                                text: `${modelData.mib} MB`
                                font: Tokens.font.label.medium
                                color: Colours.palette.m3secondary
                            }
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.spacing.extraSmall
                        implicitHeight: 32
                        radius: 16
                        color: Colours.palette.m3secondaryContainer

                        StateLayer {
                            radius: parent.radius
                            color: Colours.palette.m3onSecondaryContainer
                            onClicked: {
                                root.screenState.dashboard = false;
                                WindowFactory.create(null, {
                                    initialPageIdx: 1
                                });
                            }
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialIcon {
                                text: "tune"
                                fontStyle: Tokens.font.icon.small
                                color: Colours.palette.m3onSecondaryContainer
                            }

                            StyledText {
                                text: "Advanced Care Settings"
                                font: Tokens.font.label.medium
                                color: Colours.palette.m3onSecondaryContainer
                            }
                        }
                    }
                }
            }
        }
    }
}
