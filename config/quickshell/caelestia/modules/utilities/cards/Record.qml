pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Components
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.components.misc
import qs.services
import qs.utils

StyledRect {
    id: root

    required property var props
    required property ScreenState screenState
    property bool showHistory: false

    readonly property real nonAnimHeight: layout.implicitHeight + layout.anchors.margins * 2

    implicitHeight: nonAnimHeight

    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer
    clip: true

    Ref {
        service: Recorder
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.small

        // Compact 1-Line Screen Recorder Bar
        RowLayout {
            id: btnLayout

            Layout.fillWidth: true
            spacing: 6

            StyledRect {
                implicitWidth: 30
                implicitHeight: 30
                radius: Tokens.rounding.full
                color: Recorder.running ? Colours.palette.m3error : Colours.palette.m3secondaryContainer

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "screen_record"
                    color: Recorder.running ? Colours.palette.m3onError : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.small
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: {
                    if (!Recorder.running)
                        return "Screen Recorder";
                    const elapsed = Recorder.elapsed;
                    const mins = Math.floor((elapsed % 3600) / 60);
                    const secs = Math.floor(elapsed % 60).toString().padStart(2, "0");
                    return `${Recorder.paused ? "PAUSED" : "REC"} ${mins}:${secs}`;
                }
                color: Recorder.running ? Colours.palette.m3error : Colours.palette.m3onSurface
                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                elide: Text.ElideRight
            }

            // Quick region / fullscreen start buttons when idle
            StyledRect {
                visible: !Recorder.running
                implicitWidth: regTxt.implicitWidth + 16
                implicitHeight: 28
                radius: Tokens.rounding.full
                color: Colours.palette.m3secondaryContainer

                StateLayer {
                    radius: parent.radius
                    onClicked: Recorder.start(["-r"])
                }

                StyledText {
                    id: regTxt

                    anchors.centerIn: parent
                    text: "Region"
                    color: Colours.palette.m3onSecondaryContainer
                    font: Tokens.font.label.small
                }
            }

            StyledRect {
                visible: !Recorder.running
                implicitWidth: fullTxt.implicitWidth + 16
                implicitHeight: 28
                radius: Tokens.rounding.full
                color: Colours.palette.m3primaryContainer

                StateLayer {
                    radius: parent.radius
                    onClicked: Recorder.start(["-s"])
                }

                StyledText {
                    id: fullTxt

                    anchors.centerIn: parent
                    text: "Fullscreen"
                    color: Colours.palette.m3onPrimaryContainer
                    font: Tokens.font.label.small
                }
            }

            // Pause & Stop buttons when recording
            IconButton {
                visible: Recorder.running
                icon: Recorder.paused ? "play_arrow" : "pause"
                type: IconButton.Tonal
                padding: 4
                onClicked: Recorder.togglePause()
            }

            IconButton {
                visible: Recorder.running
                icon: "stop"
                inactiveColour: Colours.palette.m3error
                inactiveOnColour: Colours.palette.m3onError
                padding: 4
                onClicked: Recorder.stop()
            }

            // Toggle Past Recordings List
            IconButton {
                icon: root.showHistory ? "expand_less" : "folder_special"
                type: IconButton.Text
                padding: 4
                onClicked: root.showHistory = !root.showHistory
            }
        }

        // Collapsible Recording History
        Loader {
            Layout.fillWidth: true
            active: root.showHistory
            visible: active

            sourceComponent: RecordingList {
                props: root.props
                screenState: root.screenState
            }
        }
    }
}
