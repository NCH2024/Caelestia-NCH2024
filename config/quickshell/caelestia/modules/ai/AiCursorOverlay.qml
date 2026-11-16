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

        WlrLayershell.namespace: "caelestia-ai-cursor"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Strictly click-through overlay so desktop & browser clicks pass straight through
        mask: Region {}

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        color: "transparent"
        visible: AiAutomationService.showGhostCursor && AiAutomationService.cursorOverlayOpacity > 0.01

        Item {
            id: stage
            anchors.fill: parent
            opacity: AiAutomationService.cursorOverlayOpacity

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            // Click ripple ring at target position
            StyledRect {
                id: ripple
                x: AiAutomationService.cursorX - width / 2
                y: AiAutomationService.cursorY - height / 2
                width: 56 * rippleScale
                height: 56 * rippleScale
                radius: width / 2
                color: "transparent"
                border.width: 2.5
                border.color: Colours.palette.m3primary
                opacity: rippleAlpha

                property real rippleScale: 0.2
                property real rippleAlpha: 0.0

                Connections {
                    target: AiAutomationService
                    function onCursorPulseTriggered(): void {
                        rippleAnim.restart();
                    }
                }

                ParallelAnimation {
                    id: rippleAnim
                    NumberAnimation {
                        target: ripple
                        property: "rippleScale"
                        from: 0.2
                        to: 1.5
                        duration: 460
                        easing.type: Easing.OutCubic
                    }
                    SequentialAnimation {
                        NumberAnimation {
                            target: ripple
                            property: "rippleAlpha"
                            from: 0.95
                            to: 0.95
                            duration: 80
                        }
                        NumberAnimation {
                            target: ripple
                            property: "rippleAlpha"
                            to: 0.0
                            duration: 380
                            easing.type: Easing.OutQuad
                        }
                    }
                }
            }

            // Soft glowing aura trailing the cursor
            StyledRect {
                x: cursorGroup.x - 14
                y: cursorGroup.y - 14
                width: 34
                height: 34
                radius: 17
                color: Qt.alpha(Colours.palette.m3primary, 0.24)
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3primary, 0.55)
            }

            // 120Hz smooth-interpolated AI Ghost Cursor + floating action badge
            Item {
                id: cursorGroup

                x: Math.max(4, Math.min(stage.width - 24, AiAutomationService.cursorX))
                y: Math.max(4, Math.min(stage.height - 24, AiAutomationService.cursorY))

                Behavior on x {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on y {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }

                // Crisp vector pointer badge
                Canvas {
                    id: arrowCanvas
                    x: -2
                    y: -2
                    width: 26
                    height: 26
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.beginPath();
                        ctx.moveTo(3, 2);
                        ctx.lineTo(3, 21);
                        ctx.lineTo(8.5, 16);
                        ctx.lineTo(13, 24);
                        ctx.lineTo(16, 22.5);
                        ctx.lineTo(11.5, 14.5);
                        ctx.lineTo(19, 14);
                        ctx.closePath();
                        ctx.fillStyle = Colours.palette.m3primary;
                        ctx.fill();
                        ctx.lineWidth = 1.6;
                        ctx.strokeStyle = Colours.palette.m3onPrimary;
                        ctx.stroke();
                    }

                    Connections {
                        target: Colours.palette
                        function onM3primaryChanged(): void {
                            arrowCanvas.requestPaint();
                        }
                    }
                }

                // Floating live status badge right below cursor tip
                StyledRect {
                    x: (cursorGroup.x + implicitWidth + 24 > stage.width) ? (-implicitWidth - 8) : 20
                    y: (cursorGroup.y + implicitHeight + 24 > stage.height) ? (-implicitHeight - 6) : 18
                    implicitWidth: badgeRow.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: badgeRow.implicitHeight + Tokens.padding.small * 2
                    radius: Tokens.rounding.full
                    color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.92)
                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3primary, 0.5)

                    RowLayout {
                        id: badgeRow
                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: {
                                if (AiAutomationService.cursorAction === "click")
                                    return "touch_app";
                                if (AiAutomationService.cursorAction === "type")
                                    return "keyboard";
                                if (AiAutomationService.cursorAction === "scroll")
                                    return "unfold_more";
                                if (AiAutomationService.cursorAction === "launch")
                                    return "rocket_launch";
                                if (AiAutomationService.cursorAction === "focus")
                                    return "center_focus_strong";
                                if (AiAutomationService.cursorAction === "scan")
                                    return "screenshot_monitor";
                                return "auto_awesome";
                            }
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3primary
                            fill: 1
                        }

                        StyledText {
                            text: `Meow AI • ${AiAutomationService.cursorLabel || "Operating"}`
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurface
                        }
                    }
                }
            }
        }
    }
}
