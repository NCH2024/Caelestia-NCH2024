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
        case "assistant":
            return Colours.palette.m3secondaryContainer;
        case "execution":
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
        case "assistant":
            return Colours.palette.m3onSecondaryContainer;
        case "execution":
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
        case "assistant":
            return "auto_awesome";
        case "execution":
            return "memory";
        case "question":
            return "help";
        default:
            return "swap_horiz";
        }
    }

    function roleName(role: string): string {
        switch (role) {
        case "user":
            return AiAutomationService.trChat("Bạn", "You");
        case "assistant":
            return "Meow AI";
        case "execution":
            return AiAutomationService.trChat("Tiến trình thực thi", "Execution Summary");
        case "question":
            return AiAutomationService.trChat("Meow AI • Cần xác nhận", "Meow AI • Confirmation");
        default:
            return AiAutomationService.trChat("Hệ thống", "System");
        }
    }

    function phaseLabel(): string {
        switch (AiAutomationService.currentPhase) {
        case "planning":
            return AiAutomationService.trChat("Đang lập kế hoạch", "Planning");
        case "working":
            return AiAutomationService.trChat("Đang thực thi", "Running");
        case "verifying":
            return AiAutomationService.trChat("Đang kiểm chứng", "Verifying");
        case "waiting_user":
            return AiAutomationService.trChat("Chờ xác nhận", "Needs Reply");
        case "done":
            return AiAutomationService.trChat("Hoàn tất", "Done");
        case "error":
            return AiAutomationService.trChat("Cần chú ý", "Attention");
        default:
            return AiAutomationService.trChat("Sẵn sàng", "Ready");
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
                        text: "Meow AI Assistant"
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
                            text: AiAutomationService.phaseDetail || AiAutomationService.trChat(
                                "Tự động lập kế hoạch, thực thi và đối chiếu kết quả ngay tại đây.",
                                "Plans, executes, and verifies desktop & shell tasks inline."
                            )
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }
                }

                // Optional raw log viewer
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
                        Quickshell.execDetached(["hyprctl", "dispatch", "pin", "title:^(Meow AI — ).*"]);
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

        // Compact status + progress strip
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: telemetryCol.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.large
            color: Colours.layer(Colours.palette.m3surfaceContainerLow, 2)

            ColumnLayout {
                id: telemetryCol
                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.extraSmall

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    StyledText {
                        text: `${AiAutomationService.trChat("Điều phối", "Planner")}: ${AiAutomationService.activeSupervisorModel || AiAutomationService.supervisorModel}`
                        font: Tokens.font.label.small
                        color: Colours.palette.m3primary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: `${AiAutomationService.trChat("Thực thi", "Runner")}: ${AiAutomationService.activeWorkerModel || AiAutomationService.workerModel}`
                        font: Tokens.font.label.small
                        color: Colours.palette.m3secondary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: AiAutomationService.chatLanguage.toUpperCase()
                        font: Tokens.font.label.small
                        color: Colours.palette.m3tertiary
                    }
                }

                // Thin inline progress bar during execution
                StyledRect {
                    visible: AiAutomationService.running || AiAutomationService.currentPhase === "done"
                    Layout.fillWidth: true
                    implicitHeight: 4
                    radius: 2
                    color: Colours.palette.m3surfaceContainerHighest

                    StyledRect {
                        height: parent.height
                        radius: 2
                        width: parent.width * Math.max(0.06, Math.min(1.0, AiAutomationService.currentProgress / 100))
                        color: AiAutomationService.currentPhase === "done" ? Colours.palette.m3tertiary : Colours.palette.m3primary

                        Behavior on width {
                            Anim {}
                        }
                    }
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
                            text: "auto_awesome"
                            fontStyle: Tokens.font.icon.extraLarge
                            color: Colours.palette.m3primary
                            fill: 1
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: AiAutomationService.trChat("Trợ lý Tự động hóa Meow AI", "Meow AI Task Automation")
                            font: Tokens.font.title.small
                        }

                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: AiAutomationService.trChat(
                                "Nhấn SUPER + > hoặc nhập >ai <câu lệnh> từ Launcher. Tiến trình thực thi và đối chiếu kết quả sẽ hiển thị trực tiếp tại đây.",
                                "Press SUPER + > or type >ai <task> from the Launcher. Execution steps and verification render directly in this chat."
                            )
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }

                footer: Item {
                    width: chatList.width
                    height: liveBox.visible ? liveBox.implicitHeight + Tokens.spacing.small : 0

                    // Embedded Live Progress Card (replaces popup terminal window)
                    StyledRect {
                        id: liveBox
                        visible: AiAutomationService.running
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
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    text: "progress_activity"
                                    fontStyle: Tokens.font.icon.small
                                    color: Colours.palette.m3primary
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: AiAutomationService.phaseDetail || AiAutomationService.trChat("Đang xử lý tác vụ...", "Processing task...")
                                    font: Tokens.font.label.medium
                                    color: Colours.palette.m3primary
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    text: `${AiAutomationService.currentProgress}%`
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3onSurfaceVariant
                                }
                            }

                            // Recent tool execution steps inline
                            Repeater {
                                model: AiAutomationService.liveSteps.slice(-6)

                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: Tokens.spacing.small

                                    MaterialIcon {
                                        text: "terminal"
                                        fontStyle: Tokens.font.icon.small
                                        color: Colours.palette.m3secondary
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: `${modelData.ts}  ${modelData.label}`
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3onSurfaceVariant
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: AiAutomationService.streamingWorkerText.length > 0
                                text: AiAutomationService.streamingWorkerText
                                wrapMode: Text.WordWrap
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurface
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

        // Interactive Confirmation Card
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
                        text: AiAutomationService.trChat(
                            "Kết quả chưa khớp hoặc cần xác nhận. Nhập phản hồi bên dưới hoặc chọn thao tác:",
                            "Verification flagged an issue. Type instructions below or choose an action:"
                        )
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
                        text: AiAutomationService.trChat("Thử lại", "Retry")
                        type: IconTextButton.Filled
                        onClicked: {
                            const txt = promptInput.text.trim();
                            promptInput.text = "";
                            AiAutomationService.sendReply("retry", txt);
                        }
                    }

                    IconTextButton {
                        icon: "check"
                        text: AiAutomationService.trChat("Chấp nhận", "Accept")
                        type: IconTextButton.Tonal
                        onClicked: AiAutomationService.sendReply("accept", "")
                    }

                    IconTextButton {
                        icon: "close"
                        text: AiAutomationService.trChat("Hủy bỏ", "Abort")
                        type: IconTextButton.Text
                        onClicked: AiAutomationService.sendReply("abort", "")
                    }
                }
            }
        }

        // Bottom task/reply input (TextFieldBase supports fcitx5 Vietnamese IME cleanly)
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: Math.max(48, inputRow.implicitHeight + Tokens.padding.small * 2)
            radius: Tokens.rounding.extraLarge
            color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

            RowLayout {
                id: inputRow
                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                anchors.leftMargin: Tokens.padding.medium
                spacing: Tokens.spacing.small

                TextFieldBase {
                    id: promptInput
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    background: Item {}
                    leftPadding: Tokens.padding.small
                    rightPadding: Tokens.padding.small
                    topPadding: 6
                    bottomPadding: 6
                    font: Tokens.font.body.small

                    onAccepted: {
                        const txt = promptInput.text.trim();
                        if (!txt)
                            return;
                        promptInput.text = "";
                        AiAutomationService.runTask(txt);
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Tokens.padding.small
                        visible: !promptInput.text
                        text: AiAutomationService.hasPendingQuestion
                            ? AiAutomationService.trChat("Nhập hướng dẫn sửa và nhấn Enter...", "Type guidance and press Enter...")
                            : AiAutomationService.trChat("Nhập yêu cầu mới (sẽ làm mới đoạn chat)...", "Type a new automation task (starts fresh chat)...")
                        color: Colours.palette.m3outline
                        font: Tokens.font.body.small
                    }

                    Component.onCompleted: Qt.callLater(() => promptInput.forceActiveFocus())
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
