pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Components
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.components.images
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> clockPositions: [
        MenuItem { text: Tr.tr("Top Left"); property string posVal: "top-left" },
        MenuItem { text: Tr.tr("Top Center"); property string posVal: "top-center" },
        MenuItem { text: Tr.tr("Top Right"); property string posVal: "top-right" },
        MenuItem { text: Tr.tr("Middle Left"); property string posVal: "middle-left" },
        MenuItem { text: Tr.tr("Middle Center"); property string posVal: "middle-center" },
        MenuItem { text: Tr.tr("Middle Right"); property string posVal: "middle-right" },
        MenuItem { text: Tr.tr("Bottom Left"); property string posVal: "bottom-left" },
        MenuItem { text: Tr.tr("Bottom Center"); property string posVal: "bottom-center" },
        MenuItem { text: Tr.tr("Bottom Right"); property string posVal: "bottom-right" }
    ]

    title: Tr.tr("Wallpaper & style")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        StyledClippingRect {
            id: wallWrapper

            Layout.alignment: Qt.AlignHCenter
            implicitWidth: {
                const screen = root.nState.screen;
                return implicitHeight / screen.height * screen.width;
            }
            implicitHeight: {
                const screen = root.nState.screen;
                const cWidth = root.cappedWidth;
                return Math.min(Math.round(cWidth * 0.4), cWidth / screen.width * screen.height);
            }

            color: Colours.tPalette.m3surfaceContainer
            radius: Tokens.rounding.large

            Loader {
                anchors.centerIn: parent
                opacity: Config.background.wallpaperEnabled ? 0 : 1
                active: opacity > 0

                sourceComponent: ColumnLayout {
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "hide_image"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.extraLarge
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Tr.tr("Wallpaper disabled")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.large
                    }
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }
            }

            Item {
                anchors.fill: parent
                opacity: Config.background.wallpaperEnabled ? 1 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }

                Loader {
                    id: wallIndicatorLoader

                    anchors.centerIn: parent

                    opacity: 0
                    active: opacity > 0

                    sourceComponent: StyledRect {
                        implicitWidth: wallLoadingIndicator.implicitSize + Tokens.padding.largeIncreased * 2
                        implicitHeight: wallLoadingIndicator.implicitSize + Tokens.padding.largeIncreased * 2

                        color: Colours.palette.m3primaryContainer
                        radius: Tokens.rounding.full

                        LoadingIndicator {
                            id: wallLoadingIndicator

                            anchors.centerIn: parent
                            containsIcon: true
                            implicitSize: Math.min(wallWrapper.implicitWidth, wallWrapper.implicitHeight) * 0.4
                        }
                    }

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                Timer {
                    id: wallLoadDebounceTimer

                    interval: 100
                    onTriggered: {
                        if (wallImg.status !== Image.Ready)
                            wallIndicatorLoader.opacity = 1;
                    }
                }

                FadeImage {
                    id: wallImg

                    anchors.fill: parent
                    source: Wallpapers.current
                    preventInit: wallIndicatorLoader.opacity > 0
                    fadeOutAnim: Anim.DefaultEffects
                    fadeInAnim: Anim.SlowEffects

                    onSourceChanged: wallLoadDebounceTimer.restart()

                    onStatusChanged: {
                        if (status === Image.Ready) {
                            wallLoadDebounceTimer.stop();
                            wallIndicatorLoader.opacity = 0;
                        }
                    }
                }
            }
        }

        ButtonRow {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.small

            IconTextButton {
                icon: "wallpaper"
                text: Tr.tr("Wallpapers")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                disabled: !Config.background.wallpaperEnabled
                onClicked: root.nState.openSubPage(1) // Wallpaper page
            }

            IconTextButton {
                icon: "palette"
                text: Tr.tr("Colours")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                onClicked: root.nState.openSubPage(3) // Colours page
            }
        }

        ToggleRow {
            first: true
            text: Tr.tr("Display wallpaper")
            checked: Config.background.wallpaperEnabled
            onToggled: GlobalConfig.background.wallpaperEnabled = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            text: Tr.tr("Transparency")
            // TRANSLATORS: %1/%2 = opacity values from 0 to 1 for the base surface and layered surfaces
            subtext: Tr.tr("Base %1, layers %2").arg(Colours.transparency.base).arg(Colours.transparency.layers)
            checked: Colours.transparency.enabled
            onToggled: GlobalConfig.appearance.transparency.enabled = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            text: Tr.tr("Dark theme")
            checked: !Colours.light
            onToggled: Colours.setMode(checked ? "dark" : "light")
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            text: Tr.tr("Liquid Glass & Water Optics")
            subtext: Tr.tr("Refractive specular glass rims, animated water caustics & deep vibrancy blur")
            checked: ExtraConfig.liquidGlassEnabled
            onToggled: ExtraConfig.setLiquidGlass(checked)
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            text: Tr.tr("Animated water caustics")
            subtext: Tr.tr("Subtle fluid light dispersion shimmering across glass surfaces")
            enabled: ExtraConfig.liquidGlassEnabled
            checked: ExtraConfig.liquidGlassAnimate
            onToggled: {
                ExtraConfig.liquidGlassAnimate = checked;
                ExtraConfig.save();
            }
        }

        SliderRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            last: true
            icon: "water_drop"
            label: Tr.tr("Optical glass intensity")
            valueLabel: `${Math.round(value * 100)}%`
            from: 0.2
            to: 1.0
            enabled: ExtraConfig.liquidGlassEnabled
            value: ExtraConfig.liquidGlassIntensity
            onMoved: v => {
                ExtraConfig.liquidGlassIntensity = Math.round(v * 100) / 100;
                ExtraConfig.save();
            }
        }

        // ---- Desktop Clock & Weather Widget ----------------------------------
        SectionHeader {
            text: Tr.tr("Desktop clock & weather")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Enable desktop clock")
            subtext: Tr.tr("Display date, time and weather widget on the desktop")
            checked: Config.background.desktopClock.enabled
            onToggled: GlobalConfig.background.desktopClock.enabled = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            text: Tr.tr("Show weather on desktop")
            subtext: Tr.tr("Display live weather alongside the desktop clock")
            checked: ExtraConfig.desktopWeatherEnabled
            enabled: Config.background.desktopClock.enabled
            onToggled: ExtraConfig.desktopWeatherEnabled = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            text: Tr.tr("Show humidity & wind details")
            subtext: Tr.tr("Include humidity and wind speed in the desktop weather widget")
            checked: ExtraConfig.desktopWeatherDetails
            enabled: Config.background.desktopClock.enabled && ExtraConfig.desktopWeatherEnabled
            onToggled: ExtraConfig.desktopWeatherDetails = checked
        }

        SelectRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            label: Tr.tr("Desktop widget position")
            subtext: Tr.tr("Anchor position on the screen")
            menuItems: root.clockPositions
            active: root.clockPositions.find(i => i.posVal === Config.background.desktopClock.position) ?? root.clockPositions[8]
            onSelected: item => GlobalConfig.background.desktopClock.position = item.posVal
        }

        StepperRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            label: Tr.tr("Desktop widget scale")
            subtext: Tr.tr("Size multiplier for the desktop clock & weather")
            value: Math.round(Config.background.desktopClock.scale * 100) / 100
            from: 0.5
            to: 2.5
            stepSize: 0.1
            onMoved: v => GlobalConfig.background.desktopClock.scale = Math.round(v * 100) / 100
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            text: Tr.tr("Clock background plate")
            subtext: Tr.tr("Draw a frosted card behind the desktop clock")
            checked: Config.background.desktopClock.background.enabled
            onToggled: GlobalConfig.background.desktopClock.background.enabled = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            last: true
            text: Tr.tr("Clock background blur")
            checked: Config.background.desktopClock.background.blur
            enabled: Config.background.desktopClock.background.enabled
            onToggled: GlobalConfig.background.desktopClock.background.blur = checked
        }

        // ---- Desktop Audio Visualiser ----------------------------------------
        SectionHeader {
            text: Tr.tr("Desktop audio visualiser")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Enable audio visualiser")
            subtext: Tr.tr("Show Cava spectrum bars on the desktop background")
            checked: Config.background.visualiser.enabled
            onToggled: GlobalConfig.background.visualiser.enabled = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            text: Tr.tr("Auto-hide when silent")
            checked: Config.background.visualiser.autoHide
            enabled: Config.background.visualiser.enabled
            onToggled: GlobalConfig.background.visualiser.autoHide = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            last: true
            text: Tr.tr("Visualiser blur effect")
            checked: Config.background.visualiser.blur
            enabled: Config.background.visualiser.enabled
            onToggled: GlobalConfig.background.visualiser.blur = checked
        }

        // ---- UI Scaling & Transparency Tuning --------------------------------
        SectionHeader {
            text: Tr.tr("UI scale & transparency tuning")
        }

        StepperRow {
            first: true
            label: Tr.tr("Font scale")
            subtext: Tr.tr("Global text size multiplier")
            value: Math.round(GlobalConfig.appearance.font.scale * 100) / 100
            from: 0.75
            to: 1.5
            stepSize: 0.05
            onMoved: v => GlobalConfig.appearance.font.scale = Math.round(v * 100) / 100
        }

        StepperRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            label: Tr.tr("Corner rounding scale")
            subtext: Tr.tr("Global border radius multiplier")
            value: Math.round(GlobalConfig.appearance.rounding.scale * 100) / 100
            from: 0.0
            to: 2.0
            stepSize: 0.1
            onMoved: v => GlobalConfig.appearance.rounding.scale = Math.round(v * 100) / 100
        }

        StepperRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            label: Tr.tr("Animation duration scale")
            subtext: Tr.tr("Lower is faster, higher is slower")
            value: Math.round(GlobalConfig.appearance.anim.durations.scale * 100) / 100
            from: 0.2
            to: 2.0
            stepSize: 0.1
            onMoved: v => GlobalConfig.appearance.anim.durations.scale = Math.round(v * 100) / 100
        }

        StepperRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            label: Tr.tr("Base surface opacity")
            subtext: Tr.tr("Opacity of main windows when transparency is enabled")
            value: Math.round(GlobalConfig.appearance.transparency.base * 100) / 100
            from: 0.3
            to: 1.0
            stepSize: 0.05
            onMoved: v => GlobalConfig.appearance.transparency.base = Math.round(v * 100) / 100
        }

        StepperRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            last: true
            label: Tr.tr("Layer surface opacity")
            subtext: Tr.tr("Opacity of cards and containers")
            value: Math.round(GlobalConfig.appearance.transparency.layers * 100) / 100
            from: 0.1
            to: 1.0
            stepSize: 0.05
            onMoved: v => GlobalConfig.appearance.transparency.layers = Math.round(v * 100) / 100
        }
    }
}
