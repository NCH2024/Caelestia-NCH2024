pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services
import qs.modules.nexus

Singleton {
    id: root

    property var activeWindow: null

    function create(parent: Item, props: var): void {
        if (root.activeWindow && !(props && props.newWindow)) {
            if (props && props.initialPageIdx !== undefined && props.initialPageIdx >= 0) {
                root.activeWindow.setPage(props.initialPageIdx);
            }
            Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "title:^(Nexus — ).*"]);
            return;
        }
        root.activeWindow = nexusComp.createObject(parent ?? dummy, props ?? {});
    }

    QtObject {
        id: dummy
    }

    Component {
        id: nexusComp

        FloatingWindow {
            id: win

            property int initialPageIdx: 0

            function setPage(idx: int): void {
                nexus.nState.currentPageIdx = idx;
            }

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

            implicitWidth: nexus.implicitWidth
            implicitHeight: nexus.implicitHeight

            minimumSize.width: 480
            minimumSize.height: 360

            contentItem.Config.screen: screen.name
            contentItem.Tokens.screen: screen.name

            title: Tr.tr("Nexus — %1").arg(PageRegistry.pages[nexus.nState.currentPageIdx]?.label ?? "")

            Nexus {
                id: nexus

                anchors.fill: parent
                nState.screen: win.screen
                nState.isWindow: true
                nState.currentPageIdx: win.initialPageIdx
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
