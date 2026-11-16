pragma ComponentBehavior: Bound

import "cards"
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property var props
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property matrix4x4 deformMatrix

    readonly property int enabledCards: (toggles.active ? 1 : 0) + (record.active ? 1 : 0)
    readonly property real nonAnimHeight: ((toggles.item as Toggles)?.implicitHeight ?? 0) + ((record.item as Record)?.nonAnimHeight ?? 0) + layout.spacing * Math.max(0, enabledCards - 1)

    implicitWidth: Math.max(348, layout.implicitWidth)
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Tokens.spacing.small

        Loader {
            id: toggles

            Layout.fillWidth: true
            active: Config.utilities.cards.quickToggles
            visible: active

            sourceComponent: Toggles {
                objectName: "utilitiesQuickToggles"

                screenState: root.screenState
                popouts: root.popouts
            }
        }

        Loader {
            id: record

            Layout.fillWidth: true
            active: Config.utilities.cards.recorder
            visible: active
            z: 1

            sourceComponent: Record {
                objectName: "utilitiesScreenRecorder"

                props: root.props
                screenState: root.screenState
            }
        }
    }

    RecordingDeleteModal {
        props: root.props
        deformMatrix: root.deformMatrix
    }
}
