import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.components.misc
import qs.services
import qs.modules.nexus
import qs.modules.ai

Scope {
    id: root

    property bool launcherInterrupted
    readonly property bool hasFullscreen: Hypr.focusedWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "nexus"
        description: "Open nexus"
        onPressed: WindowFactory.create()
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "showall"
        description: "Toggle launcher, dashboard and osd"
        onPressed: {
            if (root.hasFullscreen)
                return;
            const v = ShellState.forActive();
            v.launcher = v.dashboard = v.osd = v.utilities = !(v.launcher || v.dashboard || v.osd || v.utilities);
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "dashboard"
        description: "Toggle dashboard"
        onPressed: {
            if (root.hasFullscreen)
                return;
            const screenState = ShellState.forActive();
            screenState.dashboard = !screenState.dashboard;
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "session"
        description: "Toggle session menu"
        onPressed: {
            if (root.hasFullscreen)
                return;
            const screenState = ShellState.forActive();
            screenState.session = !screenState.session;
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "launcher"
        description: "Toggle launcher"
        onPressed: root.launcherInterrupted = false
        onReleased: {
            if (!root.launcherInterrupted && !root.hasFullscreen) {
                const screenState = ShellState.forActive();
                screenState.launcher = !screenState.launcher;
            }
            root.launcherInterrupted = false;
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "launcherInterrupt"
        description: "Interrupt launcher keybind"
        onPressed: root.launcherInterrupted = true
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "sidebar"
        description: "Toggle sidebar"
        onPressed: {
            if (root.hasFullscreen)
                return;
            const screenState = ShellState.forActive();
            screenState.sidebar = !screenState.sidebar;
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "utilities"
        description: "Toggle utilities"
        onPressed: {
            if (root.hasFullscreen)
                return;
            const screenState = ShellState.forActive();
            screenState.utilities = !screenState.utilities;
        }
    }

    IpcHandler {
        function toggle(drawer: string): void {
            if (list().split("\n").includes(drawer)) {
                if (root.hasFullscreen && ["launcher", "session", "dashboard"].includes(drawer))
                    return;
                const screenState = ShellState.forActive();
                screenState[drawer] = !screenState[drawer];
            } else {
                console.warn(lc, `Drawer "${drawer}" does not exist`);
            }
        }

        function list(): string {
            const screenState = ShellState.forActive();
            return Object.keys(screenState).filter(k => typeof screenState[k] === "boolean").join("\n");
        }

        function isOpen(drawer: string): string {
            const screenState = ShellState.forActive();
            if (typeof screenState[drawer] !== "boolean")
                return "unknown";
            return screenState[drawer] ? "1" : "0";
        }

        function openDashboardTab(tabIdx: int): void {
            if (root.hasFullscreen)
                return;
            const screenState = ShellState.forActive();
            screenState.dashboardTab = tabIdx;
            screenState.dashboard = true;
        }

        function openAiLauncher(): void {
            if (root.hasFullscreen)
                return;
            root.launcherInterrupted = true;
            AiAutomationService.pendingLauncherText = `${GlobalConfig.launcher.actionPrefix}ai `;
            const screenState = ShellState.forActive();
            screenState.launcher = true;
        }

        target: "drawers"
    }

    IpcHandler {
        function openMonitor(): void {
            AiWindowFactory.create();
        }

        function runTask(prompt: string): void {
            AiAutomationService.runTask(prompt, false);
        }

        function runCompactTask(prompt: string): void {
            AiAutomationService.runTask(prompt, true);
        }

        function cursorEvent(x: int, y: int, action: string, label: string, clicked: int): void {
            AiAutomationService.updateCursor(x, y, action, label, clicked === 1);
        }

        function openSettings(): void {
            WindowFactory.create(null, {
                initialPageIdx: 14
            });
        }

        target: "ai"
    }

    IpcHandler {
        function open(): void {
            WindowFactory.create();
        }

        function openPage(pageIdx: int): void {
            WindowFactory.create(null, {
                initialPageIdx: pageIdx
            });
        }

        target: "nexus"
    }

    IpcHandler {
        function activate(modeId: string): void {
            ExtraConfig.activateMode(modeId);
        }

        function cycle(): void {
            ExtraConfig.cycleMode();
        }

        function toggleGaming(): void {
            ExtraConfig.activateMode(ExtraConfig.activeModeId === "gaming" ? "standard" : "gaming");
        }

        function list(): string {
            return ExtraConfig.modes.map(m => `${m.id}:${m.nameEn || m.name}`).join("\n");
        }

        function setLiquidGlass(on: bool): void {
            ExtraConfig.setLiquidGlass(on);
        }

        target: "modes"
    }

    IpcHandler {
        function info(title: string, message: string, icon: string): void {
            Toaster.toast(title, message, icon, Toast.Info);
        }

        function success(title: string, message: string, icon: string): void {
            Toaster.toast(title, message, icon, Toast.Success);
        }

        function warn(title: string, message: string, icon: string): void {
            Toaster.toast(title, message, icon, Toast.Warning);
        }

        function error(title: string, message: string, icon: string): void {
            Toaster.toast(title, message, icon, Toast.Error);
        }

        target: "toaster"
    }

    LoggingCategory {
        id: lc

        name: "caelestia.qml.shortcuts"
        defaultLogLevel: LoggingCategory.Info
    }
}
