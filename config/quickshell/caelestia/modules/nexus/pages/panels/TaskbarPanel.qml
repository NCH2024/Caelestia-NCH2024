import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: Tr.tr("Taskbar")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Quick Smart Buttons & Active Window Layout
        SectionHeader {
            first: true
            text: Tr.tr("Active Window & Quick Action Buttons")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Compact active window badge")
            subtext: Tr.tr("Show application icon + short name and disable hover popup preview")
            checked: ExtraConfig.barCompactWindow
            onToggled: ExtraConfig.barCompactWindow = checked
        }

        ToggleRow {
            text: Tr.tr("Icon-only active window indicator")
            subtext: Tr.tr("Show only the active application icon on the left bar")
            checked: ExtraConfig.barIconOnlyWindow
            onToggled: ExtraConfig.barIconOnlyWindow = checked
        }

        ToggleRow {
            text: Tr.tr("Show Modes & Routines button on left bar")
            subtext: Tr.tr("Left-click: Open Modes settings • Right-click: Cycle active mode")
            checked: ExtraConfig.barShowModesBtn
            onToggled: ExtraConfig.barShowModesBtn = checked
        }

        ToggleRow {
            text: Tr.tr("Show Power & Device Care button on left bar")
            subtext: Tr.tr("Left-click: Open Power & Care • Right-click: Quick RAM & cache cleanup")
            checked: ExtraConfig.barShowCareBtn
            onToggled: ExtraConfig.barShowCareBtn = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("Show Studio Equalizer button on left bar")
            subtext: Tr.tr("Left-click: Open 10-band Equalizer • Right-click: Toggle EQ")
            checked: ExtraConfig.barShowEqBtn
            onToggled: ExtraConfig.barShowEqBtn = checked
        }

        // Behaviour
        SectionHeader {
            text: Tr.tr("Behaviour")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Persistent")
            subtext: Tr.tr("Keep the bar visible at all times")
            checked: Config.bar.persistent
            onToggled: GlobalConfig.bar.persistent = checked
        }

        ToggleRow {
            text: Tr.tr("Show on hover")
            subtext: Tr.tr("Reveal the bar when the cursor reaches the screen edge")
            checked: Config.bar.showOnHover
            onToggled: GlobalConfig.bar.showOnHover = checked
        }

        StepperRow {
            last: true
            label: Tr.tr("Drag threshold")
            subtext: Tr.tr("Pixels dragged before the bar reveals")
            value: Config.bar.dragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.bar.dragThreshold = v
        }

        // Components
        SectionHeader {
            text: Tr.tr("Components")
        }

        NavRow {
            first: true
            icon: "workspaces"
            text: Tr.tr("Workspaces")
            subtext: Tr.tr("Indicators, window icons")
            onClicked: root.nState.openSubPage(6)
        }

        NavRow {
            icon: "web_asset"
            text: Tr.tr("Active window")
            subtext: Tr.tr("Title display, compact mode, popout")
            onClicked: root.nState.openSubPage(7)
        }

        NavRow {
            icon: "widgets"
            text: Tr.tr("Tray")
            subtext: Tr.tr("System tray icons")
            onClicked: root.nState.openSubPage(8)
        }

        NavRow {
            icon: "signal_cellular_alt"
            text: Tr.tr("Status icons")
            subtext: Tr.tr("Visible indicators")
            onClicked: root.nState.openSubPage(9)
        }

        NavRow {
            last: true
            icon: "schedule"
            text: Tr.tr("Clock")
            subtext: Tr.tr("Date, icon, background")
            onClicked: root.nState.openSubPage(10)
        }

        // Scroll actions
        SectionHeader {
            text: Tr.tr("Scroll actions")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Workspaces")
            subtext: Tr.tr("Scroll over the workspace indicator to switch workspaces")
            checked: Config.bar.scrollActions.workspaces
            onToggled: GlobalConfig.bar.scrollActions.workspaces = checked
        }

        ToggleRow {
            text: Tr.tr("Volume")
            subtext: Tr.tr("Scroll on the top half of the bar to adjust volume")
            checked: Config.bar.scrollActions.volume
            onToggled: GlobalConfig.bar.scrollActions.volume = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("Brightness")
            subtext: Tr.tr("Scroll on the bottom half of the bar to adjust brightness")
            checked: Config.bar.scrollActions.brightness
            onToggled: GlobalConfig.bar.scrollActions.brightness = checked
        }
    }
}
