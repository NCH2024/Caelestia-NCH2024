pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    required property ScreenState screenState
    required property var launcherWrapper

    readonly property bool active: AiAutomationService.miniHudVisible
    readonly property string latestStep: {
        const steps = AiAutomationService.liveSteps;
        if (steps && steps.length > 0)
            return steps[steps.length - 1].label || "";
        return "";
    }
    readonly property string latestSummary: {
        const msgs = AiAutomationService.chatMessages || [];
        for (let i = msgs.length - 1; i >= 0; i--) {
            if (msgs[i].role === "assistant" || msgs[i].role === "question" || msgs[i].role === "system")
                return String(msgs[i].text || "").replace(/[#*`]/g, "").trim();
        }
        return "";
    }

    property real offsetScale: active ? 0 : 1

    visible: offsetScale < 1
    implicitWidth: Math.min(540, Math.max(400, card.implicitWidth))
    implicitHeight: active ? card.implicitHeight : 0
    opacity: 1 - offsetScale
    anchors.bottomMargin: active ? (root.screenState.launcher ? Tokens.padding.medium : Tokens.padding.large) : (-card.implicitHeight - 16)

    Behavior on offsetScale {
        Anim {}
    }

    Behavior on implicitHeight {
        Anim {}
    }

    StyledRect {
        id: card

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        implicitWidth: 500
        implicitHeight: col.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.extraLarge
        color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onContainsMouseChanged: AiAutomationService.miniHudHovered = containsMouse
        }

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            anchors.leftMargin: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledRect {
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: Tokens.rounding.full
                    color: AiAutomationService.hasPendingQuestion
                        ? Colours.palette.m3errorContainer
                        : (AiAutomationService.running ? Colours.palette.m3primary : Colours.palette.m3tertiaryContainer)

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: AiAutomationService.hasPendingQuestion
                            ? "help"
                            : (AiAutomationService.running ? "progress_activity" : "check_circle")
                        fontStyle: Tokens.font.icon.medium
                        color: AiAutomationService.hasPendingQuestion
                            ? Colours.palette.m3onErrorContainer
                            : (AiAutomationService.running ? Colours.palette.m3onPrimary : Colours.palette.m3onTertiaryContainer)
                        fill: 1
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        StyledText {
                            text: "Meow AI"
                            font: Tokens.font.label.large
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: AiAutomationService.phaseDetail || root.latestStep || AiAutomationService.trChat("Đang xử lý...", "Processing...")
                            font: Tokens.font.body.small
                            color: Colours.palette.m3primary
                            elide: Text.ElideRight
                        }

                        StyledText {
                            visible: AiAutomationService.running
                            text: `${AiAutomationService.currentProgress}%`
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: Boolean(root.latestStep) && AiAutomationService.running
                        text: root.latestStep
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                IconButton {
                    icon: "open_in_new"
                    type: IconButton.Text
                    padding: Tokens.padding.extraSmall
                    onClicked: {
                        AiAutomationService.miniHudVisible = false;
                        AiAutomationService.monitorRequested();
                    }
                }

                IconButton {
                    visible: AiAutomationService.running
                    icon: "stop_circle"
                    type: IconButton.Text
                    padding: Tokens.padding.extraSmall
                    inactiveOnColour: Colours.palette.m3error
                    onClicked: AiAutomationService.stopTask()
                }

                IconButton {
                    icon: "close"
                    type: IconButton.Text
                    padding: Tokens.padding.extraSmall
                    onClicked: AiAutomationService.miniHudVisible = false
                }
            }

            // Thin live progress bar while active
            StyledRect {
                visible: AiAutomationService.running
                Layout.fillWidth: true
                implicitHeight: 3
                radius: 2
                color: Colours.palette.m3surfaceContainerHighest

                StyledRect {
                    height: parent.height
                    radius: 2
                    width: parent.width * Math.max(0.08, Math.min(1.0, AiAutomationService.currentProgress / 100))
                    color: Colours.palette.m3primary

                    Behavior on width {
                        Anim {}
                    }
                }
            }

            // Concise answer / confirmation preview when completed or asking user
            StyledText {
                Layout.fillWidth: true
                visible: !AiAutomationService.running && root.latestSummary.length > 0 || AiAutomationService.hasPendingQuestion
                text: root.latestSummary
                font: Tokens.font.body.small
                color: AiAutomationService.hasPendingQuestion ? Colours.palette.m3error : Colours.palette.m3onSurface
                maximumLineCount: 3
                elide: Text.ElideRight
                wrapMode: Text.WordWrap
            }

            // Quick inline confirmation buttons inside Mini HUD
            RowLayout {
                visible: AiAutomationService.hasPendingQuestion
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                IconTextButton {
                    icon: "refresh"
                    text: AiAutomationService.trChat("Thử lại", "Retry")
                    type: IconTextButton.Filled
                    onClicked: AiAutomationService.sendReply("retry", "")
                }

                IconTextButton {
                    icon: "check"
                    text: AiAutomationService.trChat("Chấp nhận", "Accept")
                    type: IconTextButton.Tonal
                    onClicked: AiAutomationService.sendReply("accept", "")
                }

                IconTextButton {
                    icon: "forum"
                    text: AiAutomationService.trChat("Mở Chat", "Open Chat")
                    type: IconTextButton.Text
                    onClicked: {
                        AiAutomationService.miniHudVisible = false;
                        AiAutomationService.monitorRequested();
                    }
                }
            }
        }
    }
}
