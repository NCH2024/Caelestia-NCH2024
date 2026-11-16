import QtQuick
import qs.components.effects
import qs.services

Rectangle {
    id: root

    readonly property bool liquidGlassEligible: ExtraConfig.liquidGlassActive
        && Math.max(root.width, root.height) >= 84
        && Math.min(root.width, root.height) >= 34
        && root.radius >= 10
        && root.color.a > 0.04
        && root.border.width === 0

    color: "transparent"

    Behavior on color {
        CAnim {}
    }

    Loader {
        anchors.fill: parent
        active: root.liquidGlassEligible
        asynchronous: false
        sourceComponent: LiquidGlassOverlay {
            radius: root.radius
        }
    }
}
