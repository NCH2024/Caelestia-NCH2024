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
        implicitHeight: 96

        color: "transparent"

        readonly property string st: AiAutomationService.voiceState
        readonly property bool isActive: st === "listening" || st === "thinking" || st === "speaking" || st === "error"
        visible: isActive || pill.opacity > 0.02

        readonly property color badgeColor: {
            if (st === "listening")
                return "#06B6D4"; // Bright Cyan - Listening
            if (st === "thinking")
                return "#8B5CF6"; // Violet - Recognizing / Executing
            if (st === "speaking")
                return "#10B981"; // Emerald - Speaking reply
            if (st === "error")
                return "#EF4444"; // Red - Missed speech
            return Colours.palette.m3primary;
        }

        readonly property string titleText: {
            if (st === "listening")
                return AiAutomationService.trChat("Mi Mi đã thức — Đang nghe lệnh...", "Mi Mi Awake — Listening...");
            if (st === "thinking")
                return AiAutomationService.trChat("Đang nhận diện giọng nói...", "Understanding Command...");
            if (st === "speaking")
                return AiAutomationService.trChat("Mi Mi đang trả lời...", "Mi Mi Speaking...");
            if (st === "error")
                return AiAutomationService.trChat("Chưa nghe rõ — Hãy gọi lại 'Mi Mi'", "Didn't catch that — Say 'Mi Mi'");
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
            y: win.isActive ? 18 : -64
            opacity: win.isActive ? 1.0 : 0.0
            width: Math.min(540, Math.max(290, contentRow.implicitWidth + 36))
            height: 54
            radius: 27
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

            RowLayout {
                id: contentRow
                anchors.centerIn: parent
                spacing: 12

                Item {
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
                    spacing: 1
                    Layout.maximumWidth: 440

                    StyledText {
                        text: win.titleText
                        font: Tokens.font.label.large
                        color: Colours.palette.m3onSurface
                        elide: Text.ElideRight
                    }

                    StyledText {
                        visible: AiAutomationService.voiceStatusText.length > 0 && win.st !== "listening"
                        text: AiAutomationService.voiceStatusText
                        font: Tokens.font.label.small
                        color: win.badgeColor
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
