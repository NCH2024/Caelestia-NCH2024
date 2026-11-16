pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.containers
import qs.services

Item {
    id: root

    property bool pinned: false
    signal close()

    function roleBg(role: string): color {
        switch (role) {
        case "user":
            return Colours.palette.m3primaryContainer;
        case "agent_a":
            return Colours.palette.m3secondaryContainer;
        case "agent_b":
            return Colours.layer(Colours.palette.m3surfaceContainerHigh, 2);
        case "question":
            return Colours.palette.m3errorContainer;
        default:
            return Colours.palette.m3tertiaryContainer;
        }
    }

    function roleFg(role: string): color {
        switch (role) {
        case "user":
            return Colours.palette.m3onPrimaryContainer;
        case "agent_a":
            return Colours.palette.m3onSecondaryContainer;
        case "agent_b":
            return Colours.palette.m3onSurface;
        case "question":
            return Colours.palette.m3onErrorContainer;
        default:
            return Colours.palette.m3onTertiaryContainer;
        }
    }

    function roleIcon(role: string): string {
        switch (role) {
        case "user":
            return "person";
        case "agent_a":
            return "supervisor_account";
        case "agent_b":
            return "smart_toy";
        case "question":
            return "help";
        default:
            return "swap_horiz";
        }
    }

    function roleName(role: string): string {
        switch (role) {
        case "user":
            return "You";
        case "agent_a":
            return "Agent A • Supervisor";
        case "agent_b":
            return "Agent B • Worker";
        case "question":
            return "Agent A • Confirmation";
        default:
            return "System";
        }
    }

    function phaseLabel(): string {
        switch (AiAutomationService.currentPhase) {
        case "planning":
            return "Agent A Planning";
        case "working":
            return "Agent B Executing";
        case "verifying":
            return "Agent A Verifying";
        case "waiting_user":
            return "Needs Your Reply";
        case "done":
            return "Completed";
        case "error":
            return "Attention";
        default:
            return "Idle";
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        // Header bar
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.extraLarge
            color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

            RowLayout {
                id: headerRow
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.large
                anchors.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.small

                StyledRect {
                    implicitWidth: 34
                    implicitHeight: 34
                    radius: Tokens.rounding.full
                    color: AiAutomationService.running ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: AiAutomationService.hasPendingQuestion ? "help" : "auto_awesome"
                        color: AiAutomationService.running ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                        fontStyle: Tokens.font.icon.medium
                        fill: 1
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    StyledText {
                        text: "AI Supervisor Monitor"
                        font: Tokens.font.title.small
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        spacing: Tokens.spacing.small

                        StyledRect {
                            implicitWidth: phaseTxt.implicitWidth + Tokens.padding.medium
                            implicitHeight: 18
                            radius: Tokens.rounding.full
                            color: AiAutomationService.hasPendingQuestion
                                ? Colours.palette.m3errorContainer
                                : (AiAutomationService.running ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest)

                            StyledText {
                                id: phaseTxt
                                anchors.centerIn: parent
                                text: root.phaseLabel()
                                font: Tokens.font.label.small
                                color: AiAutomationService.hasPendingQuestion
                                    ? Colours.palette.m3onErrorContainer
                                    : (AiAutomationService.running ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant)
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: AiAutomationService.phaseDetail || "Agent A supervises Agent B with full desktop automation."
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }
                }

                IconButton {
                    visible: AiAutomationService.currentLogPath.length > 0
                    icon: "terminal"
                    type: IconButton.Text
                    padding: Tokens.padding.extraSmall
                    onClicked: AiAutomationService.openWorkerTerminalWindow()
                }

                IconButton {
                    icon: "keep"
                    type: IconButton.Text
                    padding: Tokens.padding.extraSmall
                    label.fill: root.pinned ? 1 : 0
                    inactiveOnColour: root.pinned ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    onClicked: {
                        root.pinned = !root.pinned;
                        Quickshell.execDetached(["hyprctl", "dispatch", "pin", "title:^(AI Automation — ).*"]);
                    }
                }

                IconButton {
                    icon: "tune"
                    type: IconButton.Text
                    padding: Tokens.padding.extraSmall
                    onClicked: Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "nexus", "openPage", "14"])
                }

                IconButton {
                    visible: !AiAutomationService.running && AiAutomationService.chatMessages.length > 0
                    icon: "delete_sweep"
                    type: IconButton.Text
                    padding: Tokens.padding.extraSmall
                    onClicked: AiAutomationService.clearChat()
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
                    inactiveOnColour: Colours.palette.m3error
                    onClicked: root.close()
                }
            }
        }

        // Active Agent A <-> Agent B telemetry pill
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: telemetryRow.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.large
            color: Colours.layer(Colours.palette.m3surfaceContainerLow, 2)

            RowLayout {
                id: telemetryRow
                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                StyledText {
                    text: `A: ${AiAutomationService.activeSupervisorModel || AiAutomationService.supervisorModel}`
                    font: Tokens.font.label.small
                    color: Colours.palette.m3primary
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                StyledText {
                    text: `B: ${AiAutomationService.activeWorkerModel || AiAutomationService.workerModel}`
                    font: Tokens.font.label.small
                    color: Colours.palette.m3secondary
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                StyledText {
                    text: AiAutomationService.fullPermissions ? "Full Perms" : "Standard"
                    font: Tokens.font.label.small
                    color: AiAutomationService.fullPermissions ? Colours.palette.m3tertiary : Colours.palette.m3outline
                }
            }
        }

        // Chat Timeline
        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Tokens.rounding.extraLarge
            color: Colours.layer(Colours.palette.m3surfaceContainer, 1)

            ListView {
                id: chatList
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small
                clip: true

                model: AiAutomationService.chatMessages

                onCountChanged: Qt.callLater(() => chatList.positionViewAtEnd())

                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: chatList
                }

                header: Item {
                    width: chatList.width
                    height: AiAutomationService.chatMessages.length === 0 ? 180 : 0
                    visible: AiAutomationService.chatMessages.length === 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 32, 360)
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            Layout.alignment: Qt.AlignHCenter
                            text: "forum"
                            fontStyle: Tokens.font.icon.extraLarge
                            color: Colours.palette.m3primary
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Agent A -> Agent B Live Chat"
                            font: Tokens.font.title.small
                        }

                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: "Press SUPER + > or type a task below. Agent A plans & opens a live terminal for Agent B, then verifies every result against your request."
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }

                footer: Item {
                    width: chatList.width
                    height: liveBox.visible ? liveBox.implicitHeight + Tokens.spacing.small : 0

                    StyledRect {
                        id: liveBox
                        visible: AiAutomationService.running && (AiAutomationService.streamingWorkerText.length > 0 || AiAutomationService.currentPhase === "working")
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: Tokens.spacing.extraSmall
                        implicitHeight: liveCol.implicitHeight + Tokens.padding.medium * 2
                        radius: Tokens.rounding.large
                        color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

                        onImplicitHeightChanged: Qt.callLater(() => chatList.positionViewAtEnd())

                        ColumnLayout {
                            id: liveCol
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.extraSmall

                            RowLayout {
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    text: "smart_toy"
                                    fontStyle: Tokens.font.icon.small
                                    color: Colours.palette.m3primary
                                    fill: 1
                                }

                                StyledText {
                                    text: `Agent B • Working live (${AiAutomationService.streamingWorkerModel || AiAutomationService.workerModel})`
                                    font: Tokens.font.label.medium
                                    color: Colours.palette.m3primary
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: AiAutomationService.streamingWorkerText || "Executing actions & streaming output..."
                                wrapMode: Text.WordWrap
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }
                    }
                }

                delegate: Item {
                    id: msgWrap
                    required property var modelData
                    required property int index

                    readonly property bool isUser: modelData.role === "user"
                    readonly property bool isSystem: modelData.role === "system"

                    width: chatList.width
                    implicitHeight: bubble.implicitHeight

                    StyledRect {
                        id: bubble

                        width: msgWrap.isSystem ? parent.width : Math.min(parent.width * 0.9, parent.width - 28)
                        anchors.right: msgWrap.isUser ? parent.right : undefined
                        anchors.left: msgWrap.isUser ? undefined : parent.left
                        implicitHeight: bubbleCol.implicitHeight + Tokens.padding.medium * 2
                        radius: Tokens.rounding.large
                        color: root.roleBg(msgWrap.modelData.role)

                        ColumnLayout {
                            id: bubbleCol
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.extraSmall

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    text: root.roleIcon(msgWrap.modelData.role)
                                    fontStyle: Tokens.font.icon.small
                                    color: root.roleFg(msgWrap.modelData.role)
                                    fill: 1
                                }

                                StyledText {
                                    text: `${root.roleName(msgWrap.modelData.role)} • ${msgWrap.modelData.title}`
                                    font: Tokens.font.label.medium
                                    color: root.roleFg(msgWrap.modelData.role)
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    visible: Boolean(msgWrap.modelData.model)
                                    text: msgWrap.modelData.model
                                    font: Tokens.font.label.small
                                    color: Qt.alpha(root.roleFg(msgWrap.modelData.role), 0.75)
                                }

                                StyledText {
                                    text: msgWrap.modelData.ts
                                    font: Tokens.font.label.small
                                    color: Qt.alpha(root.roleFg(msgWrap.modelData.role), 0.65)
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: msgWrap.modelData.text
                                wrapMode: Text.WordWrap
                                font: Tokens.font.body.small
                                color: root.roleFg(msgWrap.modelData.role)
                            }
                        }
                    }
                }
            }
        }

        // Interactive Agent A confirmation actions
        StyledRect {
            visible: AiAutomationService.hasPendingQuestion
            Layout.fillWidth: true
            implicitHeight: confirmCol.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.extraLarge
            color: Colours.palette.m3errorContainer

            ColumnLayout {
                id: confirmCol
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                RowLayout {
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "warning"
                        color: Colours.palette.m3onErrorContainer
                        fontStyle: Tokens.font.icon.medium
                        fill: 1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "Agent A paused because Agent B's result needs confirmation. Reply below or choose an action:"
                        font: Tokens.font.label.medium
                        color: Colours.palette.m3onErrorContainer
                        wrapMode: Text.WordWrap
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    IconTextButton {
                        icon: "refresh"
                        text: "Retry Agent B"
                        type: IconTextButton.Filled
                        onClicked: {
                            const txt = promptInput.text.trim();
                            promptInput.text = "";
                            AiAutomationService.sendReply("retry", txt);
                        }
                    }

                    IconTextButton {
                        icon: "check"
                        text: "Accept Result"
                        type: IconTextButton.Tonal
                        onClicked: AiAutomationService.sendReply("accept", "")
                    }

                    IconTextButton {
                        icon: "close"
                        text: "Abort"
                        type: IconTextButton.Text
                        onClicked: AiAutomationService.sendReply("abort", "")
                    }
                }
            }
        }

        // Bottom task/reply input
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: Math.max(48, inputRow.implicitHeight + Tokens.padding.small * 2)
            radius: Tokens.rounding.extraLarge
            color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

            RowLayout {
                id: inputRow
                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                anchors.leftMargin: Tokens.padding.large
                spacing: Tokens.spacing.small

                TextInput {
                    id: promptInput
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    color: Colours.palette.m3onSurface
                    font.family: Tokens.font.body.medium.family
                    font.pixelSize: Tokens.font.body.medium.pixelSize
                    selectByMouse: true
                    clip: true

                    onAccepted: {
                        const txt = promptInput.text.trim();
                        if (!txt)
                            return;
                        promptInput.text = "";
                        AiAutomationService.runTask(txt);
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !promptInput.text
                        text: AiAutomationService.hasPendingQuestion
                            ? "Type guidance for Agent A / Agent B and press Enter..."
                            : "Type an AI automation task (e.g. Open Firefox and check Arch Wiki)..."
                        color: Colours.palette.m3outline
                        font: Tokens.font.body.small
                    }
                }

                IconButton {
                    icon: "send"
                    type: IconButton.Filled
                    enabled: promptInput.text.trim().length > 0 && (!AiAutomationService.running || AiAutomationService.hasPendingQuestion)
                    onClicked: {
                        const txt = promptInput.text.trim();
                        if (!txt)
                            return;
                        promptInput.text = "";
                        AiAutomationService.runTask(txt);
                    }
                }
            }
        }
    }
}
