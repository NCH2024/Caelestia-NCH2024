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

        WlrLayershell.namespace: "caelestia-ai-cursor"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Strictly 100% click-through overlay so all clicks pass cleanly to apps
        mask: Region {}

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        color: "transparent"
        visible: AiAutomationService.showGhostCursor && cursorModel.count > 0

        ListModel {
            id: cursorModel
        }

        Connections {
            target: AiAutomationService

            function onCursorUpdated(cursorId: string, x: real, y: real, action: string, label: string, colorHex: string, clicked: bool): void {
                let idx = -1;
                for (let i = 0; i < cursorModel.count; i++) {
                    if (cursorModel.get(i).cid === cursorId) {
                        idx = i;
                        break;
                    }
                }
                if (idx >= 0) {
                    const prev = cursorModel.get(idx);
                    cursorModel.set(idx, {
                        cid: cursorId,
                        tx: x,
                        ty: y,
                        action: action,
                        label: label,
                        colorHex: colorHex,
                        pulseTick: clicked ? (prev.pulseTick + 1) : prev.pulseTick
                    });
                } else {
                    if (cursorModel.count >= 4)
                        cursorModel.remove(0);
                    cursorModel.append({
                        cid: cursorId,
                        tx: x,
                        ty: y,
                        action: action,
                        label: label,
                        colorHex: colorHex,
                        pulseTick: clicked ? 1 : 0
                    });
                }
            }

            function onCursorExpired(cursorId: string): void {
                for (let i = 0; i < cursorModel.count; i++) {
                    if (cursorModel.get(i).cid === cursorId) {
                        cursorModel.remove(i);
                        break;
                    }
                }
            }
        }

        Item {
            id: stage
            anchors.fill: parent

            Repeater {
                model: cursorModel

                delegate: Item {
                    id: cursorRoot
                    required property string cid
                    required property real tx
                    required property real ty
                    required property string action
                    required property string label
                    required property string colorHex
                    required property int pulseTick

                    readonly property color accent: colorHex || Colours.palette.m3primary
                    readonly property real clampedX: Math.max(4, Math.min(stage.width - 24, tx))
                    readonly property real clampedY: Math.max(4, Math.min(stage.height - 24, ty))

                    anchors.fill: parent

                    // Expanding click ripple ring
                    StyledRect {
                        id: ripple
                        x: cursorGroup.x - width / 2
                        y: cursorGroup.y - height / 2
                        width: 60 * rippleScale
                        height: 60 * rippleScale
                        radius: width / 2
                        color: "transparent"
                        border.width: 2.5
                        border.color: cursorRoot.accent
                        opacity: rippleAlpha

                        property real rippleScale: 0.2
                        property real rippleAlpha: 0.0

                        Connections {
                            target: cursorRoot
                            function onPulseTickChanged(): void {
                                if (cursorRoot.pulseTick > 0)
                                    rippleAnim.restart();
                            }
                        }

                        ParallelAnimation {
                            id: rippleAnim
                            NumberAnimation {
                                target: ripple
                                property: "rippleScale"
                                from: 0.2
                                to: 1.55
                                duration: 480
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
                                    duration: 400
                                    easing.type: Easing.OutQuad
                                }
                            }
                        }
                    }

                    // Glowing aura trailing cursor
                    StyledRect {
                        x: cursorGroup.x - 14
                        y: cursorGroup.y - 14
                        width: 34
                        height: 34
                        radius: 17
                        color: Qt.alpha(cursorRoot.accent, 0.24)
                        border.width: 1
                        border.color: Qt.alpha(cursorRoot.accent, 0.6)
                    }

                    // Smooth 120Hz interpolated pointer + floating label pill
                    Item {
                        id: cursorGroup
                        x: cursorRoot.clampedX
                        y: cursorRoot.clampedY

                        Behavior on x {
                            NumberAnimation {
                                duration: 190
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on y {
                            NumberAnimation {
                                duration: 190
                                easing.type: Easing.OutCubic
                            }
                        }

                        Canvas {
                            id: arrowCanvas
                            x: -2
                            y: -2
                            width: 26
                            height: 26

                            property color fillCol: cursorRoot.accent
                            onFillColChanged: requestPaint()
                            Component.onCompleted: requestPaint()

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
                                ctx.fillStyle = fillCol;
                                ctx.fill();
                                ctx.lineWidth = 1.6;
                                ctx.strokeStyle = "#0F172A";
                                ctx.stroke();
                            }
                        }

                        StyledRect {
                            x: (cursorGroup.x + implicitWidth + 24 > stage.width) ? (-implicitWidth - 8) : 20
                            y: (cursorGroup.y + implicitHeight + 24 > stage.height) ? (-implicitHeight - 6) : 18
                            implicitWidth: badgeRow.implicitWidth + Tokens.padding.medium * 2
                            implicitHeight: badgeRow.implicitHeight + Tokens.padding.small * 2
                            radius: Tokens.rounding.full
                            color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.94)
                            border.width: 1.2
                            border.color: Qt.alpha(cursorRoot.accent, 0.7)

                            RowLayout {
                                id: badgeRow
                                anchors.centerIn: parent
                                spacing: Tokens.spacing.extraSmall

                                MaterialIcon {
                                    text: {
                                        if (cursorRoot.action === "click")
                                            return "touch_app";
                                        if (cursorRoot.action === "type")
                                            return "keyboard";
                                        if (cursorRoot.action === "scroll")
                                            return "unfold_more";
                                        if (cursorRoot.action === "launch")
                                            return "rocket_launch";
                                        if (cursorRoot.action === "focus")
                                            return "center_focus_strong";
                                        if (cursorRoot.action === "scan")
                                            return "screenshot_monitor";
                                        return "auto_awesome";
                                    }
                                    fontStyle: Tokens.font.icon.small
                                    color: cursorRoot.accent
                                    fill: 1
                                }

                                StyledText {
                                    text: `${cursorRoot.cid} • ${cursorRoot.label || "Operating"}`
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3onSurface
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
