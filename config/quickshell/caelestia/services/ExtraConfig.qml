pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Caelestia.Config
import Caelestia.I18n
import qs.services
import qs.utils

Singleton {
    id: root

    property bool loaded: false
    property string uiLanguage: "en"
    property bool desktopWeatherEnabled: true
    property bool desktopWeatherDetails: true
    property bool nightLightEnabled: false
    property int nightLightTemp: 4500
    property string quickDnsPreset: "auto"
    property bool autoOptimizeRam: false

    // Liquid Glass & Water Optical Effects
    property bool liquidGlassEnabled: false
    property real liquidGlassIntensity: 0.72
    property bool liquidGlassAnimate: true
    readonly property bool liquidGlassActive: liquidGlassEnabled && !GameMode.enabled && !_sleepSolidOverride && Colours.transparency.enabled

    // Mode Switch Edge OSD State
    property bool modeOsdVisible: false
    property string modeOsdSubtitle: ""
    signal modeOsdTriggered()

    // Left Bar Layout & Compact Active Window Options
    property bool barCompactWindow: true
    property bool barIconOnlyWindow: false
    property bool barShowModesBtn: true
    property bool barShowCareBtn: true
    property bool barShowEqBtn: true

    // Single Source of Truth: Power Profile (bound to UPower PowerProfiles daemon)
    readonly property int currentPowerProfile: PowerProfiles.profile
    readonly property string powerProfileId: {
        if (PowerProfiles.profile === PowerProfile.Performance)
            return "performance";
        if (PowerProfiles.profile === PowerProfile.PowerSaver)
            return "power-saver";
        return "balanced";
    }
    readonly property string powerProfileName: {
        if (PowerProfiles.profile === PowerProfile.Performance)
            return "Performance";
        if (PowerProfiles.profile === PowerProfile.PowerSaver)
            return "Power Saver";
        return "Balanced";
    }
    readonly property string powerProfileIcon: {
        if (PowerProfiles.profile === PowerProfile.Performance)
            return "rocket_launch";
        if (PowerProfiles.profile === PowerProfile.PowerSaver)
            return "energy_savings_leaf";
        return "balance";
    }

    function setPowerProfile(prof: string): void {
        if (prof === "performance")
            PowerProfiles.profile = PowerProfile.Performance;
        else if (prof === "power-saver" || prof === "powersave")
            PowerProfiles.profile = PowerProfile.PowerSaver;
        else
            PowerProfiles.profile = PowerProfile.Balanced;
    }

    function cyclePowerProfile(): void {
        if (PowerProfiles.profile === PowerProfile.PowerSaver)
            PowerProfiles.profile = PowerProfile.Balanced;
        else if (PowerProfiles.profile === PowerProfile.Balanced)
            PowerProfiles.profile = PowerProfile.Performance;
        else
            PowerProfiles.profile = PowerProfile.PowerSaver;
    }

    // Single Source of Truth: Thermal, Fans, Dual-GPU & System Health Telemetry
    property int healthScore: 96
    property bool optimizingNow: false
    property string optimizeStatusText: "System running optimally"
    property int ramPct: 0
    property string ramUsageText: "..."
    property string zramText: "..."
    property int rootDiskPct: 0
    property string rootDiskText: "..."
    property string trashSize: "0B"
    property string thumbSize: "0B"
    property string journalSize: "0B"
    property int failedUnits: 0

    // Dell G15 / Alienware WMI Fan & Thermal Telemetry
    property string thermalProfile: "balanced" // "balanced", "performance", "gmode"
    property int cpuTemp: 50
    property int gpuTemp: 45
    property int sodimmTemp: 42
    property int cpuFanRpm: 0
    property int gpuFanRpm: 0
    property int cpuFanMaxRpm: 4700
    property int gpuFanMaxRpm: 4400
    property int cpuFanBoost: 0
    property int gpuFanBoost: 0

    // Dual GPU Telemetry (AMD Radeon Vega iGPU + NVIDIA RTX 3050 dGPU)
    property string amdGpuName: "AMD Radeon Vega (iGPU)"
    property int amdGpuTemp: 48
    property string amdGpuClock: "400 MHz"
    property string amdGpuPower: "11 W"
    property string nvGpuName: "NVIDIA GeForce RTX 3050 Laptop"
    property string nvDriverVer: "620.70.06"
    property int nvGpuTemp: 46
    property int nvGpuUtil: 0
    property string nvGpuVram: "0 / 4096 MiB"
    property string nvGpuPower: "15 W"

    // Hyprland Live Tweaks (Single Source of Truth synced with hypr-vars.lua)
    property bool blurEnabled: true
    property bool shadowEnabled: true
    property int windowRounding: 20
    property int windowBorderSize: 1
    property int windowGapsIn: 2
    property int windowGapsOut: 2
    property real touchpadScrollFactor: 0.30

    // Screen Idle Timeouts (seconds, 0 = Never)
    property int lockTimeoutSec: 180
    property int screenOffTimeoutSec: 300
    property int sleepTimeoutSec: 600

    // Modes & Routines
    property string activeModeId: "standard"
    readonly property string activeModeName: {
        const m = root.modes.find(item => item.id === root.activeModeId);
        return m ? (m.nameEn || m.name) : "Balanced";
    }
    property string activeModeIcon: "balance"

    function t(viStr: string, enStr: string): string {
        return enStr || viStr;
    }

    function setLanguage(lang: string, syncSystemLocale: bool): void {
        root.uiLanguage = "en";
        Tr.language = "en_US";
        save();
        if (syncSystemLocale) {
            TaskRunner.run(
                "Set system locale (en_US.UTF-8)",
                "localectl set-locale LANG=en_US.UTF-8 && echo 'Updated /etc/locale.conf to LANG=en_US.UTF-8'",
                true,
                "language"
            );
        }
    }

    property list<var> modes: [
        {
            id: "standard",
            name: "Balanced",
            nameEn: "Balanced",
            icon: "balance",
            description: "Balanced power, quiet fans, and standard visual effects",
            descriptionEn: "Balanced power, quiet fans, and standard visual effects",
            powerProfile: "balanced",
            thermalMode: "balanced",
            gameMode: false,
            dnd: false,
            keepAwake: false,
            nightLight: false,
            nightLightTemp: 4500,
            eqPreset: "flat",
            volume: -1,
            launchCmd: ""
        },
        {
            id: "gaming",
            name: "Gaming & Turbo",
            nameEn: "Gaming & Turbo",
            icon: "sports_esports",
            description: "Max Performance power, G-Mode cooling, Hyprland FPS boost & Gaming EQ",
            descriptionEn: "Max Performance power, G-Mode cooling, Hyprland FPS boost & Gaming EQ",
            powerProfile: "performance",
            thermalMode: "performance",
            gameMode: true,
            dnd: true,
            keepAwake: true,
            nightLight: false,
            nightLightTemp: 4500,
            eqPreset: "gaming",
            volume: 85,
            launchCmd: ""
        },
        {
            id: "work",
            name: "Work & Focus",
            nameEn: "Work & Focus",
            icon: "work",
            description: "Do Not Disturb, 4500K eye comfort, Vocal EQ, and prevent screen sleep",
            descriptionEn: "Do Not Disturb, 4500K eye comfort, Vocal EQ, and prevent screen sleep",
            powerProfile: "balanced",
            thermalMode: "balanced",
            gameMode: false,
            dnd: true,
            keepAwake: true,
            nightLight: true,
            nightLightTemp: 4500,
            eqPreset: "vocal",
            volume: 50,
            launchCmd: ""
        },
        {
            id: "coding",
            name: "Developer",
            nameEn: "Developer",
            icon: "code",
            description: "High performance CPU, prevent idle sleep, gentle 4500K blue light filter",
            descriptionEn: "High performance CPU, prevent idle sleep, gentle 4500K blue light filter",
            powerProfile: "performance",
            thermalMode: "balanced",
            gameMode: false,
            dnd: false,
            keepAwake: true,
            nightLight: true,
            nightLightTemp: 4500,
            eqPreset: "flat",
            volume: 60,
            launchCmd: ""
        },
        {
            id: "cinema",
            name: "Cinema & Media",
            nameEn: "Cinema & Media",
            icon: "movie",
            description: "Cinema Surround EQ, keep screen awake, mute notifications",
            descriptionEn: "Cinema Surround EQ, keep screen awake, mute notifications",
            powerProfile: "balanced",
            thermalMode: "balanced",
            gameMode: false,
            dnd: true,
            keepAwake: true,
            nightLight: false,
            nightLightTemp: 4500,
            eqPreset: "cinema",
            volume: 80,
            launchCmd: ""
        },
        {
            id: "sleep",
            name: "Night & Battery Saver",
            nameEn: "Night & Battery Saver",
            icon: "bedtime",
            description: "Power Saver profile, warm 3500K Night Light, Do Not Disturb, quiet fans",
            descriptionEn: "Power Saver profile, warm 3500K Night Light, Do Not Disturb, quiet fans",
            powerProfile: "power-saver",
            thermalMode: "balanced",
            gameMode: false,
            dnd: true,
            keepAwake: false,
            nightLight: true,
            nightLightTemp: 3500,
            eqPreset: "flat",
            volume: 25,
            launchCmd: ""
        }
    ]

    property list<var> routines: [
        {
            id: "routine_night_sleep",
            name: "Night Eye Comfort & Power Saver",
            enabled: true,
            triggerType: "time",
            triggerValue: "22:00-06:00",
            triggerLabel: "22:00 – 06:00",
            matchMode: "time",
            revertOnExit: true,
            actionType: "mode",
            actionValue: "sleep",
            actionLabel: "Night & Battery Saver"
        },
        {
            id: "routine_auto_gaming",
            name: "Auto Gaming Mode on Steam / Games",
            enabled: true,
            triggerType: "process",
            triggerValue: "steam|steam_app_|gamescope|cs2|dota2",
            triggerLabel: "Window: steam, gamescope, cs2, dota2",
            matchMode: "window",
            revertOnExit: true,
            actionType: "mode",
            actionValue: "gaming",
            actionLabel: "Gaming & Turbo"
        },
        {
            id: "routine_auto_cinema",
            name: "Cinema Audio on MPV / VLC",
            enabled: false,
            triggerType: "process",
            triggerValue: "mpv|vlc",
            triggerLabel: "Window: mpv, vlc",
            matchMode: "window",
            revertOnExit: true,
            actionType: "mode",
            actionValue: "cinema",
            actionLabel: "Cinema & Media"
        },
        {
            id: "routine_auto_coding",
            name: "Developer Mode on VS Code / Zed",
            enabled: false,
            triggerType: "process",
            triggerValue: "code|nvim|zed",
            triggerLabel: "Window: code, nvim, zed",
            matchMode: "window",
            revertOnExit: true,
            actionType: "mode",
            actionValue: "coding",
            actionLabel: "Developer"
        }
    ]

    // Edge-triggered routine runtime tracking (prevents fighting manual overrides & handles auto-restore)
    property var routineRuntimeState: ({})
    property bool _internalRoutineSwitch: false

    readonly property var openWindowsList: {
        const list = [];
        const seen = {};
        const toplevels = Hypr.toplevels?.values ?? [];
        for (let i = 0; i < toplevels.length; i++) {
            const t = toplevels[i];
            const cls = String(t?.lastIpcObject?.class ?? "").trim();
            const ttl = String(t?.title ?? "").trim();
            if (!cls)
                continue;
            const key = cls.toLowerCase();
            if (!seen[key]) {
                seen[key] = true;
                list.push({ appClass: cls, title: ttl });
            }
        }
        return list;
    }

    onOpenWindowsListChanged: {
        if (loaded)
            windowEvalTimer.restart();
    }

    function refreshTelemetry(): void {
        OptimizerService.refreshTelemetry();
    }

    function runQuickOptimize(): void {
        OptimizerService.runDeepOptimize();
    }

    function setThermalMode(mode: string): void {
        OptimizerService.setThermalMode(mode);
    }

    function setFanBoost(cpuBoostVal: int, gpuBoostVal: int): void {
        OptimizerService.setFanBoost(cpuBoostVal, gpuBoostVal);
    }

    function saveHyprVars(): void {
        const lua = [
            "return {",
            `    blurEnabled = ${root.blurEnabled ? "true" : "false"},`,
            `    shadowEnabled = ${root.shadowEnabled ? "true" : "false"},`,
            `    windowRounding = ${root.windowRounding},`,
            `    windowBorderSize = ${root.windowBorderSize},`,
            `    windowGapsIn = ${root.windowGapsIn},`,
            `    windowGapsOut = ${root.windowGapsOut},`,
            `    touchpadScrollFactor = ${root.touchpadScrollFactor.toFixed(2)},`,
            "}",
            ""
        ].join("\n");
        hyprVarsFile.setText(lua);
    }

    function applyHyprKeyword(key: string, val: var): void {
        Quickshell.execDetached(["hyprctl", "keyword", key, String(val)]);
        saveHyprVars();
    }

    function updateIdleTimeout(kind: string, seconds: int): void {
        if (kind === "lock")
            root.lockTimeoutSec = seconds;
        else if (kind === "dpms")
            root.screenOffTimeoutSec = seconds;
        else if (kind === "sleep")
            root.sleepTimeoutSec = seconds;
        save();

        // Update GlobalConfig.general.idle.timeouts in-memory for immediate effect
        const list = GlobalConfig.general.idle.timeouts.values;
        for (let i = 0; i < list.length; i++) {
            const item = list[i];
            const act = String(item.idleAction);
            if (kind === "lock" && act === "lock") {
                item.enabled = seconds > 0;
                if (seconds > 0)
                    item.timeout = seconds;
            } else if (kind === "dpms" && act.includes("dpms")) {
                item.enabled = seconds > 0;
                if (seconds > 0)
                    item.timeout = seconds;
            } else if (kind === "sleep" && (act.includes("suspend") || act.includes("hibernate"))) {
                item.enabled = seconds > 0;
                if (seconds > 0)
                    item.timeout = seconds;
            }
        }
    }

    function save(): void {
        if (!loaded)
            return;
        saveTimer.restart();
    }

    onDesktopWeatherEnabledChanged: save()
    onDesktopWeatherDetailsChanged: save()
    onNightLightEnabledChanged: save()
    onNightLightTempChanged: save()
    onQuickDnsPresetChanged: save()
    onAutoOptimizeRamChanged: save()
    onBarCompactWindowChanged: save()
    onBarIconOnlyWindowChanged: save()
    onBarShowModesBtnChanged: save()
    onBarShowCareBtnChanged: save()
    onBarShowEqBtnChanged: save()

    function applyNightLight(enabled: bool, temp: int): void {
        root.nightLightEnabled = enabled;
        if (temp > 0)
            root.nightLightTemp = temp;

        if (enabled) {
            Quickshell.execDetached(["sh", "-c", `pkill -x gammastep 2>/dev/null; nohup gammastep -O ${root.nightLightTemp} </dev/null >/dev/null 2>&1 &`]);
        } else {
            Quickshell.execDetached(["sh", "-c", "pkill -x gammastep 2>/dev/null; gammastep -x >/dev/null 2>&1 || true"]);
        }
    }

    property bool _sleepSolidOverride: false
    property bool _sleepSavedTransparency: true

    function activateMode(modeId: string): void {
        const m = root.modes.find(item => item.id === modeId);
        if (!m)
            return;

        if (!root._internalRoutineSwitch) {
            const nextState = Object.assign({}, root.routineRuntimeState);
            let stateChanged = false;
            for (const rId in nextState) {
                const st = nextState[rId];
                if (st && st.active && st.actionValue !== modeId && !st.dismissed) {
                    nextState[rId] = Object.assign({}, st, { dismissed: true });
                    stateChanged = true;
                }
            }
            if (stateChanged)
                root.routineRuntimeState = nextState;
        }

        root.activeModeId = m.id;
        root.activeModeIcon = m.icon;

        if (m.powerProfile)
            root.setPowerProfile(String(m.powerProfile));
        if (m.thermalMode)
            root.setThermalMode(String(m.thermalMode));

        const wantGameMode = Boolean(m.gameMode);
        const wantSolidBattery = (m.id === "sleep");

        if (wantGameMode) {
            root._sleepSolidOverride = false;
            GameMode.enabled = true;
        } else {
            GameMode.enabled = false;
            if (wantSolidBattery) {
                if (!root._sleepSolidOverride) {
                    root._sleepSavedTransparency = GlobalConfig.appearance.transparency.enabled;
                    root._sleepSolidOverride = true;
                }
                GlobalConfig.appearance.transparency.enabled = false;
                root.applyHyprKeyword("decoration:blur:enabled", "false");
            } else if (root._sleepSolidOverride) {
                GlobalConfig.appearance.transparency.enabled = root._sleepSavedTransparency;
                root._sleepSolidOverride = false;
                root.applyHyprKeyword("decoration:blur:enabled", root.blurEnabled ? "true" : "false");
            }
        }

        Notifs.dnd = Boolean(m.dnd);
        IdleInhibitor.enabled = Boolean(m.keepAwake);
        applyNightLight(Boolean(m.nightLight), Number(m.nightLightTemp) || 4500);

        if (m.eqPreset) {
            EqualizerService.selectPreset(String(m.eqPreset));
        }
        if (m.volume !== undefined && Number(m.volume) >= 0) {
            Audio.setVolume(Number(m.volume) / 100.0);
        }
        if (m.launchCmd && String(m.launchCmd).trim().length > 0) {
            Quickshell.execDetached(["bash", "-c", String(m.launchCmd).trim()]);
        }

        const tags = [];
        if (m.powerProfile === "performance")
            tags.push("Max Speed");
        else if (m.powerProfile === "power-saver")
            tags.push("Power Saver");
        else
            tags.push("Balanced");
        if (m.gameMode)
            tags.push("Solid Game UI");
        if (m.eqPreset)
            tags.push(`EQ: ${m.eqPreset}`);
        root.modeOsdSubtitle = tags.join(" • ");
        if (root.loaded) {
            root.modeOsdVisible = true;
            modeOsdTimer.restart();
            root.modeOsdTriggered();
        }

        if (root.liquidGlassEnabled && !wantGameMode && !wantSolidBattery)
            Qt.callLater(() => applyLiquidGlassBlur(true));

        save();
    }

    function applyLiquidGlassBlur(enabled: bool): void {
        if (enabled && !GameMode.enabled && !root._sleepSolidOverride) {
            Hypr.extras.applyOptions({
                "decoration:blur:enabled": 1,
                "decoration:blur:size": 16,
                "decoration:blur:passes": 4,
                "decoration:blur:vibrancy": 0.36,
                "decoration:blur:vibrancy_darkness": 0.18,
                "decoration:blur:contrast": 1.07,
                "decoration:blur:brightness": 1.05,
                "decoration:blur:noise": 0.006,
                "decoration:blur:popups": 1
            });
        } else if (!GameMode.enabled && !root._sleepSolidOverride) {
            Hypr.extras.applyOptions({
                "decoration:blur:size": 8,
                "decoration:blur:passes": 2,
                "decoration:blur:vibrancy": 0.1696,
                "decoration:blur:vibrancy_darkness": 0.0,
                "decoration:blur:contrast": 1.0,
                "decoration:blur:brightness": 1.0,
                "decoration:blur:noise": 0.0117
            });
        }
    }

    function setLiquidGlass(enabled: bool): void {
        root.liquidGlassEnabled = enabled;
        if (enabled) {
            if (!GameMode.enabled && !root._sleepSolidOverride)
                GlobalConfig.appearance.transparency.enabled = true;
            applyLiquidGlassBlur(true);
        } else {
            applyLiquidGlassBlur(false);
        }
        save();
    }

    function cycleMode(): void {
        const ids = root.modes.map(m => m.id);
        const curIdx = ids.indexOf(root.activeModeId);
        const nextIdx = (curIdx + 1) % ids.length;
        activateMode(ids[nextIdx]);
    }

    function updateModeProperty(modeId: string, propName: string, propVal: var): void {
        const nextModes = [];
        for (let i = 0; i < root.modes.length; i++) {
            const copy = Object.assign({}, root.modes[i]);
            if (copy.id === modeId) {
                copy[propName] = propVal;
            }
            nextModes.push(copy);
        }
        root.modes = nextModes;
        if (root.activeModeId === modeId) {
            activateMode(modeId);
        } else {
            save();
        }
    }

    function setRoutineEnabled(routineId: string, on: bool): void {
        const nextRoutines = [];
        for (let i = 0; i < root.routines.length; i++) {
            const copy = Object.assign({}, root.routines[i]);
            if (copy.id === routineId) {
                copy.enabled = on;
            }
            nextRoutines.push(copy);
        }
        root.routines = nextRoutines;
        if (!on) {
            const st = root.routineRuntimeState[routineId];
            if (st && st.active && !st.dismissed && st.actionValue === root.activeModeId) {
                root._internalRoutineSwitch = true;
                root.activateMode(st.prevModeId || "standard");
                root._internalRoutineSwitch = false;
            }
            const nextState = Object.assign({}, root.routineRuntimeState);
            delete nextState[routineId];
            root.routineRuntimeState = nextState;
        } else {
            Qt.callLater(evaluateAllRoutines);
        }
        save();
    }

    function updateRoutineProperty(routineId: string, propName: string, propVal: var): void {
        const nextRoutines = [];
        for (let i = 0; i < root.routines.length; i++) {
            const copy = Object.assign({}, root.routines[i]);
            if (copy.id === routineId) {
                copy[propName] = propVal;
            }
            nextRoutines.push(copy);
        }
        root.routines = nextRoutines;
        save();
        Qt.callLater(evaluateAllRoutines);
    }

    function getRoutineStatus(routineId: string): string {
        const st = root.routineRuntimeState[routineId];
        if (!st || !st.active)
            return "idle";
        return st.dismissed ? "dismissed" : "active";
    }

    function resumeRoutine(routineId: string): void {
        const nextState = Object.assign({}, root.routineRuntimeState);
        delete nextState[routineId];
        root.routineRuntimeState = nextState;
        Qt.callLater(evaluateAllRoutines);
    }

    function addRoutine(name: string, triggerType: string, triggerValue: string, triggerLabel: string, actionType: string, actionValue: string, actionLabel: string, matchMode = "window", revertOnExit = true): void {
        const next = root.routines.slice();
        next.push({
            id: "routine_" + Date.now(),
            name: name || "Custom Routine",
            enabled: true,
            triggerType: triggerType,
            triggerValue: triggerValue,
            triggerLabel: triggerLabel,
            matchMode: matchMode,
            revertOnExit: revertOnExit,
            actionType: actionType,
            actionValue: actionValue,
            actionLabel: actionLabel
        });
        root.routines = next;
        save();
        Qt.callLater(evaluateAllRoutines);
    }

    function removeRoutine(routineId: string): void {
        const nextState = Object.assign({}, root.routineRuntimeState);
        delete nextState[routineId];
        root.routineRuntimeState = nextState;
        root.routines = root.routines.filter(r => r.id !== routineId);
        save();
    }

    function executeRoutineAction(r: var): void {
        if (r.actionType === "mode") {
            if (root.activeModeId !== r.actionValue) {
                root._internalRoutineSwitch = true;
                root.activateMode(r.actionValue);
                root._internalRoutineSwitch = false;
            }
        } else if (r.actionType === "command") {
            Quickshell.execDetached(["bash", "-c", r.actionValue]);
        } else if (r.actionType === "nightlight") {
            if (!root.nightLightEnabled)
                root.applyNightLight(true, 4000);
        } else if (r.actionType === "dnd") {
            Notifs.dnd = true;
        }
    }

    function _handleRoutineEvaluation(r: var, isMatched: bool, matchedBy = ""): void {
        const nextState = Object.assign({}, root.routineRuntimeState);
        const st = nextState[r.id];

        if (isMatched) {
            if (!st || !st.active) {
                const prevId = (root.activeModeId && root.activeModeId !== r.actionValue) ? root.activeModeId : "standard";
                nextState[r.id] = {
                    active: true,
                    dismissed: false,
                    prevModeId: prevId,
                    actionValue: r.actionValue,
                    matchedBy: matchedBy
                };
                root.routineRuntimeState = nextState;
                root.executeRoutineAction(r);
            }
        } else if (st && st.active) {
            const shouldRevert = (r.revertOnExit !== false) && !st.dismissed && r.actionType === "mode" && root.activeModeId === r.actionValue;
            const restoreId = st.prevModeId || "standard";
            delete nextState[r.id];
            root.routineRuntimeState = nextState;
            if (shouldRevert) {
                root._internalRoutineSwitch = true;
                root.activateMode(restoreId);
                root._internalRoutineSwitch = false;
            }
        }
    }

    function evaluateWindowRoutines(): void {
        if (!root.loaded)
            return;
        const wins = root.openWindowsList;
        for (let i = 0; i < root.routines.length; i++) {
            const r = root.routines[i];
            if (!r.enabled || r.triggerType !== "process")
                continue;
            const mode = r.matchMode || "window";
            if (mode !== "window")
                continue;
            const patterns = String(r.triggerValue).toLowerCase().split("|").map(s => s.trim()).filter(Boolean);
            let matchedWin = "";
            const isMatched = wins.some(w => {
                const cls = w.appClass.toLowerCase();
                const ttl = w.title.toLowerCase();
                const hit = patterns.some(pat => cls === pat || cls.includes(pat) || ttl.includes(pat));
                if (hit)
                    matchedWin = w.appClass;
                return hit;
            });
            root._handleRoutineEvaluation(r, isMatched, matchedWin);
        }
    }

    function evaluateAllRoutines(): void {
        if (!root.loaded)
            return;
        const now = new Date();
        const curMins = now.getHours() * 60 + now.getMinutes();

        for (let i = 0; i < root.routines.length; i++) {
            const r = root.routines[i];
            if (!r.enabled)
                continue;

            if (r.triggerType === "time") {
                const parts = String(r.triggerValue).split("-");
                if (parts.length === 2) {
                    const s = parts[0].split(":");
                    const e = parts[1].split(":");
                    const startMins = (parseInt(s[0], 10) || 0) * 60 + (parseInt(s[1], 10) || 0);
                    const endMins = (parseInt(e[0], 10) || 0) * 60 + (parseInt(e[1], 10) || 0);
                    const inRange = startMins <= endMins
                        ? (curMins >= startMins && curMins <= endMins)
                        : (curMins >= startMins || curMins <= endMins);
                    root._handleRoutineEvaluation(r, inRange, r.triggerValue);
                }
            } else if (r.triggerType === "wifi") {
                const currentSsid = Nmcli.active?.ssid ?? "";
                const matched = currentSsid.length > 0 && currentSsid.toLowerCase().includes(String(r.triggerValue).toLowerCase());
                root._handleRoutineEvaluation(r, matched, currentSsid);
            }
        }

        evaluateWindowRoutines();

        const bgProcRoutines = root.routines.filter(r => r.enabled && r.triggerType === "process" && r.matchMode === "process");
        if (bgProcRoutines.length > 0 && !procRoutineChecker.running) {
            procRoutineChecker.running = true;
        }
    }

    Process {
        id: quickOptProc

        command: ["sh", "-c", "sync; pkexec sh -c 'echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null || true; rm -rf ~/.cache/thumbnails/* 2>/dev/null || true; systemctl --user reset-failed 2>/dev/null || true; sleep 0.4"]
        onExited: {
            root.optimizingNow = false;
            root.optimizeStatusText = "Memory cache released, thumbnails cleaned & services verified";
            root.refreshTelemetry();
        }
    }

    Process {
        id: telemetryProc

        command: ["python3", "-c", `
import subprocess, glob, os, json

def read_file(p, default=""):
    try:
        return open(p).read().strip()
    except Exception:
        return default

def sh(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""

out = {}
# RAM & ZRAM
mem = sh("free -m | awk '/Mem:/ {printf \"%d|%s / %s MB\", int($3*100/$2), $3, $2}'")
if "|" in mem:
    p = mem.split("|")
    out["ramPct"] = int(p[0])
    out["ramUsageText"] = p[1]
out["zramText"] = sh("free -m | awk '/Swap:/ {printf \"%s / %s MB\", $3, $2}'")

# Root disk
disk = sh("df -h / | awk 'NR==2 {gsub(/%/,\"\",$5); printf \"%s|%s / %s (%s%%)\", $5, $3, $2, $5}'")
if "|" in disk:
    p = disk.split("|")
    out["rootDiskPct"] = int(p[0])
    out["rootDiskText"] = p[1]

out["thumbSize"] = sh("du -sh ~/.cache/thumbnails 2>/dev/null | cut -f1") or "0B"
out["trashSize"] = sh("du -sh ~/.local/share/Trash 2>/dev/null | cut -f1") or "0B"
out["journalSize"] = sh("du -sh /var/log/journal 2>/dev/null | cut -f1") or "0B"
out["failedUnits"] = int(sh("systemctl --failed --no-legend 2>/dev/null | wc -l") or "0")

# Platform profile & hwmon (alienware_wmi, dell_smm, amdgpu, k10temp)
out["platformProfile"] = read_file("/sys/firmware/acpi/platform_profile", "balanced")
for h in glob.glob("/sys/class/hwmon/hwmon*"):
    name = read_file(os.path.join(h, "name"))
    if name == "alienware_wmi":
        out["cpuFanRpm"] = int(read_file(os.path.join(h, "fan1_input"), "0") or 0)
        out["gpuFanRpm"] = int(read_file(os.path.join(h, "fan2_input"), "0") or 0)
        out["cpuFanMax"] = int(read_file(os.path.join(h, "fan1_max"), "4700") or 4700)
        out["gpuFanMax"] = int(read_file(os.path.join(h, "fan2_max"), "4400") or 4400)
        out["cpuFanBoost"] = int(read_file(os.path.join(h, "fan1_boost"), "0") or 0)
        out["gpuFanBoost"] = int(read_file(os.path.join(h, "fan2_boost"), "0") or 0)
        t1 = int(read_file(os.path.join(h, "temp1_input"), "0") or 0)
        if t1 > 0:
            out["cpuTemp"] = t1 // 1000 if t1 > 200 else t1
    elif name == "dell_smm":
        t3 = int(read_file(os.path.join(h, "temp3_input"), "0") or 0)
        if t3 > 0:
            out["sodimmTemp"] = t3 // 1000 if t3 > 200 else t3
    elif name == "k10temp":
        t1 = int(read_file(os.path.join(h, "temp1_input"), "0") or 0)
        if t1 > 0:
            out["cpuTemp"] = t1 // 1000
    elif name == "amdgpu":
        t1 = int(read_file(os.path.join(h, "temp1_input"), "0") or 0)
        if t1 > 0:
            out["amdGpuTemp"] = t1 // 1000
        freq = int(read_file(os.path.join(h, "freq1_input"), "0") or 0)
        if freq > 0:
            out["amdGpuClock"] = f"{freq // 1000000} MHz"
        ppt = int(read_file(os.path.join(h, "power1_average"), "0") or 0)
        if ppt > 0:
            out["amdGpuPower"] = f"{ppt / 1000000:.1f} W"

# NVIDIA dGPU
nv = sh("nvidia-smi --query-gpu=name,driver_version,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw --format=csv,noheader,nounits")
if nv and "," in nv:
    parts = [x.strip() for x in nv.split(",")]
    if len(parts) >= 7:
        out["nvGpuName"] = parts[0]
        out["nvDriverVer"] = parts[1]
        out["nvGpuTemp"] = int(float(parts[2] or 0))
        out["nvGpuUtil"] = int(float(parts[3] or 0))
        out["nvGpuVram"] = f"{parts[4]} / {parts[5]} MiB"
        out["nvGpuPower"] = f"{float(parts[6] or 0):.1f} W"
        out["gpuTemp"] = out["nvGpuTemp"]

print(json.dumps(out))
`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim());
                    if (d.ramPct !== undefined) root.ramPct = d.ramPct;
                    if (d.ramUsageText) root.ramUsageText = d.ramUsageText;
                    if (d.zramText) root.zramText = d.zramText;
                    if (d.rootDiskPct !== undefined) root.rootDiskPct = d.rootDiskPct;
                    if (d.rootDiskText) root.rootDiskText = d.rootDiskText;
                    if (d.thumbSize) root.thumbSize = d.thumbSize;
                    if (d.trashSize) root.trashSize = d.trashSize;
                    if (d.journalSize) root.journalSize = d.journalSize;
                    if (d.failedUnits !== undefined) root.failedUnits = d.failedUnits;
                    if (d.cpuTemp !== undefined) root.cpuTemp = d.cpuTemp;
                    if (d.gpuTemp !== undefined) root.gpuTemp = d.gpuTemp;
                    if (d.sodimmTemp !== undefined) root.sodimmTemp = d.sodimmTemp;
                    if (d.cpuFanRpm !== undefined) root.cpuFanRpm = d.cpuFanRpm;
                    if (d.gpuFanRpm !== undefined) root.gpuFanRpm = d.gpuFanRpm;
                    if (d.cpuFanMax !== undefined) root.cpuFanMaxRpm = d.cpuFanMax;
                    if (d.gpuFanMax !== undefined) root.gpuFanMaxRpm = d.gpuFanMax;
                    if (d.cpuFanBoost !== undefined) root.cpuFanBoost = d.cpuFanBoost;
                    if (d.gpuFanBoost !== undefined) root.gpuFanBoost = d.gpuFanBoost;
                    if (d.platformProfile) {
                        root.thermalProfile = (d.cpuFanBoost >= 80 && d.platformProfile === "performance") ? "gmode" : d.platformProfile;
                    }
                    if (d.amdGpuTemp !== undefined) root.amdGpuTemp = d.amdGpuTemp;
                    if (d.amdGpuClock) root.amdGpuClock = d.amdGpuClock;
                    if (d.amdGpuPower) root.amdGpuPower = d.amdGpuPower;
                    if (d.nvGpuName) root.nvGpuName = d.nvGpuName;
                    if (d.nvDriverVer) root.nvDriverVer = d.nvDriverVer;
                    if (d.nvGpuTemp !== undefined) root.nvGpuTemp = d.nvGpuTemp;
                    if (d.nvGpuUtil !== undefined) root.nvGpuUtil = d.nvGpuUtil;
                    if (d.nvGpuVram) root.nvGpuVram = d.nvGpuVram;
                    if (d.nvGpuPower) root.nvGpuPower = d.nvGpuPower;

                    let score = 100;
                    if (root.ramPct > 85) score -= 12;
                    else if (root.ramPct > 70) score -= 4;
                    if (root.rootDiskPct > 90) score -= 15;
                    else if (root.rootDiskPct > 80) score -= 5;
                    if (root.failedUnits > 0) score -= Math.min(15, root.failedUnits * 5);
                    if (root.cpuTemp > 85) score -= 6;
                    root.healthScore = Math.max(60, Math.min(100, score));
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 30000
        running: false
        repeat: false
        onTriggered: root.refreshTelemetry()
    }

    FileView {
        id: hyprVarsFile

        printErrors: false
        path: `${Paths.config}/hypr-vars.lua`
        onLoaded: {
            const t = text();
            const mBlur = t.match(/blurEnabled\s*=\s*(true|false)/);
            if (mBlur) root.blurEnabled = mBlur[1] === "true";
            const mShadow = t.match(/shadowEnabled\s*=\s*(true|false)/);
            if (mShadow) root.shadowEnabled = mShadow[1] === "true";
            const mRound = t.match(/windowRounding\s*=\s*(\d+)/);
            if (mRound) root.windowRounding = parseInt(mRound[1], 10);
            const mBorder = t.match(/windowBorderSize\s*=\s*(\d+)/);
            if (mBorder) root.windowBorderSize = parseInt(mBorder[1], 10);
            const mIn = t.match(/windowGapsIn\s*=\s*(\d+)/) || t.match(/gapsIn\s*=\s*(\d+)/);
            if (mIn) root.windowGapsIn = parseInt(mIn[1], 10);
            const mOut = t.match(/windowGapsOut\s*=\s*(\d+)/) || t.match(/gapsOut\s*=\s*(\d+)/);
            if (mOut) root.windowGapsOut = parseInt(mOut[1], 10);
            const mScroll = t.match(/touchpadScrollFactor\s*=\s*([\d.]+)/);
            if (mScroll) root.touchpadScrollFactor = parseFloat(mScroll[1]);
        }
    }

    Timer {
        id: modeOsdTimer

        interval: 2600
        onTriggered: root.modeOsdVisible = false
    }

    Timer {
        id: windowEvalTimer

        interval: 250
        onTriggered: root.evaluateWindowRoutines()
    }

    Connections {
        target: GameMode

        function onEnabledChanged(): void {
            if (!GameMode.enabled && !root._internalRoutineSwitch) {
                const nextState = Object.assign({}, root.routineRuntimeState);
                let changed = false;
                for (const rId in nextState) {
                    const st = nextState[rId];
                    if (st && st.active && st.actionValue === "gaming" && !st.dismissed) {
                        nextState[rId] = Object.assign({}, st, { dismissed: true });
                        changed = true;
                    }
                }
                if (changed)
                    root.routineRuntimeState = nextState;
            }
        }
    }

    Timer {
        id: routineCheckTimer

        interval: 15000
        running: root.loaded
        repeat: true
        triggeredOnStart: true
        onTriggered: root.evaluateAllRoutines()
    }

    Process {
        id: procRoutineChecker

        command: ["ps", "-eo", "comm="]
        stdout: StdioCollector {
            onStreamFinished: {
                const runningProcs = text.toLowerCase().split("\n").map(s => s.trim());
                for (let i = 0; i < root.routines.length; i++) {
                    const r = root.routines[i];
                    if (!r.enabled || r.triggerType !== "process" || (r.matchMode || "window") !== "process")
                        continue;
                    const patterns = String(r.triggerValue).toLowerCase().split("|").map(s => s.trim()).filter(Boolean);
                    let matchedProc = "";
                    const matched = patterns.some(pat => {
                        const hit = runningProcs.find(p => p === pat || p.includes(pat));
                        if (hit)
                            matchedProc = hit;
                        return Boolean(hit);
                    });
                    root._handleRoutineEvaluation(r, matched, matchedProc);
                }
            }
        }
    }

    Timer {
        id: saveTimer

        interval: 300
        onTriggered: {
            const data = {
                uiLanguage: "en",
                desktopWeatherEnabled: root.desktopWeatherEnabled,
                desktopWeatherDetails: root.desktopWeatherDetails,
                nightLightEnabled: root.nightLightEnabled,
                nightLightTemp: root.nightLightTemp,
                quickDnsPreset: root.quickDnsPreset,
                autoOptimizeRam: root.autoOptimizeRam,
                liquidGlassEnabled: root.liquidGlassEnabled,
                liquidGlassIntensity: root.liquidGlassIntensity,
                liquidGlassAnimate: root.liquidGlassAnimate,
                barCompactWindow: root.barCompactWindow,
                barIconOnlyWindow: root.barIconOnlyWindow,
                barShowModesBtn: root.barShowModesBtn,
                barShowCareBtn: root.barShowCareBtn,
                barShowEqBtn: root.barShowEqBtn,
                lockTimeoutSec: root.lockTimeoutSec,
                screenOffTimeoutSec: root.screenOffTimeoutSec,
                sleepTimeoutSec: root.sleepTimeoutSec,
                activeModeId: root.activeModeId,
                modes: root.modes,
                routines: root.routines
            };
            storage.setText(JSON.stringify(data, null, 4));
        }
    }

    FileView {
        id: storage

        printErrors: false
        path: `${Paths.config}/extra.json`
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.uiLanguage = "en";
                if (data.desktopWeatherEnabled !== undefined)
                    root.desktopWeatherEnabled = Boolean(data.desktopWeatherEnabled);
                if (data.desktopWeatherDetails !== undefined)
                    root.desktopWeatherDetails = Boolean(data.desktopWeatherDetails);
                if (data.nightLightEnabled !== undefined)
                    root.nightLightEnabled = Boolean(data.nightLightEnabled);
                if (data.nightLightTemp !== undefined)
                    root.nightLightTemp = Number(data.nightLightTemp) || 4500;
                if (data.quickDnsPreset !== undefined)
                    root.quickDnsPreset = String(data.quickDnsPreset);
                if (data.autoOptimizeRam !== undefined)
                    root.autoOptimizeRam = Boolean(data.autoOptimizeRam);
                if (data.liquidGlassEnabled !== undefined)
                    root.liquidGlassEnabled = Boolean(data.liquidGlassEnabled);
                if (data.liquidGlassIntensity !== undefined)
                    root.liquidGlassIntensity = Math.max(0.2, Math.min(1.0, Number(data.liquidGlassIntensity) || 0.72));
                if (data.liquidGlassAnimate !== undefined)
                    root.liquidGlassAnimate = Boolean(data.liquidGlassAnimate);
                if (data.barCompactWindow !== undefined)
                    root.barCompactWindow = Boolean(data.barCompactWindow);
                if (data.barIconOnlyWindow !== undefined)
                    root.barIconOnlyWindow = Boolean(data.barIconOnlyWindow);
                if (data.barShowModesBtn !== undefined)
                    root.barShowModesBtn = Boolean(data.barShowModesBtn);
                if (data.barShowCareBtn !== undefined)
                    root.barShowCareBtn = Boolean(data.barShowCareBtn);
                if (data.barShowEqBtn !== undefined)
                    root.barShowEqBtn = Boolean(data.barShowEqBtn);
                if (data.lockTimeoutSec !== undefined)
                    root.lockTimeoutSec = Number(data.lockTimeoutSec);
                if (data.screenOffTimeoutSec !== undefined)
                    root.screenOffTimeoutSec = Number(data.screenOffTimeoutSec);
                if (data.sleepTimeoutSec !== undefined)
                    root.sleepTimeoutSec = Number(data.sleepTimeoutSec);
                if (Array.isArray(data.modes) && data.modes.length > 0) {
                    const merged = [];
                    for (let i = 0; i < root.modes.length; i++) {
                        const defM = root.modes[i];
                        const savedM = data.modes.find(x => x.id === defM.id);
                        merged.push(savedM ? Object.assign({}, defM, savedM, {
                            name: defM.name,
                            nameEn: defM.nameEn,
                            description: defM.description,
                            descriptionEn: defM.descriptionEn
                        }) : defM);
                    }
                    root.modes = merged;
                }
                if (Array.isArray(data.routines) && data.routines.length > 0) {
                    const mergedR = [];
                    for (let i = 0; i < data.routines.length; i++) {
                        const savedR = data.routines[i];
                        const defR = root.routines.find(x => x.id === savedR.id);
                        mergedR.push(defR ? Object.assign({}, defR, savedR, {
                            name: defR.name,
                            triggerLabel: defR.triggerLabel,
                            actionLabel: defR.actionLabel,
                            matchMode: defR.matchMode,
                            revertOnExit: savedR.revertOnExit !== undefined ? Boolean(savedR.revertOnExit) : defR.revertOnExit
                        }) : Object.assign({
                            matchMode: "window",
                            revertOnExit: true
                        }, savedR));
                    }
                    root.routines = mergedR;
                }
                if (data.activeModeId) {
                    root.activeModeId = String(data.activeModeId);
                    const m = root.modes.find(item => item.id === root.activeModeId);
                    if (m)
                        root.activeModeIcon = m.icon;
                }
            } catch (e) {}
            root.loaded = true;
            if (root.liquidGlassEnabled && !GameMode.enabled)
                Qt.callLater(() => root.applyLiquidGlassBlur(true));
            Qt.callLater(() => saveTimer.restart());
        }
        onLoadFailed: err => {
            root.loaded = true;
            if (err === FileViewError.FileNotFound) {
                Qt.callLater(() => saveTimer.restart());
            }
        }
    }
}
