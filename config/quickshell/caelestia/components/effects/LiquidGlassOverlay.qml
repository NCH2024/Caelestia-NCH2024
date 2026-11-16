pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

ShaderEffect {
    id: root

    property real radius: 16
    readonly property real uWidth: width
    readonly property real uHeight: height
    readonly property real uRadius: radius
    readonly property real uIntensity: ExtraConfig.liquidGlassIntensity
    readonly property real uIsLight: Colours.light ? 1.0 : 0.0
    readonly property color uTint: Colours.palette.m3primary

    anchors.fill: parent
    enabled: false
    z: 99
    fragmentShader: Qt.resolvedUrl(`${Quickshell.shellDir}/assets/shaders/liquid_glass.frag.qsb`)
}
