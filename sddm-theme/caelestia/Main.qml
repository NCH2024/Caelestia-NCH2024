import QtQuick
import QtQuick.Layouts
import SddmComponents 2.0

Rectangle {
    id: root

    width: 1920
    height: 1080
    color: config.surfaceColor || "#110d11"

    readonly property color colPrimary: config.primaryColor || "#e1bae0"
    readonly property color colOnPrimary: config.onPrimaryColor || "#533655"
    readonly property color colSurface: config.surfaceColor || "#110d11"
    readonly property color colContainer: config.surfaceContainer || "#1e181d"
    readonly property color colContainerHigh: config.surfaceContainerHigh || "#2b232b"
    readonly property color colText: config.textColor || "#f0e1ec"
    readonly property color colSubtext: config.subtextColor || "#b4a7b1"
    readonly property color colOutline: config.outlineColor || "#4f454d"
    readonly property color colError: config.errorColor || "#f97386"

    property int sessionIndex: (sessionModel && sessionModel.lastIndex !== undefined && sessionModel.lastIndex >= 0) ? sessionModel.lastIndex : 0
    property string selectedUser: (userModel && userModel.lastUser) ? userModel.lastUser : "mew"
    property string statusMsg: ""
    property bool isError: false
    property bool showPassword: false

    TextConstants {
        id: textConstants
    }

    Connections {
        target: sddm
        function onLoginSucceeded() {
            root.isError = false;
            root.statusMsg = "Signing in to Caelestia...";
        }
        function onLoginFailed() {
            root.isError = true;
            root.statusMsg = "Incorrect password, please try again.";
            passwordInput.text = "";
            passwordInput.forceActiveFocus();
        }
    }

    function doLogin() {
        root.isError = false;
        root.statusMsg = "Authenticating...";
        const uname = userInput.text.trim().length > 0 ? userInput.text.trim() : root.selectedUser;
        sddm.login(uname, passwordInput.text, root.sessionIndex);
    }

    // Wallpaper background
    Image {
        id: bgImage
        anchors.fill: parent
        source: config.background || "background.jpg"
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
    }

    // Scrim overlay matching Caelestia lock screen
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#66110d11" }
            GradientStop { position: 0.5; color: "#88110d11" }
            GradientStop { position: 1.0; color: "#cc110d11" }
        }
    }

    // Top Status Pill (Session Badge)
    Rectangle {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 28
        height: 38
        width: topRow.implicitWidth + 32
        radius: 19
        color: "#cc1e181d"
        border.color: root.colOutline
        border.width: 1

        RowLayout {
            id: topRow
            anchors.centerIn: parent
            spacing: 10

            Rectangle {
                width: 8
                height: 8
                radius: 4
                color: root.colPrimary
            }

            Text {
                text: "Caelestia Shell  •  Hyprland"
                color: root.colText
                font.family: "Rubik"
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }
    }

    // Center Clock & Login Card
    ColumnLayout {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -20
        width: 420
        spacing: 28

        // Caelestia Desktop Clock Style
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 4

            Text {
                id: clockLabel
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatTime(new Date(), "HH:mm")
                color: root.colPrimary
                font.family: "Rubik"
                font.pixelSize: 88
                font.weight: Font.Bold
            }

            Text {
                id: dateLabel
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatDate(new Date(), "dddd, MMMM d")
                color: root.colText
                font.family: "Rubik"
                font.pixelSize: 18
                font.weight: Font.Medium
            }

            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: {
                    const now = new Date();
                    clockLabel.text = Qt.formatTime(now, "HH:mm");
                    dateLabel.text = Qt.formatDate(now, "dddd, MMMM d");
                }
            }
        }

        // Material 3 Surface Card
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: cardCol.implicitHeight + 48
            radius: 28
            color: "#dd1e181d"
            border.color: root.isError ? root.colError : root.colOutline
            border.width: 1.5

            ColumnLayout {
                id: cardCol
                anchors.fill: parent
                anchors.margins: 24
                spacing: 16

                // User Avatar Circle
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 68
                    height: 68
                    radius: 34
                    color: root.colContainerHigh
                    border.color: root.colPrimary
                    border.width: 2

                    Text {
                        anchors.centerIn: parent
                        text: (userInput.text.length > 0 ? userInput.text[0] : "M").toUpperCase()
                        color: root.colPrimary
                        font.family: "Rubik"
                        font.pixelSize: 28
                        font.weight: Font.Bold
                    }
                }

                // Username input pill
                Rectangle {
                    Layout.fillWidth: true
                    height: 44
                    radius: 22
                    color: root.colContainerHigh
                    border.color: userInput.activeFocus ? root.colPrimary : root.colOutline
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 10

                        Text {
                            text: "person"
                            color: root.colSubtext
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 18
                        }

                        TextInput {
                            id: userInput
                            Layout.fillWidth: true
                            text: root.selectedUser
                            color: root.colText
                            font.family: "Rubik"
                            font.pixelSize: 15
                            font.weight: Font.Medium
                            verticalAlignment: TextInput.AlignVCenter
                            selectByMouse: true
                            KeyNavigation.tab: passwordInput
                            Keys.onReturnPressed: passwordInput.forceActiveFocus()
                            Keys.onEnterPressed: passwordInput.forceActiveFocus()
                        }
                    }
                }

                // Password pill
                Rectangle {
                    Layout.fillWidth: true
                    height: 48
                    radius: 24
                    color: root.colContainerHigh
                    border.color: root.isError ? root.colError : (passwordInput.activeFocus ? root.colPrimary : root.colOutline)
                    border.width: passwordInput.activeFocus ? 2 : 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 8
                        spacing: 10

                        Text {
                            text: "lock"
                            color: root.colSubtext
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 18
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: "Enter password..."
                                color: root.colSubtext
                                font.family: "Rubik"
                                font.pixelSize: 14
                                visible: passwordInput.text.length === 0
                            }

                            TextInput {
                                id: passwordInput
                                anchors.fill: parent
                                verticalAlignment: TextInput.AlignVCenter
                                color: root.colText
                                font.family: "Rubik"
                                font.pixelSize: 15
                                echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                                focus: true
                                selectByMouse: true
                                Keys.onReturnPressed: root.doLogin()
                                Keys.onEnterPressed: root.doLogin()
                            }
                        }

                        // Show/Hide password button
                        Rectangle {
                            width: 34
                            height: 34
                            radius: 17
                            color: showPassMouse.containsMouse ? "#33ffffff" : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: root.showPassword ? "visibility_off" : "visibility"
                                color: root.colSubtext
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 18
                            }

                            MouseArea {
                                id: showPassMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showPassword = !root.showPassword
                            }
                        }

                        // Submit Arrow Button
                        Rectangle {
                            width: 36
                            height: 36
                            radius: 18
                            color: root.colPrimary
                            opacity: loginBtnMouse.pressed ? 0.85 : 1.0

                            Text {
                                anchors.centerIn: parent
                                text: "arrow_forward"
                                color: root.colOnPrimary
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 20
                            }

                            MouseArea {
                                id: loginBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.doLogin()
                            }
                        }
                    }
                }

                // Status / Error feedback
                Text {
                    visible: root.statusMsg.length > 0
                    Layout.alignment: Qt.AlignHCenter
                    text: root.statusMsg
                    color: root.isError ? root.colError : root.colPrimary
                    font.family: "Rubik"
                    font.pixelSize: 13
                }
            }
        }
    }

    // Bottom Action Bar (Suspend / Reboot / Shut Down)
    RowLayout {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 32
        spacing: 16

        Repeater {
            model: [
                { label: "Suspend", icon: "bedtime", action: "suspend" },
                { label: "Reboot", icon: "restart_alt", action: "reboot" },
                { label: "Shut Down", icon: "power_settings_new", action: "poweroff" }
            ]

            delegate: Rectangle {
                required property var modelData
                height: 40
                width: actionRow.implicitWidth + 28
                radius: 20
                color: actionMouse.containsMouse ? root.colContainerHigh : "#cc1e181d"
                border.color: root.colOutline
                border.width: 1

                RowLayout {
                    id: actionRow
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: modelData.icon
                        color: root.colPrimary
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 18
                    }

                    Text {
                        text: modelData.label
                        color: root.colText
                        font.family: "Rubik"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                }

                MouseArea {
                    id: actionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (modelData.action === "suspend")
                            sddm.suspend();
                        else if (modelData.action === "reboot")
                            sddm.reboot();
                        else if (modelData.action === "poweroff")
                            sddm.powerOff();
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        passwordInput.forceActiveFocus();
    }
}
