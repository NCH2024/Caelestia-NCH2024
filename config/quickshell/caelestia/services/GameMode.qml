pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.services

Singleton {
    id: root

    property alias enabled: props.enabled

    function setDynamicConfs(): void {
        Hypr.extras.applyOptions({
            "animations:enabled": 0,
            "decoration:shadow:enabled": 0,
            "decoration:blur:enabled": 0,
            "general:gaps_in": 0,
            "general:gaps_out": 0,
            "general:border_size": 1,
            "decoration:rounding": 0,
            "general:allow_tearing": 1
        });
    }

    onEnabledChanged: {
        if (enabled) {
            if (!props.solidOverrideActive) {
                props.savedTransparency = GlobalConfig.appearance.transparency.enabled;
                props.solidOverrideActive = true;
            }
            GlobalConfig.appearance.transparency.enabled = false;
            setDynamicConfs();
            if (GlobalConfig.utilities.toasts.gameModeChanged)
                Toaster.toast(Tr.tr("Game mode enabled"), Tr.tr("Solid opaque UI enabled; animations, blur and shadows disabled"), "gamepad");
        } else {
            if (props.solidOverrideActive) {
                GlobalConfig.appearance.transparency.enabled = props.savedTransparency;
                props.solidOverrideActive = false;
            }
            Hypr.extras.message("reload");
            if (GlobalConfig.utilities.toasts.gameModeChanged)
                Toaster.toast(Tr.tr("Game mode disabled"), Tr.tr("Hyprland and transparency settings restored"), "gamepad");
        }
    }

    PersistentProperties {
        id: props

        property bool enabled: Hypr.options["animations:enabled"] === 0 // qmllint disable missing-property
        property bool savedTransparency: true
        property bool solidOverrideActive: false

        reloadableId: "gameMode"
    }

    Component.onCompleted: {
        if (props.enabled) {
            if (!props.solidOverrideActive) {
                props.savedTransparency = GlobalConfig.appearance.transparency.enabled;
                props.solidOverrideActive = true;
            }
            GlobalConfig.appearance.transparency.enabled = false;
        }
    }

    Connections {
        function onConfigReloaded(): void {
            if (props.enabled)
                root.setDynamicConfs();
        }

        target: Hypr
    }

    IpcHandler {
        function isEnabled(): bool {
            return props.enabled;
        }

        function toggle(): void {
            props.enabled = !props.enabled;
        }

        function enable(): void {
            props.enabled = true;
        }

        function disable(): void {
            props.enabled = false;
        }

        target: "gameMode"
    }
}
