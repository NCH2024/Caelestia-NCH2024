pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: Tr.tr("Updates & Drivers")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Status Overview Hero Card
        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: heroLayout.implicitHeight + Tokens.padding.large * 2
            first: true
            last: true

            ColumnLayout {
                id: heroLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: 52
                        implicitHeight: 52
                        radius: Tokens.rounding.full
                        color: TaskRunner.checkingUpdates ? Colours.palette.m3secondaryContainer : (TaskRunner.totalUpdateCount > 0 ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer)

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: TaskRunner.checkingUpdates ? "sync" : (TaskRunner.totalUpdateCount > 0 ? "system_update_alt" : "verified")
                            color: TaskRunner.checkingUpdates ? Colours.palette.m3onSecondaryContainer : (TaskRunner.totalUpdateCount > 0 ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer)
                            fontStyle: Tokens.font.icon.large
                            fill: 1
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                if (TaskRunner.checkingUpdates)
                                    return "Checking for updates...";
                                if (TaskRunner.totalUpdateCount === 0)
                                    return "Your system is up to date";
                                return `${TaskRunner.totalUpdateCount} updates available`;
                            }
                            font: Tokens.font.body.builders.large.weight(Font.Medium).build()
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                if (TaskRunner.checkingUpdates)
                                    return "Scanning CachyOS / Arch repositories, AUR, and Flatpak...";
                                const parts = [];
                                parts.push(`Official: ${TaskRunner.repoUpdates.length}`);
                                parts.push(`AUR: ${TaskRunner.aurUpdates.length}`);
                                if (TaskRunner.flatpakUpdates.length > 0)
                                    parts.push(`Flatpak: ${TaskRunner.flatpakUpdates.length}`);
                                if (TaskRunner.lastChecked.length > 0)
                                    parts.push(`Checked at ${TaskRunner.lastChecked}`);
                                return parts.join(" • ");
                            }
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    IconButton {
                        icon: "refresh"
                        type: IconButton.Tonal
                        padding: Tokens.padding.small
                        disabled: TaskRunner.checkingUpdates
                        onClicked: TaskRunner.checkUpdates()
                    }
                }

                // System Package Stats Grid
                GridLayout {
                    Layout.fillWidth: true
                    columns: 4
                    columnSpacing: Tokens.spacing.small
                    rowSpacing: Tokens.spacing.small

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 62
                        radius: Tokens.rounding.medium
                        color: Colours.palette.m3surfaceContainerHighest

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: String(TaskRunner.totalPackages)
                                color: Colours.palette.m3primary
                                font: Tokens.font.title.medium
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Installed"
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                            }
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 62
                        radius: Tokens.rounding.medium
                        color: Colours.palette.m3surfaceContainerHighest

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: TaskRunner.kernelVersion.split("-")[0] || "Linux"
                                color: Colours.palette.m3secondary
                                font: Tokens.font.title.medium
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Kernel"
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                            }
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 62
                        radius: Tokens.rounding.medium
                        color: Colours.palette.m3surfaceContainerHighest

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: TaskRunner.cacheSize
                                color: Colours.palette.m3tertiary
                                font: Tokens.font.title.medium
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Pkg Cache"
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                            }
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 62
                        radius: Tokens.rounding.medium
                        color: Colours.palette.m3surfaceContainerHighest

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: String(TaskRunner.orphanCount)
                                color: TaskRunner.orphanCount > 0 ? Colours.palette.m3error : Colours.palette.m3onSurface
                                font: Tokens.font.title.medium
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Orphans"
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                            }
                        }
                    }
                }
            }
        }

        // ---- 1. Recommended Hardware Drivers & Firmware ----------------------
        SectionHeader {
            text: Tr.tr("Recommended Hardware Drivers & Firmware")
        }

        Repeater {
            model: TaskRunner.driverProfiles

            delegate: ConnectedRect {
                id: drvCard

                required property var modelData
                required property int index

                Layout.fillWidth: true
                implicitHeight: drvRow.implicitHeight + Tokens.padding.large * 2
                first: index === 0

                RowLayout {
                    id: drvRow

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: 42
                        implicitHeight: 42
                        radius: 21
                        color: drvCard.modelData.installed ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: drvCard.modelData.icon || "developer_board"
                            color: drvCard.modelData.installed ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.medium
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            StyledText {
                                text: drvCard.modelData.device
                                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                                elide: Text.ElideRight
                            }

                            StyledRect {
                                visible: Boolean(drvCard.modelData.recommended)
                                implicitWidth: recBadge.implicitWidth + 10
                                implicitHeight: 20
                                radius: 6
                                color: Colours.palette.m3tertiaryContainer

                                StyledText {
                                    id: recBadge

                                    anchors.centerIn: parent
                                    text: "Recommended"
                                    color: Colours.palette.m3onTertiaryContainer
                                    font: Tokens.font.label.small
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: `Profile: ${drvCard.modelData.profile}  •  Version: ${drvCard.modelData.version}  •  ${drvCard.modelData.status}`
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    StyledRect {
                        implicitWidth: stBadge.implicitWidth + 14
                        implicitHeight: 26
                        radius: 13
                        color: drvCard.modelData.installed ? Colours.palette.m3secondaryContainer : Colours.palette.m3errorContainer

                        StyledText {
                            id: stBadge

                            anchors.centerIn: parent
                            text: drvCard.modelData.installed ? "Installed" : "Missing"
                            color: drvCard.modelData.installed ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onErrorContainer
                            font: Tokens.font.label.small
                        }
                    }
                }
            }
        }

        RowButton {
            icon: "developer_board"
            text: "Install / Verify Recommended Hardware Drivers (chwd -a)"
            subtext: "Automatically detect and install optimal CachyOS GPU & PCI drivers"
            onClicked: TaskRunner.runSystemUpdate("drivers")
        }

        RowButton {
            last: true
            icon: "memory"
            text: "Check & Update BIOS / Device Firmware (fwupdmgr)"
            subtext: "Scan LVFS for UEFI, NVMe, and controller firmware updates"
            onClicked: TaskRunner.runSystemUpdate("firmware")
        }

        // ---- 2. System Updates (Seamless Background Execution) ---------------
        SectionHeader {
            text: Tr.tr("System Updates")
        }

        RowButton {
            first: true
            icon: "rocket_launch"
            text: "Update Full System (Official + AUR + Flatpak)"
            subtext: "Upgrade all system packages seamlessly with live progress bar"
            onClicked: TaskRunner.runSystemUpdate("full")
        }

        RowButton {
            icon: "update"
            text: "Update Official Packages Only (pacman -Syu)"
            subtext: "Upgrade CachyOS and Arch Linux repository packages"
            onClicked: TaskRunner.runSystemUpdate("repo")
        }

        RowButton {
            last: true
            icon: "inventory_2"
            text: "Update AUR Packages Only (paru -Sua)"
            subtext: "Upgrade Arch User Repository community packages"
            onClicked: TaskRunner.runSystemUpdate("aur")
        }

        // ---- 3. Pending Updates List -----------------------------------------
        SectionHeader {
            visible: TaskRunner.totalUpdateCount > 0
            text: `Pending Updates (${TaskRunner.totalUpdateCount})`
        }

        ConnectedRect {
            visible: TaskRunner.totalUpdateCount > 0
            Layout.fillWidth: true
            implicitHeight: pkgListCol.implicitHeight + Tokens.padding.medium * 2
            first: true
            last: true

            ColumnLayout {
                id: pkgListCol

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: 4

                Repeater {
                    model: TaskRunner.repoUpdates.concat(TaskRunner.aurUpdates).concat(TaskRunner.flatpakUpdates).slice(0, 60)

                    delegate: StyledRect {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: pkgRow.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.extraSmall
                        color: Colours.palette.m3surfaceContainerHighest

                        RowLayout {
                            id: pkgRow

                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.medium
                            spacing: Tokens.spacing.small

                            StyledRect {
                                implicitWidth: srcLabel.implicitWidth + Tokens.padding.small * 2
                                implicitHeight: srcLabel.implicitHeight + 4
                                radius: Tokens.rounding.extraSmall
                                color: modelData.source === "Official" ? Colours.palette.m3primaryContainer : (modelData.source === "AUR" ? Colours.palette.m3tertiaryContainer : Colours.palette.m3secondaryContainer)

                                StyledText {
                                    id: srcLabel

                                    anchors.centerIn: parent
                                    text: modelData.source
                                    color: modelData.source === "Official" ? Colours.palette.m3onPrimaryContainer : (modelData.source === "AUR" ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSecondaryContainer)
                                    font: Tokens.font.label.small
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.name
                                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                                elide: Text.ElideRight
                            }

                            StyledText {
                                text: `${modelData.oldVer} → ${modelData.newVer}`
                                color: Colours.palette.m3outline
                                font: Tokens.font.mono.small
                            }
                        }
                    }
                }
            }
        }

        // ---- 4. Repository & Package Maintenance -----------------------------
        SectionHeader {
            text: Tr.tr("Repository & Package Maintenance")
        }

        RowButton {
            first: true
            icon: "speed"
            text: "Rank Fastest Mirrors (cachyos-rate-mirrors)"
            subtext: "Benchmark and select the fastest CachyOS & Arch mirrors"
            onClicked: TaskRunner.run("Rank Mirrors (cachyos-rate-mirrors)", "cachyos-rate-mirrors", true, "speed", true)
        }

        RowButton {
            icon: "cleaning_services"
            text: "Clean Pacman Package Cache (Keep Latest 2)"
            subtext: `Current cache size: ${TaskRunner.cacheSize}`
            onClicked: TaskRunner.run("Clean Pacman Cache (paccache -rk2)", "paccache -rk2 && paccache -ruk0", true, "cleaning_services", true)
        }

        RowButton {
            last: true
            icon: "delete_sweep"
            text: "Remove Unused Orphan Packages"
            subtext: TaskRunner.orphanCount > 0 ? `${TaskRunner.orphanCount} orphan packages can be removed` : "No orphan packages found"
            disabled: TaskRunner.orphanCount === 0
            onClicked: TaskRunner.run("Remove Orphan Packages", "pacman -Rns --noconfirm $(pacman -Qdtq)", true, "delete_sweep", true)
        }
    }
}
