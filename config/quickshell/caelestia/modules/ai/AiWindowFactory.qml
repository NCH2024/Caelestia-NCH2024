pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

Singleton {
    id: root

    property var activeWindow: null

    function create(parent: Item, props: var): void {
        if (root.activeWindow) {
            Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "title:^(Meow AI — ).*"]);
            return;
        }
        root.activeWindow = aiWinComp.createObject(parent ?? dummy, props ?? {});
    }

    Connections {
        target: AiAutomationService

        function onMonitorRequested(): void {
            root.create();
        }
    }

    QtObject {
        id: dummy
    }

    Component {
        id: aiWinComp

        FloatingWindow {
            id: win

            color: Colours.tPalette.m3surface
            surfaceFormat.opaque: false

            onVisibleChanged: {
                if (!visible) {
                    if (root.activeWindow === win)
                        root.activeWindow = null;
                    destroy();
                }
            }

            Component.onDestruction: {
                if (root.activeWindow === win)
                    root.activeWindow = null;
            }

            implicitWidth: 580
            implicitHeight: 680
            minimumSize.width: 440
            minimumSize.height: 420

            contentItem.Config.screen: screen.name
            contentItem.Tokens.screen: screen.name

            title: "Meow AI — Task Assistant"

            AiChatWindow {
                anchors.fill: parent
                onClose: {
                    if (root.activeWindow === win)
                        root.activeWindow = null;
                    win.destroy();
                }
            }

            Behavior on color {
                CAnim {}
            }
        }
    }
}
