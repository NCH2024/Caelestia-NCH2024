pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus
import qs.modules.bar.popouts as BarPopouts

StyledRect {
    id: root

    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts

    readonly property bool btEnabled: Bluetooth.defaultAdapter?.enabled ?? false // qmllint disable unresolved-type
    readonly property string btSubtitle: {
        if (!btEnabled)
            return "Off";
        const connectedDev = Bluetooth.devices.values.find(d => d.connected); // qmllint disable unresolved-type
        if (connectedDev) {
            if (connectedDev.batteryAvailable)
                return `${connectedDev.name} (${Strings.percentOne(connectedDev.battery)})`;
            return connectedDev.name;
        }
        return "On";
    }

    readonly property string wifiSubtitle: {
        if (!Nmcli.wifiEnabled)
            return "Off";
        if (Nmcli.active && Nmcli.active.ssid)
            return `${Nmcli.active.ssid} (${Nmcli.active.strength}%)`;
        return "Not connected";
    }

    readonly property real effectiveGridWidth: Math.max(320, width - Tokens.padding.medium * 2)
    readonly property real tileWidth: Math.floor((effectiveGridWidth - Tokens.spacing.extraSmall) / 2)

    function openNexusPage(pageIdx: int): void {
        root.screenState.utilities = false;
        WindowFactory.create(null, {
            initialPageIdx: pageIdx
        });
    }

    implicitWidth: 348
    implicitHeight: layout.implicitHeight + Tokens.padding.medium * 2

    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer
    clip: true

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.small

        // Top Header Row
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "tune"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.medium
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: "Quick Settings"
                    font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: `${ExtraConfig.activeModeName} • ${ExtraConfig.powerProfileName}`
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                }
            }

            // Quick Device Care Button
            IconButton {
                icon: "shield_with_heart"
                type: IconButton.Tonal
                padding: Tokens.padding.extraSmall
                onClicked: root.openNexusPage(1)
            }

            // Open Settings Button
            IconButton {
                icon: "settings"
                type: IconButton.Tonal
                padding: Tokens.padding.extraSmall
                onClicked: root.openNexusPage(0)
            }
        }

        // 2-Column Tile Grid
        GridLayout {
            id: tilesGrid

            Layout.fillWidth: true
            columns: 2
            columnSpacing: Tokens.spacing.extraSmall
            rowSpacing: Tokens.spacing.extraSmall

            // 1. Wi-Fi Tile
            DetailedToggleTile {
                icon: Nmcli.wifiEnabled ? "wifi" : "wifi_off"
                title: "Wi-Fi"
                subtitle: root.wifiSubtitle
                active: Nmcli.wifiEnabled
                hasMore: true
                onMainClicked: Nmcli.toggleWifi()
                onMoreClicked: root.openNexusPage(4)
            }

            // 2. Bluetooth Tile
            DetailedToggleTile {
                icon: root.btEnabled ? "bluetooth_connected" : "bluetooth_disabled"
                title: "Bluetooth"
                subtitle: root.btSubtitle
                active: root.btEnabled
                hasMore: true
                onMainClicked: {
                    const adapter = Bluetooth.defaultAdapter; // qmllint disable unresolved-type
                    if (adapter)
                        adapter.enabled = !adapter.enabled;
                }
                onMoreClicked: root.openNexusPage(5)
            }

            // 3. Power Profile Tile (Single Source of Truth: PowerProfiles)
            DetailedToggleTile {
                icon: ExtraConfig.powerProfileIcon
                title: "Power"
                subtitle: ExtraConfig.powerProfileName
                active: ExtraConfig.powerProfileId === "performance"
                hasMore: true
                onMainClicked: ExtraConfig.cyclePowerProfile()
                onMoreClicked: root.openNexusPage(2)
            }

            // 4. Modes & Routines Tile
            DetailedToggleTile {
                icon: ExtraConfig.activeModeIcon
                title: "Mode"
                subtitle: ExtraConfig.activeModeName
                active: ExtraConfig.activeModeId !== "standard"
                hasMore: true
                onMainClicked: ExtraConfig.cycleMode()
                onMoreClicked: root.openNexusPage(1)
            }

            // 5. Studio Equalizer Tile
            DetailedToggleTile {
                icon: "equalizer"
                title: "Studio EQ"
                subtitle: EqualizerService.enabled ? EqualizerService.activePresetName : "Off"
                active: EqualizerService.enabled
                hasMore: true
                onMainClicked: {
                    EqualizerService.enabled = !EqualizerService.enabled;
                    EqualizerService.scheduleApply();
                }
                onMoreClicked: root.openNexusPage(6)
            }

            // 6. Night Light Tile
            DetailedToggleTile {
                icon: "nightlight"
                title: "Night Light"
                subtitle: ExtraConfig.nightLightEnabled ? `${ExtraConfig.nightLightTemp}K` : "Off"
                active: ExtraConfig.nightLightEnabled
                hasMore: true
                onMainClicked: ExtraConfig.applyNightLight(!ExtraConfig.nightLightEnabled, ExtraConfig.nightLightTemp)
                onMoreClicked: root.openNexusPage(9)
            }

            // 7. Game Mode Tile
            DetailedToggleTile {
                icon: "sports_esports"
                title: "Game Mode"
                subtitle: GameMode.enabled ? "FPS Boost" : "Standard"
                active: GameMode.enabled
                hasMore: true
                onMainClicked: GameMode.enabled = !GameMode.enabled
                onMoreClicked: root.openNexusPage(2)
            }

            // 8. Keep Awake (Idle Inhibitor) Tile
            DetailedToggleTile {
                icon: "coffee"
                title: "Keep Awake"
                subtitle: IdleInhibitor.enabled ? "Active" : "Auto sleep"
                active: IdleInhibitor.enabled
                hasMore: true
                onMainClicked: IdleInhibitor.enabled = !IdleInhibitor.enabled
                onMoreClicked: root.openNexusPage(2)
            }
        }

        // Quick Audio & Mic Sliders
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: slidersCol.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.medium
            color: Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)
            clip: true

            ColumnLayout {
                id: slidersCol

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.padding.small
                spacing: 4

                // Speaker Volume Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    IconButton {
                        icon: Icons.getVolumeIcon(Audio.volume, Audio.muted)
                        type: IconButton.Text
                        padding: 2
                        onClicked: Audio.setStreamMuted(Audio.sink, !Audio.muted)
                    }

                    StyledSlider {
                        Layout.fillWidth: true
                        implicitWidth: 80
                        value: Math.min(1, Audio.volume)
                        onInteraction: v => Audio.setVolume(v)
                    }

                    StyledText {
                        Layout.preferredWidth: 36
                        horizontalAlignment: Text.AlignRight
                        text: Strings.percentOne(Audio.volume)
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    IconButton {
                        icon: "tune"
                        type: IconButton.Text
                        padding: 2
                        onClicked: root.openNexusPage(6)
                    }
                }

                // Microphone Volume Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    IconButton {
                        icon: Icons.getMicVolumeIcon(Audio.sourceVolume, Audio.sourceMuted)
                        type: IconButton.Text
                        padding: 2
                        onClicked: Audio.setStreamMuted(Audio.source, !Audio.sourceMuted)
                    }

                    StyledSlider {
                        Layout.fillWidth: true
                        implicitWidth: 80
                        value: Math.min(1, Audio.sourceVolume)
                        onInteraction: v => Audio.setSourceVolume(v)
                    }

                    StyledText {
                        Layout.preferredWidth: 36
                        horizontalAlignment: Text.AlignRight
                        text: Strings.percentOne(Audio.sourceVolume)
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    IconButton {
                        icon: "hard_drive"
                        type: IconButton.Text
                        padding: 2
                        onClicked: root.openNexusPage(7)
                    }
                }
            }
        }
    }

    component DetailedToggleTile: StyledRect {
        id: tile

        required property string icon
        required property string title
        required property string subtitle
        required property bool active
        property bool hasMore: false

        signal mainClicked
        signal moreClicked

        Layout.fillWidth: true
        Layout.preferredWidth: root.tileWidth
        Layout.minimumWidth: root.tileWidth
        Layout.maximumWidth: root.tileWidth
        implicitWidth: root.tileWidth
        implicitHeight: 50
        radius: Tokens.rounding.medium
        color: active ? Colours.palette.m3primary : Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)
        clip: true

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // Left Main Toggle Area
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                StateLayer {
                    radius: tile.radius
                    topRightRadius: tile.hasMore ? 0 : tile.radius
                    bottomRightRadius: tile.hasMore ? 0 : tile.radius
                    onClicked: tile.mainClicked()
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 4
                    spacing: 8

                    MaterialIcon {
                        text: tile.icon
                        color: tile.active ? Colours.palette.m3onPrimary : Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.small
                        fill: tile.active ? 1 : 0
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: tile.title
                            color: tile.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                            font: Tokens.font.label.medium
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: tile.subtitle
                            color: tile.active ? Colours.palette.m3onPrimary : Colours.palette.m3outline
                            opacity: tile.active ? 0.88 : 1.0
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // Divider line before chevron
            Rectangle {
                visible: tile.hasMore
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                Layout.topMargin: 10
                Layout.bottomMargin: 10
                color: tile.active ? Colours.palette.m3onPrimary : Colours.palette.m3outlineVariant
                opacity: 0.25
            }

            // Right Chevron Area to open Settings page
            Item {
                visible: tile.hasMore
                Layout.preferredWidth: 28
                Layout.fillHeight: true

                StateLayer {
                    radius: tile.radius
                    topLeftRadius: 0
                    bottomLeftRadius: 0
                    onClicked: tile.moreClicked()
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "chevron_right"
                    color: tile.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }
            }
        }
    }
}
