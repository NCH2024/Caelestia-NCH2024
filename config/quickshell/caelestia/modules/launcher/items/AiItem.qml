import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property var list
    readonly property string rawText: list.search.text
    readonly property string prefix: `${GlobalConfig.launcher.actionPrefix}ai`
    readonly property string prompt: rawText.startsWith(`${prefix} `)
        ? rawText.slice(`${prefix} `.length).trim()
        : (rawText.startsWith(prefix) ? rawText.slice(prefix.length).trim() : "")

    function onClicked(): void {
        root.list.screenState.launcher = false;
        if (root.prompt.length > 0) {
            AiAutomationService.runTask(root.prompt);
        } else {
            Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "ai", "openMonitor"]);
        }
    }

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: root.onClicked()
    }

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Tokens.padding.medium

        spacing: Tokens.spacing.medium

        StyledRect {
            implicitWidth: 36
            implicitHeight: 36
            radius: Tokens.rounding.full
            color: Colours.palette.m3primaryContainer
            Layout.alignment: Qt.AlignVCenter

            MaterialIcon {
                anchors.centerIn: parent
                text: "auto_awesome"
                fontStyle: Tokens.font.icon.medium
                color: Colours.palette.m3onPrimaryContainer
                fill: 1
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1

            StyledText {
                Layout.fillWidth: true
                text: root.prompt.length > 0 ? `Run AI Task: ${root.prompt}` : "Type a task after >ai and press Enter"
                color: root.prompt.length > 0 ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: `Agent A (${AiAutomationService.supervisorModel}) -> Agent B (${AiAutomationService.workerModel})${AiAutomationService.autoSwitchOnQuota ? " • Auto-Failover" : ""}`
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }

        StyledRect {
            color: Colours.palette.m3primary
            radius: Tokens.rounding.large
            clip: true

            implicitWidth: badgeRow.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: badgeRow.implicitHeight + Tokens.padding.small

            Layout.alignment: Qt.AlignVCenter

            RowLayout {
                id: badgeRow
                anchors.centerIn: parent
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    text: root.prompt.length > 0 ? "Execute" : "Monitor"
                    color: Colours.palette.m3onPrimary
                    font: Tokens.font.label.medium
                }

                MaterialIcon {
                    text: root.prompt.length > 0 ? "arrow_forward" : "forum"
                    color: Colours.palette.m3onPrimary
                    fontStyle: Tokens.font.icon.small
                }
            }
        }
    }
}
