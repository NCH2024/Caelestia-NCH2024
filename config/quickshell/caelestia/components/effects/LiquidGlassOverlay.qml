pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

ShaderEffect {
    id: root

    property real radius: 20
    readonly property bool active: ExtraConfig.liquidGlassActive && visible && width > 4 && height > 4

    property real uTime: 0
    readonly property real uWidth: width
    readonly property real uHeight: height
    readonly property real uRadius: radius
    readonly property real uIntensity: ExtraConfig.liquidGlassIntensity
    readonly property real uAnimate: ExtraConfig.liquidGlassAnimate ? 1.0 : 0.0
    readonly property color uTint: Colours.palette.m3primary

    anchors.fill: parent
    enabled: false
    visible: ExtraConfig.liquidGlassActive
    opacity: active ? 1.0 : 0.0
    fragmentShader: Qt.resolvedUrl(`${Quickshell.shellDir}/assets/shaders/liquid_glass.frag.qsb`)

    NumberAnimation on uTime {
        from: 0
        to: 62.831853
        duration: 36000
        loops: Animation.Infinite
        running: root.active && ExtraConfig.liquidGlassAnimate
    }
}
