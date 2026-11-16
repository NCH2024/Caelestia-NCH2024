pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Blobs
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.modules.nexus

Item {
    id: root

    readonly property NexusState nState: NexusState {
        id: nState

        onClose: root.close()
    }
    property color blobColour: Colours.tPalette.m3surfaceContainerLow
    property bool sidebarCollapsed: false
    readonly property bool effectiveSidebarVisible: !sidebarCollapsed && root.width >= 560

    signal close

    implicitWidth: Math.round(implicitHeight * Tokens.sizes.nexus.ratio)
    implicitHeight: Math.round((nState.screen?.height ?? 900) * Tokens.sizes.nexus.heightMult)

    Behavior on blobColour {
        CAnim {}
    }

    TapHandler {
        onTapped: root.focus = true
    }

    BlobGroup {
        id: blobGroup

        smoothing: root.Tokens.rounding.medium
        color: root.blobColour
    }

    BlobInvertedRect {
        id: border

        anchors.fill: parent
        group: blobGroup
        opacity: root.blobColour.a
        radius: Tokens.rounding.large

        borderLeft: root.effectiveSidebarVisible ? (navPane.width + navPane.anchors.margins * 2) : Tokens.padding.medium
        borderRight: Tokens.padding.medium
        borderTop: Tokens.padding.medium
        borderBottom: Tokens.padding.medium
    }

    BlobRect {
        id: windowBtnRect

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: root.nState.isWindow ? 0 : Tokens.padding.extraSmall

        group: blobGroup
        opacity: root.blobColour.a
        radius: Tokens.rounding.medium

        implicitWidth: windowControlsRow.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: windowControlsRow.implicitHeight + Tokens.padding.small
    }

    RowLayout {
        id: windowControlsRow

        anchors.centerIn: windowBtnRect
        spacing: 2

        // Toggle Left Sidebar
        IconButton {
            icon: root.effectiveSidebarVisible ? "left_panel_close" : "left_panel_open"
            type: IconButton.Text
            label.fill: 0
            padding: Tokens.padding.extraSmall
            inactiveOnColour: hovered ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            stateLayer.opacity: 0
            onClicked: root.sidebarCollapsed = !root.sidebarCollapsed
        }

        // Toggle Task Progress Bar
        IconButton {
            visible: TaskRunner.running || TaskRunner.logLines.length > 0
            icon: TaskRunner.running ? "sync" : "terminal"
            type: IconButton.Text
            label.fill: TaskRunner.hasTask ? 1 : 0
            padding: Tokens.padding.extraSmall
            inactiveOnColour: TaskRunner.running ? Colours.palette.m3primary : (hovered ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant)
            stateLayer.opacity: 0
            onClicked: TaskRunner.hasTask = !TaskRunner.hasTask
        }

        IconButton {
            id: windowBtn

            icon: root.nState.isWindow ? "close" : "pip"
            type: IconButton.Text
            label.fill: 0
            padding: Tokens.padding.extraSmall
            inactiveOnColour: hovered ? (root.nState.isWindow ? Colours.palette.m3error : Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
            stateLayer.opacity: 0
            onClicked: {
                if (!root.nState.isWindow)
                    WindowFactory.create();
                root.close();
            }

            label.scale: pressed ? 0.8 : 1
            label.renderType: Text.QtRendering

            Behavior on label.scale {
                Anim {}
            }
        }
    }

    NavPane {
        id: navPane

        visible: root.effectiveSidebarVisible
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: Tokens.padding.large

        nState: root.nState
        width: root.effectiveSidebarVisible ? Math.min(Tokens.sizes.nexus.maxNavWidth, Math.max(210, Math.round(root.width * 0.28))) : 0
    }

    Pages {
        id: pagesArea

        anchors.left: root.effectiveSidebarVisible ? navPane.right : parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: taskDrawer.visible ? taskDrawer.top : parent.bottom
        anchors.leftMargin: root.effectiveSidebarVisible ? (navPane.anchors.margins + Tokens.padding.extraLarge) : Tokens.padding.extraLarge
        anchors.rightMargin: Tokens.padding.extraLarge
        anchors.topMargin: Tokens.padding.extraLarge
        anchors.bottomMargin: taskDrawer.visible ? Tokens.spacing.small : Tokens.padding.extraLarge

        nState: root.nState
    }

    // Sleek Material 3 Background Task Progress Card (Collapsible "Show Code" view)
    StyledRect {
        id: taskDrawer

        visible: TaskRunner.hasTask
        anchors.left: root.effectiveSidebarVisible ? navPane.right : parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.effectiveSidebarVisible ? (navPane.anchors.margins + Tokens.padding.large) : Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large
        anchors.bottomMargin: Tokens.padding.large

        implicitHeight: drawerCol.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainerHigh
        border.width: 1
        border.color: TaskRunner.running ? Colours.palette.m3primary : Colours.palette.m3outlineVariant
        clip: true

        ColumnLayout {
            id: drawerCol

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.small

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledRect {
                    implicitWidth: 32
                    implicitHeight: 32
                    radius: Tokens.rounding.full
                    color: TaskRunner.running ? Colours.palette.m3primary : (TaskRunner.exitCode === 0 ? Colours.palette.m3secondaryContainer : Colours.palette.m3errorContainer)

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: TaskRunner.running ? TaskRunner.taskIcon : (TaskRunner.exitCode === 0 ? "check_circle" : "error")
                        color: TaskRunner.running ? Colours.palette.m3onPrimary : (TaskRunner.exitCode === 0 ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onErrorContainer)
                        fontStyle: Tokens.font.icon.small
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    StyledText {
                        Layout.fillWidth: true
                        text: TaskRunner.taskTitle || "System Task"
                        font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: TaskRunner.statusText || (TaskRunner.running ? "Running in background..." : "Ready")
                        color: TaskRunner.exitCode !== 0 && !TaskRunner.running ? Colours.palette.m3error : Colours.palette.m3outline
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }

                // "Show Code" / "Hide Code" pill button
                StyledRect {
                    implicitWidth: codeBtnRow.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: 28
                    radius: Tokens.rounding.full
                    color: TaskRunner.drawerExpanded ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest

                    StateLayer {
                        radius: parent.radius
                        onClicked: TaskRunner.drawerExpanded = !TaskRunner.drawerExpanded
                    }

                    RowLayout {
                        id: codeBtnRow

                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            text: "code"
                            color: TaskRunner.drawerExpanded ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            text: TaskRunner.drawerExpanded ? "Hide Code" : "Show Code"
                            color: TaskRunner.drawerExpanded ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }
                    }
                }

                IconButton {
                    visible: TaskRunner.running
                    icon: "stop_circle"
                    type: IconButton.Tonal
                    inactiveColour: Colours.palette.m3errorContainer
                    inactiveOnColour: Colours.palette.m3onErrorContainer
                    padding: Tokens.padding.extraSmall
                    onClicked: TaskRunner.stopTask()
                }

                IconButton {
                    visible: !TaskRunner.running
                    icon: "close"
                    type: IconButton.Text
                    padding: Tokens.padding.extraSmall
                    onClicked: {
                        TaskRunner.drawerExpanded = false;
                        TaskRunner.hasTask = false;
                    }
                }
            }

            // Progress Bar (Always visible while running or when recently completed)
            StyledProgressBar {
                Layout.fillWidth: true
                implicitHeight: 6
                indeterminate: TaskRunner.running && TaskRunner.progress < 0
                value: TaskRunner.progress >= 0 ? TaskRunner.progress : (TaskRunner.exitCode === 0 ? 1.0 : 0.0)
            }

            // Collapsible Read-Only Code / Log Output (Only shown when user clicks "Show Code")
            StyledRect {
                visible: TaskRunner.drawerExpanded
                Layout.fillWidth: true
                Layout.preferredHeight: 150
                radius: Tokens.rounding.medium
                color: Colours.palette.m3surfaceContainerLowest
                clip: true

                Flickable {
                    id: logFlick

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    contentWidth: width
                    contentHeight: logTextItem.implicitHeight
                    clip: true

                    onContentHeightChanged: {
                        if (contentHeight > height)
                            contentY = contentHeight - height;
                    }

                    StyledText {
                        id: logTextItem

                        width: logFlick.width
                        text: TaskRunner.logOutput.length > 0 ? TaskRunner.logOutput : "No log output yet..."
                        font: Tokens.font.mono.small
                        color: Colours.palette.m3onSurface
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }
    }
}
