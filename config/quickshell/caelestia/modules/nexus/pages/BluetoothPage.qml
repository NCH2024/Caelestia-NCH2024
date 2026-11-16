pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter // qmllint disable unresolved-type
    readonly property bool btEnabled: adapter?.enabled ?? false
    readonly property bool isScanning: adapter?.discovering ?? false
    property string btAudioProfile: "a2dp"

    function switchBtAudioProfile(prof: string): void {
        root.btAudioProfile = prof;
        const cmd = `
            for card in $(pactl list short cards 2>/dev/null | awk '/bluez_card/{print $2}'); do
                if [ "${prof}" = "a2dp" ]; then
                    pactl set-card-profile "$card" a2dp-sink 2>/dev/null || pactl set-card-profile "$card" a2dp-sink-sbc_xq 2>/dev/null || pactl set-card-profile "$card" a2dp-sink-aac 2>/dev/null || true
                else
                    pactl set-card-profile "$card" headset-head-unit 2>/dev/null || pactl set-card-profile "$card" headset-head-unit-cvsd 2>/dev/null || pactl set-card-profile "$card" headset-head-unit-msbc 2>/dev/null || true
                fi
            done
        `;
        Quickshell.execDetached(["bash", "-c", cmd]);
    }

    title: Tr.tr("Connected devices")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            text: Tr.tr("Bluetooth")
            subtext: root.btEnabled ? "Enabled — Controller ready" : "Disabled"
            font: Tokens.font.body.medium
            horizontalPadding: Tokens.padding.largeIncreased
            checked: root.btEnabled
            onToggled: {
                if (root.adapter)
                    root.adapter.enabled = checked;
            }
        }

        ItemList {
            id: deviceList

            showList: root.btEnabled
            placeholderIcon: root.btEnabled ? "devices_other" : "bluetooth_disabled"
            placeholderText: root.btEnabled ? Tr.tr("No saved devices") : Tr.tr("Bluetooth disabled")

            model: ScriptModel {
                values: Bluetooth.devices.values.filter(d => d.bonded).sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name)) // qmllint disable unresolved-type
            }

            delegate: ConnectedRect {
                id: device

                required property BluetoothDevice modelData
                required property int index
                readonly property bool connected: modelData?.connected ?? false
                readonly property bool loading: modelData && (modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting)

                width: ListView.view ? ListView.view.width : undefined
                implicitHeight: deviceInner.implicitHeight + Tokens.padding.medium * 2
                color: connected ? Colours.tPalette.m3surfaceContainerHigh : Colours.tPalette.m3surfaceContainer

                StateLayer {
                    topLeftRadius: parent.topLeftRadius
                    topRightRadius: parent.topRightRadius
                    bottomLeftRadius: parent.bottomLeftRadius
                    bottomRightRadius: parent.bottomRightRadius
                    disabled: device.loading || !root.btEnabled

                    onClicked: {
                        if (device.modelData)
                            device.modelData.connected = !device.modelData.connected;
                    }
                }

                RowLayout {
                    id: deviceInner

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: implicitHeight
                        implicitHeight: devIcon.implicitHeight + Tokens.padding.normal * 2

                        radius: device.connected ? Tokens.rounding.small : implicitHeight / 2
                        color: device.connected ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainerHighest

                        Behavior on radius {
                            Anim {}
                        }

                        MaterialIcon {
                            id: devIcon

                            anchors.centerIn: parent
                            text: Icons.getBluetoothIcon(device.modelData?.icon)
                            color: device.connected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                            fontStyle: Tokens.font.icon.large
                            fill: device.connected ? 1 : 0
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: device.modelData?.name ?? Tr.trCtx("Unknown", "unknown bluetooth device")
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                if (!device.connected)
                                    return `${Tr.trCtx("Saved", "bluetooth device state")} • ${device.modelData?.address ?? ""}`;
                                if (device.modelData?.batteryAvailable)
                                    return Tr.trCtx("Connected • %1", "bluetooth device state with battery").arg(Strings.percentOne(device.modelData.battery));
                                return Tr.trCtx("Connected", "bluetooth device state");
                            }
                            color: device.connected ? Colours.palette.m3primary : Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                            animate: true
                        }
                    }

                    AnimLoader {
                        sourceComp: device.loading ? loadingComp : settingsComp

                        Component {
                            id: settingsComp

                            StyledRect {
                                implicitWidth: implicitHeight
                                implicitHeight: settingsIcon.implicitHeight + Tokens.padding.small * 2

                                radius: Tokens.rounding.full
                                color: "transparent"

                                StateLayer {
                                    color: device.connected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface

                                    onClicked: {
                                        root.nState.selectedBtDevice = device.modelData;
                                        root.nState.openSubPage(1);
                                    }
                                }

                                MaterialIcon {
                                    id: settingsIcon

                                    anchors.centerIn: parent
                                    text: "settings"
                                    color: device.connected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                                }
                            }
                        }

                        Component {
                            id: loadingComp

                            CircularIndicator {
                                implicitSize: Tokens.font.icon.normal.pointSize + Tokens.padding.small * 2
                                running: true
                                fgColour: device.connected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3primary
                                bgColour: "transparent"
                            }
                        }
                    }
                }
            }
        }

        RowButton {
            last: true
            icon: "add"
            text: Tr.tr("Pair new device")
            disabled: !root.btEnabled
            onClicked: root.nState.openSubPage(2)
        }

        // Bluetooth Audio Codec & Profile Controls
        SectionHeader {
            text: Tr.tr("Bluetooth Audio Profile (A2DP / Headset)")
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: codecCol.implicitHeight + Tokens.padding.large * 2
            first: true
            last: true

            ColumnLayout {
                id: codecCol

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                StyledText {
                    text: Tr.tr("Select audio transmission mode for connected Bluetooth headphones/speakers")
                    font: Tokens.font.body.small
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 42
                        radius: Tokens.rounding.medium
                        color: root.btAudioProfile === "a2dp" ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                        StateLayer {
                            radius: parent.radius
                            onClicked: root.switchBtAudioProfile("a2dp")
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialIcon {
                                text: "headphones"
                                color: root.btAudioProfile === "a2dp" ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                fontStyle: Tokens.font.icon.small
                            }

                            StyledText {
                                text: "Hi-Fi A2DP (Music & Media)"
                                color: root.btAudioProfile === "a2dp" ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                font: Tokens.font.label.small
                            }
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 42
                        radius: Tokens.rounding.medium
                        color: root.btAudioProfile === "hfp" ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                        StateLayer {
                            radius: parent.radius
                            onClicked: root.switchBtAudioProfile("hfp")
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialIcon {
                                text: "headset_mic"
                                color: root.btAudioProfile === "hfp" ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                fontStyle: Tokens.font.icon.small
                            }

                            StyledText {
                                text: "Headset HFP/HSP (Voice & Mic)"
                                color: root.btAudioProfile === "hfp" ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                font: Tokens.font.label.small
                            }
                        }
                    }
                }
            }
        }

        // Adapter & Visibility Settings
        SectionHeader {
            text: Tr.tr("Adapter & Visibility")
        }

        ToggleRow {
            first: true
            text: Tr.trCtx("Discoverable", "bluetooth setting")
            subtext: Tr.tr("Allow nearby devices to find this computer")
            disabled: !root.btEnabled
            checked: root.adapter?.discoverable ?? false
            onToggled: {
                if (root.adapter)
                    root.adapter.discoverable = checked;
            }
        }

        ToggleRow {
            text: Tr.trCtx("Pairable", "bluetooth setting")
            subtext: Tr.tr("Allow nearby devices to pair with this computer")
            disabled: !root.btEnabled
            checked: root.adapter?.pairable ?? false
            onToggled: {
                if (root.adapter)
                    root.adapter.pairable = checked;
            }
        }

        RowButton {
            last: true
            icon: "restart_alt"
            text: Tr.tr("Restart Bluetooth Service & Unblock RFKill")
            subtext: Tr.tr("Reset Bluetooth controller if audio or pairing becomes unresponsive")
            onClicked: TaskRunner.run("Restart Bluetooth Service", "rfkill unblock bluetooth && systemctl restart bluetooth && echo 'Bluetooth service restarted.'", true, "bluetooth")
        }
    }
}
