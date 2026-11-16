pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property string ssid: nState.selectedNetworkSsid
    readonly property var ap: Nmcli.findNetwork(root.ssid)
    property bool showPassword: false
    property bool connecting: false
    property bool failed: false
    property string errorMsg: ""

    function submit(): void {
        if (!root.ssid || root.connecting)
            return;

        const pwd = passwordField.text;
        if (pwd.length < 8) {
            passwordField.isError = true;
            errorMsg = Tr.tr("Password must be at least 8 characters");
            passwordField.forceActiveFocus();
            return;
        }

        root.failed = false;
        root.errorMsg = "";
        passwordField.isError = false;
        root.connecting = true;

        Nmcli.connectToNetwork(root.ssid, pwd, root.ap?.bssid ?? "", result => {
            root.connecting = false;
            if (result && result.success) {
                if (!autoConnectToggle.checked) {
                    Nmcli.setAutoconnect(root.ssid, false, () => {});
                }
                root.nState.closeSubPage();
            } else {
                root.failed = true;
                passwordField.isError = true;
                root.errorMsg = Tr.tr("Connection failed — please check your password and try again.");
                Nmcli.forgetNetwork(root.ssid);
            }
        });
    }

    title: root.ssid || Tr.tr("Connect to Wi-Fi")
    isSubPage: true

    Component.onCompleted: {
        focusTimer.start();
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Timer {
            id: focusTimer

            interval: 150
            onTriggered: passwordField.forceActiveFocus()
        }

        SectionHeader {
            first: true
            text: Tr.tr("Network details")
        }

        InfoRow {
            first: true
            icon: "wifi"
            label: Tr.tr("SSID")
            value: root.ssid || "—"
        }

        InfoRow {
            icon: "signal_wifi_4_bar"
            label: Tr.tr("Signal strength")
            value: root.ap ? `${root.ap.strength}% (${root.ap.frequency >= 4900 ? "5 GHz" : "2.4 GHz"} • ${root.ap.frequency} MHz)` : "—"
        }

        InfoRow {
            last: true
            icon: "lock"
            label: Tr.tr("Security")
            value: root.ap?.security || "WPA2/WPA3"
        }

        SectionHeader {
            text: Tr.tr("Authentication")
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            Layout.bottomMargin: Tokens.spacing.small
            spacing: Tokens.spacing.small

            StyledTextField {
                id: passwordField

                Layout.fillWidth: true
                enabled: !root.connecting
                placeholderText: Tr.tr("Enter Wi-Fi password")
                leadingIcon: "key"
                echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                supportingText: Tr.tr("WPA2/WPA3 passwords require at least 8 characters")
                errorText: root.errorMsg || Tr.tr("Connection failed — check the password")

                onTextEdited: {
                    if (isError) {
                        isError = false;
                        root.failed = false;
                    }
                }
                onAccepted: root.submit()
            }

            IconButton {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: Tokens.padding.small
                type: IconButton.Tonal
                isRound: true
                icon: root.showPassword ? "visibility_off" : "visibility"
                onClicked: {
                    root.showPassword = !root.showPassword;
                    passwordField.forceActiveFocus();
                }
            }
        }

        ToggleRow {
            id: autoConnectToggle

            first: true
            last: true
            text: Tr.tr("Connect automatically")
            subtext: Tr.tr("Automatically join this network when in range")
            checked: true
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: Tokens.spacing.large
            spacing: Tokens.spacing.small

            TextButton {
                Layout.fillHeight: true
                isRound: true
                horizontalPadding: Tokens.padding.extraLarge
                type: TextButton.Tonal
                text: Tr.trCtx("Cancel", "button")
                onClicked: root.nState.closeSubPage()
            }

            ButtonBase {
                id: connectBtn

                shapeMorph: true
                isRound: true
                inactiveColour: Colours.palette.m3primary
                inactiveOnColour: Colours.palette.m3onPrimary
                stateLayer.disabled: root.connecting || passwordField.text.length === 0

                implicitWidth: connectMetrics.width + Tokens.padding.extraLarge * 2
                implicitHeight: connectMetrics.height + Tokens.padding.medium * 2

                onClicked: root.submit()

                TextMetrics {
                    id: connectMetrics

                    text: Tr.tr("Connect")
                    font: connectBtn.font
                }

                AnimLoader {
                    anchors.centerIn: parent
                    sourceComp: root.connecting ? connectLoadingComp : connectTextComp
                    outAnimType: Anim.SlowEffects
                    inAnimType: Anim.SlowEffects
                }

                Component {
                    id: connectLoadingComp

                    LoadingIndicator {
                        implicitSize: Math.round(Tokens.font.body.medium.pointSize * 1.4)
                        color: connectBtn.onColour
                    }
                }

                Component {
                    id: connectTextComp

                    StyledText {
                        text: connectMetrics.text
                        font: connectBtn.font
                        color: connectBtn.onColour
                    }
                }
            }
        }
    }
}
