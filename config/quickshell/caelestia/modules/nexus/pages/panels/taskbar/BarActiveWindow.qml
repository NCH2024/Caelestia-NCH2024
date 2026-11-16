import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: Tr.tr("Active window")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            text: Tr.tr("Smart compact mode (Recommended)")
            subtext: Tr.tr("Show app icon + short class name and only open info popout on click")
            checked: ExtraConfig.barCompactWindow
            onToggled: ExtraConfig.barCompactWindow = checked
        }

        ToggleRow {
            text: Tr.tr("Icon-only mode")
            subtext: Tr.tr("Hide window text completely, show only the active window icon")
            checked: ExtraConfig.barIconOnlyWindow
            onToggled: ExtraConfig.barIconOnlyWindow = checked
        }

        ToggleRow {
            text: Tr.trCtx("Compact title", "taskbar active window layout")
            checked: Config.bar.activeWindow.compact
            onToggled: GlobalConfig.bar.activeWindow.compact = checked
        }

        ToggleRow {
            text: Tr.trCtx("Inverted", "taskbar active window: swap the title and class order")
            checked: Config.bar.activeWindow.inverted
            onToggled: GlobalConfig.bar.activeWindow.inverted = checked
        }

        ToggleRow {
            text: Tr.tr("Popout on hover")
            subtext: Tr.tr("Only active when Smart compact mode is disabled")
            checked: Config.bar.popouts.activeWindow
            onToggled: GlobalConfig.bar.popouts.activeWindow = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("Show Modes & Device Care buttons below active window")
            checked: ExtraConfig.barShowModesBtn
            onToggled: {
                ExtraConfig.barShowModesBtn = checked;
                ExtraConfig.barShowCareBtn = checked;
            }
        }
    }
}
