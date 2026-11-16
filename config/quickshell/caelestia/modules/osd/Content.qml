pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root

    required property Brightness.Monitor monitor
    required property ScreenState screenState

    required property real volume
    required property bool muted
    required property real sourceVolume
    required property bool sourceMuted
    required property real brightness

    implicitWidth: Math.max(layout.implicitWidth, modeOsdCard.visible ? modeOsdCard.implicitWidth : 0) + Tokens.padding.large + layout.anchors.horizontalCenterOffset * 2
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        anchors.horizontalCenterOffset: CUtils.clamp(Tokens.padding.large - Config.border.thickness, 0, Tokens.padding.large) / 2
        spacing: Tokens.spacing.medium

        // Mode Switch Edge OSD Pill (shown when switching modes via shortcut or routine)
        StyledRect {
            id: modeOsdCard

            visible: ExtraConfig.modeOsdVisible
            Layout.alignment: Qt.AlignRight
            implicitWidth: modeOsdRow.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: modeOsdRow.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.large
            color: Colours.palette.m3primaryContainer
            clip: true

            LiquidGlassOverlay {
                radius: parent.radius
            }

            RowLayout {
                id: modeOsdRow

                anchors.centerIn: parent
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: ExtraConfig.activeModeIcon
                    color: Colours.palette.m3onPrimaryContainer
                    fontStyle: Tokens.font.icon.medium
                    fill: 1
                }

                ColumnLayout {
                    spacing: 0

                    StyledText {
                        text: ExtraConfig.activeModeName
                        color: Colours.palette.m3onPrimaryContainer
                        font: Tokens.font.label.large
                    }

                    StyledText {
                        visible: ExtraConfig.modeOsdSubtitle.length > 0
                        text: ExtraConfig.modeOsdSubtitle
                        color: Colours.palette.m3onPrimaryContainer
                        opacity: 0.8
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        // Speaker volume
        CustomMouseArea {
            function onWheel(event: WheelEvent) {
                if (event.angleDelta.y > 0)
                    Audio.incrementVolume();
                else if (event.angleDelta.y < 0)
                    Audio.decrementVolume();
            }

            implicitWidth: Tokens.sizes.osd.sliderWidth
            implicitHeight: Tokens.sizes.osd.sliderHeight

            FilledSlider {
                anchors.fill: parent

                icon: Icons.getVolumeIcon(value, root.muted)
                value: root.volume
                to: GlobalConfig.services.maxVolume
                onMoved: Audio.setVolume(value)
            }
        }

        // Microphone volume
        WrappedLoader {
            shouldBeActive: Config.osd.enableMicrophone && (!Config.osd.enableBrightness || !root.screenState.session)

            sourceComponent: CustomMouseArea {
                function onWheel(event: WheelEvent) {
                    if (event.angleDelta.y > 0)
                        Audio.incrementSourceVolume();
                    else if (event.angleDelta.y < 0)
                        Audio.decrementSourceVolume();
                }

                implicitWidth: Tokens.sizes.osd.sliderWidth
                implicitHeight: Tokens.sizes.osd.sliderHeight

                FilledSlider {
                    anchors.fill: parent

                    icon: Icons.getMicVolumeIcon(value, root.sourceMuted)
                    value: root.sourceVolume
                    to: GlobalConfig.services.maxVolume
                    onMoved: Audio.setSourceVolume(value)
                }
            }
        }

        // Brightness
        WrappedLoader {
            shouldBeActive: Config.osd.enableBrightness

            sourceComponent: CustomMouseArea {
                function onWheel(event: WheelEvent) {
                    const monitor = root.monitor;
                    if (!monitor)
                        return;
                    if (event.angleDelta.y > 0)
                        monitor.setBrightness(monitor.brightness + GlobalConfig.services.brightnessIncrement);
                    else if (event.angleDelta.y < 0)
                        monitor.setBrightness(monitor.brightness - GlobalConfig.services.brightnessIncrement);
                }

                implicitWidth: Tokens.sizes.osd.sliderWidth
                implicitHeight: Tokens.sizes.osd.sliderHeight

                FilledSlider {
                    anchors.fill: parent

                    icon: `brightness_${(Math.round(value * 6) + 1)}`
                    value: root.brightness
                    onMoved: root.monitor?.setBrightness(value)
                }
            }
        }
    }

    component WrappedLoader: Loader {
        required property bool shouldBeActive

        asynchronous: true
        Layout.preferredHeight: shouldBeActive ? Tokens.sizes.osd.sliderHeight : 0
        opacity: shouldBeActive ? 1 : 0
        active: opacity > 0
        visible: active

        Behavior on Layout.preferredHeight {
            Anim {
                type: Anim.Emphasized
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
