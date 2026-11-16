pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services
import qs.utils
import qs.modules.nexus

Item {
    id: root

    required property Item bar
    required property Brightness.Monitor monitor
    property color colour: Colours.palette.m3primary

    readonly property string shortAppName: {
        const cls = Hypr.activeToplevel?.lastIpcObject.class ?? "";
        const title = Hypr.activeToplevel?.title ?? "";
        if (!cls && !title)
            return "Desktop";
        if (title.startsWith("Nexus —"))
            return "Settings";
        if (cls) {
            const parts = cls.split(".");
            const last = parts[parts.length - 1];
            if (last.toLowerCase() === "quickshell")
                return "Shell";
            return last.length > 9 ? last.slice(0, 8) + "…" : last;
        }
        return title.length > 9 ? title.slice(0, 8) + "…" : title;
    }

    readonly property string windowTitle: {
        if (ExtraConfig.barCompactWindow)
            return root.shortAppName;
        const title = Hypr.activeToplevel?.title;
        if (!title)
            return Tr.trCtx("Desktop", "shown when no window is focused");
        if (Config.bar.activeWindow.compact) {
            const parts = title.split(/\s+[\-\u2013\u2014]\s+/);
            if (parts.length > 1)
                return parts[parts.length - 1].trim();
        }
        return title;
    }

    readonly property int maxHeight: {
        if (ExtraConfig.barCompactWindow)
            return 84;
        const otherModules = bar.children.filter(c => c.entryId && c.item !== this && c.entryId !== "spacer");
        const otherHeight = otherModules.reduce((acc, curr) => acc + (curr.item.nonAnimHeight ?? curr.height), 0);
        return Math.max(80, bar.height - otherHeight - bar.spacing * (bar.children.length - 1) - bar.vPadding * 2);
    }

    implicitWidth: mainCol.implicitWidth
    implicitHeight: mainCol.implicitHeight

    TextMetrics {
        id: titleMetrics

        text: root.windowTitle
        font: root.Tokens.font.label.small
        elide: Qt.ElideRight
        elideWidth: Math.max(36, root.maxHeight - 24)
    }

    ColumnLayout {
        id: mainCol

        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Tokens.spacing.small

        // 1. Compact Active Window Badge
        StyledRect {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 28
            implicitHeight: winCol.implicitHeight + 14
            radius: Tokens.rounding.full
            color: Colours.tPalette.m3surfaceContainer
            clip: true

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: {
                    const popouts = root.bar.popouts;
                    if (popouts.hasCurrent && popouts.currentName === "activewindow") {
                        popouts.hasCurrent = false;
                    } else {
                        popouts.currentName = "activewindow";
                        popouts.currentCenter = root.mapToItem(root.bar, 0, parent.height / 2).y;
                        popouts.hasCurrent = true;
                    }
                }
            }

            ColumnLayout {
                id: winCol

                anchors.centerIn: parent
                spacing: 4

                MaterialIcon {
                    id: icon

                    Layout.alignment: Qt.AlignHCenter
                    animate: true
                    text: Icons.getAppCategoryIcon(Hypr.activeToplevel?.lastIpcObject.class, "desktop_windows")
                    color: root.colour
                    fontStyle: Tokens.font.icon.small
                }

                Item {
                    visible: !ExtraConfig.barIconOnlyWindow
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: rotatedLabel.implicitHeight
                    implicitHeight: rotatedLabel.implicitWidth
                    clip: true

                    StyledText {
                        id: rotatedLabel

                        anchors.centerIn: parent
                        text: titleMetrics.elidedText
                        font: root.Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                        rotation: root.Config.bar.activeWindow.inverted ? 270 : 90
                    }
                }
            }
        }

        // 2. Smart Quick Pill: Modes & Routines + Device Care + Equalizer
        StyledRect {
            visible: ExtraConfig.barShowModesBtn || ExtraConfig.barShowCareBtn || ExtraConfig.barShowEqBtn
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 28
            implicitHeight: smartCol.implicitHeight + 12
            radius: Tokens.rounding.full
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: smartCol

                anchors.centerIn: parent
                spacing: 8

                // Modes & Routines Quick Button
                StyledRect {
                    visible: ExtraConfig.barShowModesBtn
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 22
                    implicitHeight: 22
                    radius: 11
                    color: ExtraConfig.activeModeId !== "standard" ? Colours.palette.m3primary : "transparent"

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: ExtraConfig.activeModeIcon
                        color: ExtraConfig.activeModeId !== "standard" ? Colours.palette.m3onPrimary : Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.small
                        fill: ExtraConfig.activeModeId !== "standard" ? 1 : 0
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                ExtraConfig.cycleMode();
                            } else {
                                WindowFactory.create(null, { initialPageIdx: 0 });
                            }
                        }
                    }
                }

                // Device Care / Power & Thermal Quick Button
                StyledRect {
                    visible: ExtraConfig.barShowCareBtn
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 22
                    implicitHeight: 22
                    radius: 11
                    color: (GameMode.enabled || ExtraConfig.powerProfileId === "performance") ? Colours.palette.m3tertiary : "transparent"

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: OptimizerService.optimizingNow ? "autorenew" : "shield_with_heart"
                        color: (GameMode.enabled || OptimizerService.powerProfileId === "performance") ? Colours.palette.m3onTertiary : Colours.palette.m3secondary
                        fontStyle: Tokens.font.icon.small
                        fill: 1
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                OptimizerService.runDeepOptimize();
                            } else {
                                WindowFactory.create(null, { initialPageIdx: 1 });
                            }
                        }
                    }
                }

                // Studio Equalizer Quick Button
                StyledRect {
                    visible: ExtraConfig.barShowEqBtn
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 22
                    implicitHeight: 22
                    radius: 11
                    color: EqualizerService.enabled ? Colours.palette.m3primaryContainer : "transparent"

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "equalizer"
                        color: EqualizerService.enabled ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                EqualizerService.enabled = !EqualizerService.enabled;
                                EqualizerService.scheduleApply();
                            } else {
                                WindowFactory.create(null, { initialPageIdx: 5 });
                            }
                        }
                    }
                }
            }
        }
    }
}
