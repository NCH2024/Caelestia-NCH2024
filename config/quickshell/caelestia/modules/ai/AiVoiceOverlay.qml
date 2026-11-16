pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.services

Variants {
    model: Screens.screens

    PanelWindow {
        id: win

        required property ShellScreen modelData
        screen: modelData

        WlrLayershell.namespace: "caelestia-ai-voice-osd"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Strictly click-through
        mask: Region {}

        anchors.top: true
        anchors.left: true
        anchors.right: true
        implicitHeight: 160

        color: "transparent"

        readonly property string st: AiAutomationService.voiceState
        readonly property bool isActive: st === "listening" || st === "thinking" || st === "speaking" || st === "error"
        visible: isActive || pill.opacity > 0.02

        readonly property color badgeColor: {
            if (st === "listening")
                return "#06B6D4";
            if (st === "thinking")
                return "#8B5CF6";
            if (st === "speaking")
                return "#10B981";
            if (st === "error")
                return "#EF4444";
            return Colours.palette.m3primary;
        }

        readonly property string titleText: {
            if (st === "listening")
                return AiAutomationService.trChat("Đang nghe lệnh giọng nói...", "Listening for Command...");
            if (st === "thinking")
                return AiAutomationService.trChat("Đang nhận diện giọng nói...", "Understanding Command...");
            if (st === "speaking")
                return AiAutomationService.trChat("Meow AI đang đọc phản hồi...", "Meow AI Speaking...");
            if (st === "error")
                return AiAutomationService.trChat("Chưa nghe rõ — Vui lòng thử lại", "Didn't catch that — Try Again");
            return "";
        }

        readonly property string iconName: {
            if (st === "listening")
                return "mic";
            if (st === "thinking")
                return "graphic_eq";
            if (st === "speaking")
                return "volume_up";
            if (st === "error")
                return "mic_off";
            return "mic";
        }

        StyledRect {
            id: pill

            anchors.horizontalCenter: parent.horizontalCenter
            y: win.isActive ? 18 : -84
            opacity: win.isActive ? 1.0 : 0.0
            clip: true
            width: Math.min(620, Math.max(320, contentCol.implicitWidth + 82))
            height: Math.max(54, contentCol.implicitHeight + 22)
            radius: Math.min(28, height / 2)
            color: Colours.tPalette.m3surfaceContainerHigh
            border.width: 2
            border.color: win.badgeColor

            Behavior on y {
                NumberAnimation {
                    duration: 240
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutQuad
                }
            }
            Behavior on height {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }

            RowLayout {
                id: contentRow
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 18
                anchors.topMargin: 10
                anchors.bottomMargin: 10
                spacing: 12

                Item {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 34
                    implicitHeight: 34

                    StyledRect {
                        id: pulseRing
                        anchors.centerIn: parent
                        width: 34
                        height: 34
                        radius: 17
                        color: win.badgeColor
                        opacity: 0.25

                        SequentialAnimation on scale {
                            running: win.st === "listening" || win.st === "speaking"
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.95; to: 1.42; duration: 680; easing.type: Easing.OutQuad }
                            NumberAnimation { from: 1.42; to: 0.95; duration: 680; easing.type: Easing.InQuad }
                        }
                    }

                    StyledRect {
                        anchors.centerIn: parent
                        width: 30
                        height: 30
                        radius: 15
                        color: win.badgeColor

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: win.iconName
                            color: "#FFFFFF"
                            fontStyle: Tokens.font.icon.small
                            fill: 1
                        }
                    }
                }

                ColumnLayout {
                    id: contentCol
                    Layout.fillWidth: true
                    Layout.maximumWidth: 520
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: win.titleText
                        font: Tokens.font.label.large
                        color: Colours.palette.m3onSurface
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: AiAutomationService.voiceStatusText.length > 0 && win.st !== "listening"
                        text: AiAutomationService.voiceStatusText
                        font: Tokens.font.label.small
                        color: win.badgeColor
                        wrapMode: Text.WordWrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
