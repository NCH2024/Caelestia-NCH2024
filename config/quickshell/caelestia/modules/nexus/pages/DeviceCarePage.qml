pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> lockTimeItems: [
        MenuItem { text: "Never"; property int sec: 0 },
        MenuItem { text: "1 minute"; property int sec: 60 },
        MenuItem { text: "3 minutes"; property int sec: 180 },
        MenuItem { text: "5 minutes"; property int sec: 300 },
        MenuItem { text: "10 minutes"; property int sec: 600 },
        MenuItem { text: "15 minutes"; property int sec: 900 },
        MenuItem { text: "30 minutes"; property int sec: 1800 }
    ]

    readonly property list<MenuItem> dpmsTimeItems: [
        MenuItem { text: "Never"; property int sec: 0 },
        MenuItem { text: "2 minutes"; property int sec: 120 },
        MenuItem { text: "5 minutes"; property int sec: 300 },
        MenuItem { text: "10 minutes"; property int sec: 600 },
        MenuItem { text: "15 minutes"; property int sec: 900 },
        MenuItem { text: "30 minutes"; property int sec: 1800 }
    ]

    readonly property list<MenuItem> sleepTimeItems: [
        MenuItem { text: "Never"; property int sec: 0 },
        MenuItem { text: "5 minutes"; property int sec: 300 },
        MenuItem { text: "10 minutes"; property int sec: 600 },
        MenuItem { text: "15 minutes"; property int sec: 900 },
        MenuItem { text: "30 minutes"; property int sec: 1800 },
        MenuItem { text: "60 minutes"; property int sec: 3600 }
    ]

    readonly property list<MenuItem> scxSchedItems: [
        MenuItem { text: "Kernel EEVDF (Default)"; property string sId: "eevdf" },
        MenuItem { text: "scx_lavd (Gaming & Interactive)"; property string sId: "lavd" },
        MenuItem { text: "scx_bpfland (Low-Latency Desktop)"; property string sId: "bpfland" },
        MenuItem { text: "scx_cosmos (Balanced Multi-Core)"; property string sId: "cosmos" },
        MenuItem { text: "scx_rusty (Throughput Workloads)"; property string sId: "rusty" }
    ]

    readonly property list<MenuItem> scxModeItems: [
        MenuItem { text: "Auto"; property string mId: "Auto" },
        MenuItem { text: "Gaming"; property string mId: "Gaming" },
        MenuItem { text: "Low Latency"; property string mId: "LowLatency" },
        MenuItem { text: "Power Save"; property string mId: "PowerSave" }
    ]

    readonly property list<MenuItem> ioSchedItems: [
        MenuItem { text: "Kyber (Fast Balanced NVMe)"; property string ioId: "kyber" },
        MenuItem { text: "None (Direct NVMe Queue)"; property string ioId: "none" },
        MenuItem { text: "MQ-Deadline (Latency Floor)"; property string ioId: "mq-deadline" },
        MenuItem { text: "ADIOS (Adaptive CachyOS)"; property string ioId: "adios" }
    ]

    readonly property list<MenuItem> autoRamItems: [
        MenuItem { text: "Off (Manual Only)"; property int thr: 0 },
        MenuItem { text: "Above 85% RAM"; property int thr: 85 },
        MenuItem { text: "Above 90% RAM"; property int thr: 90 }
    ]

    title: Tr.tr("Power, Fans & Care")

    Component.onCompleted: OptimizerService.refreshTelemetry()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Hero Health Score & Quick Optimize Card
        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: careHeroCol.implicitHeight + Tokens.padding.large * 2
            first: true
            last: true

            ColumnLayout {
                id: careHeroCol

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.large

                    StyledRect {
                        implicitWidth: 78
                        implicitHeight: 78
                        radius: 39
                        color: OptimizerService.healthScore >= 90 ? Colours.palette.m3primaryContainer : (OptimizerService.healthScore >= 75 ? Colours.palette.m3secondaryContainer : Colours.palette.m3errorContainer)
                        border.width: 3
                        border.color: OptimizerService.healthScore >= 90 ? Colours.palette.m3primary : Colours.palette.m3tertiary

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: -2

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: String(OptimizerService.healthScore)
                                color: OptimizerService.healthScore >= 90 ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSecondaryContainer
                                font: Tokens.font.title.large
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: "/ 100"
                                color: Colours.palette.m3outline
                                font: Tokens.font.label.small
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        StyledText {
                            Layout.fillWidth: true
                            text: OptimizerService.healthScore >= 90 ? "System Status: Excellent" : (OptimizerService.healthScore >= 75 ? "System Status: Good" : "Optimization Recommended")
                            font: Tokens.font.title.medium
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: OptimizerService.optimizeStatusText
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                            wrapMode: Text.WordWrap
                        }
                    }

                    StyledRect {
                        implicitWidth: optBtnRow.implicitWidth + Tokens.padding.large * 2
                        implicitHeight: 42
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        StateLayer {
                            radius: parent.radius
                            disabled: OptimizerService.optimizingNow
                            onClicked: OptimizerService.runDeepOptimize()
                        }

                        RowLayout {
                            id: optBtnRow

                            anchors.centerIn: parent
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                text: OptimizerService.optimizingNow ? "autorenew" : "auto_fix_high"
                                color: Colours.palette.m3onPrimary
                                fontStyle: Tokens.font.icon.medium
                            }

                            StyledText {
                                text: OptimizerService.optimizingNow ? "Optimizing..." : "Optimize Now"
                                color: Colours.palette.m3onPrimary
                                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                            }
                        }
                    }
                }

                // 4 Pillar Summary Cards (RAM / Storage / CPU Temp / dGPU Temp)
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
                                text: `${OptimizerService.ramPct}%`
                                color: Colours.palette.m3primary
                                font: Tokens.font.title.medium
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Memory"
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
                                text: `${OptimizerService.rootDiskPct}%`
                                color: Colours.palette.m3secondary
                                font: Tokens.font.title.medium
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Root Disk (/)"
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
                                text: `${OptimizerService.cpuTemp}°C`
                                color: OptimizerService.cpuTemp >= 85 ? Colours.palette.m3error : Colours.palette.m3tertiary
                                font: Tokens.font.title.medium
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: "CPU Temp"
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
                                text: `${OptimizerService.gpuTemp}°C`
                                color: Colours.palette.m3primary
                                font: Tokens.font.title.medium
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: "RTX 3050 GPU"
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                            }
                        }
                    }
                }
            }
        }

        // ---- 0. CachyOS Kernel, Sched-ext & Auto-Boost Tuning ----------------
        SectionHeader {
            text: Tr.tr("CachyOS Kernel, Sched-ext & Auto-Boost")
        }

        SelectRow {
            first: true
            label: "CPU Scheduler (sched-ext)"
            subtext: `Active: ${OptimizerService.scxSched === "eevdf" ? "Linux EEVDF" : "scx_" + OptimizerService.scxSched} (${OptimizerService.scxMode}) • EPP: ${OptimizerService.cpuEpp}`
            menuItems: root.scxSchedItems
            active: root.scxSchedItems.find(i => i.sId === OptimizerService.scxSched) ?? root.scxSchedItems[0]
            onSelected: item => OptimizerService.setScxScheduler(item.sId)
        }

        SelectRow {
            label: "Sched-ext Tuning Mode"
            subtext: "Tuning preset passed to active scx scheduler via scxctl"
            menuItems: root.scxModeItems
            active: root.scxModeItems.find(i => i.mId.toLowerCase() === OptimizerService.scxMode.toLowerCase()) ?? root.scxModeItems[0]
            onSelected: item => {
                if (OptimizerService.scxSched !== "eevdf")
                    OptimizerService.setScxScheduler(OptimizerService.scxSched, item.mId);
            }
        }

        ToggleRow {
            text: "Persist Scheduler on Boot"
            subtext: "Enable scx_loader.service and write /etc/scx_loader.toml"
            checked: OptimizerService.scxBootEnabled
            onToggled: OptimizerService.setScxBoot(checked)
        }

        ToggleRow {
            text: "CPU Turbo Boost (AMD Precision Boost)"
            subtext: "Allow Ryzen CPU cores to boost above base frequency"
            checked: OptimizerService.cpuTurboEnabled
            onToggled: OptimizerService.setCpuTurbo(checked)
        }

        SelectRow {
            label: "NVMe I/O Scheduler"
            subtext: `Block queue scheduler for nvme0n1 (${OptimizerService.ioAvailable.join(", ")})`
            menuItems: root.ioSchedItems
            active: root.ioSchedItems.find(i => i.ioId === OptimizerService.ioScheduler) ?? root.ioSchedItems[0]
            onSelected: item => OptimizerService.setIoScheduler(item.ioId)
        }

        SelectRow {
            label: "Auto-Boost RAM Guard"
            subtext: "Automatically reclaim caches when memory usage crosses threshold"
            menuItems: root.autoRamItems
            active: root.autoRamItems.find(i => i.thr === OptimizerService.autoRamThreshold) ?? root.autoRamItems[0]
            onSelected: item => {
                OptimizerService.autoRamThreshold = item.thr;
                OptimizerService.save();
            }
        }

        ToggleRow {
            text: "Smart Cool Balanced Tuning"
            subtext: "Use balance_power EPP (3.4 GHz cap) & gentle airflow above 61°C in Balanced mode"
            checked: OptimizerService.smartCoolEnabled
            onToggled: {
                OptimizerService.smartCoolEnabled = checked;
                OptimizerService.save();
                OptimizerService.setThermalMode(OptimizerService.thermalProfile);
            }
        }

        ToggleRow {
            text: "Show Optimization Tab in Top Dashboard"
            subtext: "Display the Optimization card before Weather on top hover"
            checked: OptimizerService.showDashboardTab
            onToggled: {
                OptimizerService.showDashboardTab = checked;
                OptimizerService.save();
            }
        }

        ToggleRow {
            text: "Include Pacman Cache in Deep Boost"
            subtext: `Keep 2 recent versions and drop uninstalled caches (${OptimizerService.pacmanCacheSize})`
            checked: OptimizerService.cleanPacman
            onToggled: {
                OptimizerService.cleanPacman = checked;
                OptimizerService.save();
            }
        }

        ToggleRow {
            last: true
            text: "Run NVMe SSD TRIM in Deep Boost"
            subtext: "Discard unused blocks (fstrim -av) during one-click optimization"
            checked: OptimizerService.cleanTrim
            onToggled: {
                OptimizerService.cleanTrim = checked;
                OptimizerService.save();
            }
        }

        // ---- 1. Power Profile & Screen Idle Timeouts -------------------------
        SectionHeader {
            text: Tr.tr("Power Profile & Screen Timeouts")
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: powerProfCol.implicitHeight + Tokens.padding.large * 2
            first: true

            ColumnLayout {
                id: powerProfCol

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        Layout.fillWidth: true
                        text: `Active Power Profile: ${ExtraConfig.powerProfileName}`
                        font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                    }

                    StyledText {
                        text: UPower.onBattery ? `On Battery (${Math.round(UPower.displayDevice.percentage * 100)}%)` : `Plugged In (${Math.round(UPower.displayDevice.percentage * 100)}%)`
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: [
                            { id: "power-saver", label: "Power Saver", icon: "energy_savings_leaf" },
                            { id: "balanced", label: "Balanced", icon: "balance" },
                            { id: "performance", label: "Performance", icon: "rocket_launch" }
                        ]

                        delegate: StyledRect {
                            required property var modelData
                            readonly property bool active: ExtraConfig.powerProfileId === modelData.id

                            Layout.fillWidth: true
                            implicitHeight: 40
                            radius: Tokens.rounding.medium
                            color: active ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                            StateLayer {
                                radius: parent.radius
                                onClicked: ExtraConfig.setPowerProfile(modelData.id)
                            }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6

                                MaterialIcon {
                                    text: modelData.icon
                                    color: active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                    fontStyle: Tokens.font.icon.small
                                    fill: active ? 1 : 0
                                }

                                StyledText {
                                    text: modelData.label
                                    color: active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                    font: Tokens.font.label.medium
                                }
                            }
                        }
                    }
                }
            }
        }

        SelectRow {
            label: "Lock screen when idle"
            subtext: "Automatically lock the session after inactivity"
            menuItems: root.lockTimeItems
            active: root.lockTimeItems.find(i => i.sec === ExtraConfig.lockTimeoutSec) ?? root.lockTimeItems[2]
            onSelected: item => ExtraConfig.updateIdleTimeout("lock", item.sec)
        }

        SelectRow {
            label: "Turn off display (DPMS) when idle"
            subtext: "Power off the laptop display to save energy"
            menuItems: root.dpmsTimeItems
            active: root.dpmsTimeItems.find(i => i.sec === ExtraConfig.screenOffTimeoutSec) ?? root.dpmsTimeItems[2]
            onSelected: item => ExtraConfig.updateIdleTimeout("dpms", item.sec)
        }

        SelectRow {
            label: "Automatic system sleep"
            subtext: "Suspend or hibernate after prolonged inactivity"
            menuItems: root.sleepTimeItems
            active: root.sleepTimeItems.find(i => i.sec === ExtraConfig.sleepTimeoutSec) ?? root.sleepTimeItems[2]
            onSelected: item => ExtraConfig.updateIdleTimeout("sleep", item.sec)
        }

        ToggleRow {
            text: "Lock screen before sleep"
            subtext: "Require authentication when waking from suspend"
            checked: GlobalConfig.general.idle.lockBeforeSleep
            onToggled: GlobalConfig.general.idle.lockBeforeSleep = checked
        }

        ToggleRow {
            text: "Keep awake while audio is playing"
            subtext: "Do not blank the screen or sleep during media playback"
            checked: GlobalConfig.general.idle.inhibitWhenAudio
            onToggled: GlobalConfig.general.idle.inhibitWhenAudio = checked
        }

        ToggleRow {
            last: true
            text: "Keep awake while plugged into AC power"
            subtext: "Disable idle timeouts when charging"
            checked: GlobalConfig.general.idle.inhibitWhenCharging
            onToggled: GlobalConfig.general.idle.inhibitWhenCharging = checked
        }

        // ---- 2. Fan Control & Thermal Cooling (Dell G15 / Alienware WMI) -----
        SectionHeader {
            text: Tr.tr("Cooling Fans & Thermal Control")
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: fanCol.implicitHeight + Tokens.padding.large * 2
            first: true

            ColumnLayout {
                id: fanCol

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                // Dual Fan RPM Cards
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: Tokens.spacing.small

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 68
                        radius: Tokens.rounding.medium
                        color: Colours.palette.m3surfaceContainerHighest

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.medium

                            StyledRect {
                                implicitWidth: 42
                                implicitHeight: 42
                                radius: 21
                                color: Colours.palette.m3primaryContainer

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: "mode_fan"
                                    color: Colours.palette.m3onPrimaryContainer
                                    fontStyle: Tokens.font.icon.medium
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    text: `CPU Fan: ${OptimizerService.cpuFanRpm} RPM`
                                    font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                                }

                                StyledText {
                                    text: `Temp: ${OptimizerService.cpuTemp}°C  •  Max: ${OptimizerService.cpuFanMaxRpm} RPM`
                                    color: Colours.palette.m3outline
                                    font: Tokens.font.label.small
                                }
                            }
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 68
                        radius: Tokens.rounding.medium
                        color: Colours.palette.m3surfaceContainerHighest

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.medium

                            StyledRect {
                                implicitWidth: 42
                                implicitHeight: 42
                                radius: 21
                                color: Colours.palette.m3secondaryContainer

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: "mode_fan"
                                    color: Colours.palette.m3onSecondaryContainer
                                    fontStyle: Tokens.font.icon.medium
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    text: `GPU Fan: ${OptimizerService.gpuFanRpm} RPM`
                                    font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                                }

                                StyledText {
                                    text: `Temp: ${OptimizerService.gpuTemp}°C  •  RAM: ${OptimizerService.sodimmTemp}°C`
                                    color: Colours.palette.m3outline
                                    font: Tokens.font.label.small
                                }
                            }
                        }
                    }
                }

                // 3-way Thermal Mode Selector
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: [
                            { id: "balanced", label: "Quiet / Auto", icon: "air" },
                            { id: "performance", label: "Performance", icon: "speed" },
                            { id: "gmode", label: "G-Mode (100% Fan)", icon: "bolt" }
                        ]

                        delegate: StyledRect {
                            required property var modelData
                            readonly property bool active: OptimizerService.thermalProfile === modelData.id

                            Layout.fillWidth: true
                            implicitHeight: 38
                            radius: Tokens.rounding.medium
                            color: active ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                            StateLayer {
                                radius: parent.radius
                                onClicked: OptimizerService.setThermalMode(modelData.id)
                            }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6

                                MaterialIcon {
                                    text: modelData.icon
                                    color: active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                    fontStyle: Tokens.font.icon.small
                                }

                                StyledText {
                                    text: modelData.label
                                    color: active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                    font: Tokens.font.label.small
                                }
                            }
                        }
                    }
                }
            }
        }

        SliderRow {
            icon: "mode_fan"
            label: "CPU Fan Boost Override"
            valueLabel: `${Math.round(value)}%`
            from: 0
            to: 100
            value: OptimizerService.cpuFanBoost
            onMoved: v => OptimizerService.setFanBoost(Math.round(v), OptimizerService.gpuFanBoost)
        }

        SliderRow {
            last: true
            icon: "mode_fan"
            label: "GPU Fan Boost Override"
            valueLabel: `${Math.round(value)}%`
            from: 0
            to: 100
            value: OptimizerService.gpuFanBoost
            onMoved: v => OptimizerService.setFanBoost(OptimizerService.cpuFanBoost, Math.round(v))
        }

        // ---- 3. Dual Graphics Cards (NVIDIA RTX 3050 dGPU + AMD Radeon iGPU) -
        SectionHeader {
            text: Tr.tr("Graphics Cards (Dual-GPU Status)")
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: nvRow.implicitHeight + Tokens.padding.large * 2
            first: true

            RowLayout {
                id: nvRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledRect {
                    implicitWidth: 44
                    implicitHeight: 44
                    radius: 22
                    color: Colours.palette.m3primaryContainer

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "developer_board"
                        color: Colours.palette.m3onPrimaryContainer
                        fontStyle: Tokens.font.icon.medium
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: `${ExtraConfig.nvGpuName} (Discrete GPU)`
                        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: `Driver ${ExtraConfig.nvDriverVer}  •  Temp: ${OptimizerService.gpuTemp}°C  •  Load: ${OptimizerService.nvGpuUtil}%  •  VRAM: ${OptimizerService.nvGpuVram}  •  Power: ${OptimizerService.nvGpuPower}`
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: amdRow.implicitHeight + Tokens.padding.large * 2
            last: true

            RowLayout {
                id: amdRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledRect {
                    implicitWidth: 44
                    implicitHeight: 44
                    radius: 22
                    color: Colours.palette.m3secondaryContainer

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "memory"
                        color: Colours.palette.m3onSecondaryContainer
                        fontStyle: Tokens.font.icon.medium
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: `${ExtraConfig.amdGpuName} (Display Compositor GPU)`
                        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: `Driver: amdgpu (Mesa RADV)  •  Temp: ${OptimizerService.amdGpuTemp}°C`
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // ---- 4. Memory & Storage Cleanup -------------------------------------
        SectionHeader {
            text: Tr.tr("Memory & Storage Cleanup")
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: ramBarCol.implicitHeight + Tokens.padding.large * 2
            first: true

            ColumnLayout {
                id: ramBarCol

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        Layout.fillWidth: true
                        text: `RAM Used: ${OptimizerService.ramUsageText} (${OptimizerService.ramPct}%)`
                        font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                    }

                    StyledText {
                        text: `ZRAM Swap: ${OptimizerService.zramText}`
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                    }
                }

                StyledProgressBar {
                    Layout.fillWidth: true
                    implicitHeight: 8
                    value: OptimizerService.ramPct / 100.0
                }
            }
        }

        RowButton {
            icon: "cleaning_services"
            text: "Reclaim Standby RAM & PageCache (drop_caches)"
            subtext: "Flush filesystem buffers and free cached memory pages"
            onClicked: {
                TaskRunner.run("Reclaim RAM & PageCache", "sync && echo 3 > /proc/sys/vm/drop_caches && echo 1 > /proc/sys/vm/compact_memory && free -h", true, "memory");
                OptimizerService.refreshTelemetry();
            }
        }

        RowButton {
            icon: "image"
            text: "Clear Thumbnail Cache"
            subtext: `Current size: ${OptimizerService.thumbSize}`
            onClicked: {
                TaskRunner.run("Clear Thumbnail Cache", "rm -rf ~/.cache/thumbnails/* && echo 'Thumbnail cache cleared.'", false, "delete_sweep");
                OptimizerService.refreshTelemetry();
            }
        }

        RowButton {
            icon: "delete"
            text: "Empty User Trash"
            subtext: `Current size: ${OptimizerService.trashSize}`
            onClicked: {
                TaskRunner.run("Empty Trash", "rm -rf ~/.local/share/Trash/files/* ~/.local/share/Trash/info/* && echo 'Trash emptied.'", false, "delete");
                OptimizerService.refreshTelemetry();
            }
        }

        RowButton {
            last: true
            icon: "receipt_long"
            text: "Vacuum Systemd Journal Logs (Keep 3 Days)"
            subtext: `Current size: ${OptimizerService.journalSize}`
            onClicked: {
                TaskRunner.run("Vacuum Systemd Journal Logs", "journalctl --vacuum-time=3d", true, "receipt_long");
                OptimizerService.refreshTelemetry();
            }
        }

        // ---- 5. Hyprland Compositor & Window Tuning --------------------------
        SectionHeader {
            text: Tr.tr("Hyprland Window & Visual Tuning")
        }

        ToggleRow {
            first: true
            text: "Hyprland Game Mode"
            subtext: "Disable blur, shadows and animations for lowest latency"
            checked: GameMode.enabled
            onToggled: GameMode.enabled = checked
        }

        ToggleRow {
            text: "Window Background Blur"
            subtext: "Frosted glass effect behind transparent windows"
            checked: ExtraConfig.blurEnabled
            onToggled: {
                ExtraConfig.blurEnabled = checked;
                ExtraConfig.applyHyprKeyword("decoration:blur:enabled", checked ? "true" : "false");
            }
        }

        ToggleRow {
            text: "Window Drop Shadows"
            subtext: "Render soft depth shadows around windows"
            checked: ExtraConfig.shadowEnabled
            onToggled: {
                ExtraConfig.shadowEnabled = checked;
                ExtraConfig.applyHyprKeyword("decoration:shadow:enabled", checked ? "true" : "false");
            }
        }

        SliderRow {
            icon: "rounded_corner"
            label: "Window Corner Rounding"
            valueLabel: `${Math.round(value)} px`
            from: 0
            to: 28
            value: ExtraConfig.windowRounding
            onMoved: v => {
                ExtraConfig.windowRounding = Math.round(v);
                ExtraConfig.applyHyprKeyword("decoration:rounding", String(ExtraConfig.windowRounding));
            }
        }

        SliderRow {
            icon: "border_style"
            label: "Window Border Thickness"
            valueLabel: `${Math.round(value)} px`
            from: 0
            to: 6
            value: ExtraConfig.windowBorderSize
            onMoved: v => {
                ExtraConfig.windowBorderSize = Math.round(v);
                ExtraConfig.applyHyprKeyword("general:border_size", String(ExtraConfig.windowBorderSize));
            }
        }

        SliderRow {
            icon: "space_dashboard"
            label: "Inner Window Gaps (Gaps In)"
            valueLabel: `${Math.round(value)} px`
            from: 0
            to: 24
            value: ExtraConfig.windowGapsIn
            onMoved: v => {
                ExtraConfig.windowGapsIn = Math.round(v);
                ExtraConfig.applyHyprKeyword("general:gaps_in", String(ExtraConfig.windowGapsIn));
            }
        }

        SliderRow {
            last: true
            icon: "fullscreen_exit"
            label: "Outer Screen Gaps (Gaps Out)"
            valueLabel: `${Math.round(value)} px`
            from: 0
            to: 36
            value: ExtraConfig.windowGapsOut
            onMoved: v => {
                ExtraConfig.windowGapsOut = Math.round(v);
                ExtraConfig.applyHyprKeyword("general:gaps_out", String(ExtraConfig.windowGapsOut));
            }
        }
    }
}
