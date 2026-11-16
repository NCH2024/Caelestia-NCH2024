import QtQuick
import Quickshell
import Caelestia.Config
import qs.services
import qs.modules.ai

Scope {
    Component.onCompleted: {
        // Force certain singletons to load on shell init instead of lazily

        IdleInhibitor;
        GameMode;
        Notifs;
        Players;
        Brightness;
        ExtraConfig;
        TaskRunner;
        EqualizerService;
        AiAutomationService;
        AiWindowFactory;
        Weather.reload();

        if (GlobalConfig.utilities.vpn.enabled)
            VPN;
    }
}
