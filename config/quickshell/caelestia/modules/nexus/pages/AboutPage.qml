import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.effects
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property int pluginCount: (Config.background.desktopClock.enabled ? 1 : 0) + (Config.background.visualiser.enabled ? 1 : 0) + (Config.dashboard.enabled ? 1 : 0) + (Config.launcher.enabled ? 1 : 0) + (Config.sidebar.enabled ? 1 : 0) + (Config.utilities.enabled ? 1 : 0) + (Config.utilities.cards.recorder ? 1 : 0) + (Config.utilities.cards.keepAwake ? 1 : 0) + (Config.osd.enabled ? 1 : 0)

    property string quickshellVersion
    property string cliVersion

    title: Tr.tr("About")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // e.g. "Quickshell 0.3.0 (revision ...)"
        Process {
            running: true
            command: ["quickshell", "--version"]
            stdout: StdioCollector {
                onStreamFinished: root.quickshellVersion = text.trim().split(" ")[1] ?? ""
            }
        }

        // Parsed from the caelestia CLI's package listing; the sh wrapper avoids a
        // warning when the (optional) CLI isn't installed
        Process {
            running: true
            command: ["sh", "-c", "caelestia --version 2>/dev/null"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const m = text.match(/caelestia-cli\S*\s+(\d+(?:\.\d+)*)/);
                    root.cliVersion = m ? m[1] : "";
                }
            }
        }

        // Hero
        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: hero.implicitHeight + Tokens.padding.extraLarge * 2

            ColumnLayout {
                id: hero

                anchors.centerIn: parent
                width: parent.width - Tokens.padding.largeIncreased * 2
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Tokens.spacing.large

                    AnimatedLogo {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: implicitWidth
                        Layout.preferredHeight: implicitHeight
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: "×"
                        font: Tokens.font.headline.medium
                        color: Colours.palette.m3outline
                    }

                    Image {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 112
                        Layout.preferredHeight: 112
                        source: Quickshell.shellPath("assets/meow-logo.png")
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true

                        layer.enabled: true
                        layer.effect: Colouriser {
                            sourceColor: "black"
                            colorizationColor: Colours.palette.m3onSurface
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Tokens.spacing.small
                    text: "Caelestia × Meow"
                    font: Tokens.font.headline.builders.large.width(110).build()
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: CUtils.version ? `Base v${CUtils.version} • Meow Remake` : "Meow Remake"
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                }

                StyledRect {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Tokens.spacing.extraSmall
                    implicitWidth: collabRow.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: 32
                    radius: 16
                    color: Colours.palette.m3secondaryContainer

                    StateLayer {
                        radius: parent.radius
                        color: Colours.palette.m3onSecondaryContainer
                        onClicked: Qt.openUrlExternally("https://github.com/NCH2024")
                    }

                    RowLayout {
                        id: collabRow

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: "pets"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3primary
                            fill: 1
                        }

                        StyledText {
                            text: "Remade by Meow"
                            font: Tokens.font.label.large
                            color: Colours.palette.m3onSecondaryContainer
                        }

                        MaterialIcon {
                            text: "open_in_new"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3onSecondaryContainer
                        }
                    }
                }
            }
        }

        // Remake & Credits
        SectionHeader {
            text: Tr.tr("Remake & Credits")
        }

        InfoRow {
            first: true
            icon: "merge_type"
            label: "Edition"
            value: "Caelestia × Meow Remake"
        }

        InfoRow {
            icon: "pets"
            label: "Creator"
            value: "Meow"
        }

        InfoRow {
            icon: "tune"
            label: "Included Enhancements"
            value: "Smart Optimization, Adaptive Cooling, Studio EQ & Nexus"
        }

        RowButton {
            last: true
            icon: "code"
            trailingIcon: "open_in_new"
            text: "Meow on GitHub (@NCH2024)"
            subtext: "https://github.com/NCH2024"
            onClicked: Qt.openUrlExternally("https://github.com/NCH2024")
        }

        // System
        SectionHeader {
            text: Tr.tr("System")
        }

        InfoRow {
            first: true
            label: Tr.tr("Hostname")
            value: SysInfo.hostname
        }

        InfoRow {
            label: Tr.trCtx("Device", "system model name")
            value: SysInfo.device
        }

        InfoRow {
            label: Tr.tr("Distro")
            value: SysInfo.osPrettyName || SysInfo.osName
        }

        InfoRow {
            label: Tr.tr("Kernel")
            value: SysInfo.kernel
        }

        InfoRow {
            last: true
            // TRANSLATORS: BIOS or UEFI firmware version
            label: Tr.tr("Firmware")
            value: SysInfo.firmware
        }

        // Software
        SectionHeader {
            text: Tr.tr("Software")
        }

        InfoRow {
            first: true
            label: Tr.trCtx("Shell", "the caelestia shell itself, not a unix shell")
            value: CUtils.version || "…"
        }

        InfoRow {
            label: Tr.trCtx("CLI", "the caelestia command line tool")
            value: root.cliVersion || "…"
        }

        InfoRow {
            label: "Quickshell"
            value: root.quickshellVersion || "…"
        }

        InfoRow {
            last: true
            label: "Qt"
            value: CUtils.qtVersion || "…"
        }

        // Plugins
        SectionHeader {
            text: Tr.tr("Plugins")
        }

        InfoRow {
            first: true
            last: true
            label: Tr.tr("Loaded plugins")
            value: root.pluginCount.toString()
        }
    }
}
