pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.utils

Singleton {
    id: root

    // Persisted Preferences (optimizer.json)
    property bool loaded: false
    property bool showDashboardTab: true
    property bool smartCoolEnabled: true
    property bool cleanPacman: true
    property bool cleanTrim: true
    property bool cleanTrash: false
    property int autoRamThreshold: 0 // 0 = Disabled, 85, 90
    property int _autoCoolLevel: 0 // 0 = EC Auto, 1 = whisper (45), 2 = medium (72)
    property string preferredScxSched: "lavd"
    property string preferredScxMode: "Auto"
    property int lastReclaimedMiB: 0
    property int lastDiskFreedMiB: 0
    property string lastOptimizedTime: ""

    // Live Hardware & System Telemetry (Single Source of Truth)
    property int healthScore: 95
    property string healthLabel: "Great"

    property int ramPct: 0
    property string ramUsageText: "..."
    property string ramFreeText: "..."
    property string zramText: "0 MiB / 15 GiB"
    property int rootDiskPct: 0
    property string rootDiskText: "..."

    property bool cpuTurboEnabled: true
    property string cpuGov: "powersave"
    property string cpuEpp: "balance_performance"
    property int cpuTemp: 0
    property int gpuTemp: 0
    property int amdGpuTemp: 0
    property int sodimmTemp: 0
    property int nvGpuUtil: 0
    property string nvGpuPower: "0 W"
    property string nvGpuVram: "0 / 4096 MiB"

    // Dell G15 / Alienware WMI Cooling & Thermal
    property string platformProfile: "balanced"
    property string thermalProfile: "balanced" // "balanced" | "performance" | "gmode"
    property int cpuFanRpm: 0
    property int gpuFanRpm: 0
    property int cpuFanMaxRpm: 4700
    property int gpuFanMaxRpm: 4400
    property int cpuFanBoost: 0
    property int gpuFanBoost: 0

    // CachyOS Sched-ext (scx_loader / scxctl)
    property string scxSched: "eevdf" // "eevdf" | "lavd" | "bpfland" | "cosmos" | "rusty"
    property string scxMode: "Default" // "Default" | "Auto" | "Gaming" | "LowLatency" | "PowerSave"
    property bool scxBootEnabled: false
    property bool scxBusy: false

    // NVMe I/O Scheduler
    property string ioScheduler: "kyber"
    property var ioAvailable: ["kyber", "none", "mq-deadline", "adios"]

    // Active Services & Cleanables
    property bool svcAnanicy: false
    property bool svcOomd: false
    property bool svcPowerd: false
    property bool svcScx: false
    property bool svcNvidia: false
    property bool svcFstrim: false
    property int failedUnits: 0

    property string thumbSize: "0 MiB"
    property string trashSize: "0 MiB"
    property string pacmanCacheSize: "0 GiB"
    property string journalSize: "0M"
    property var topProcesses: []

    // Optimization Progress State
    property bool optimizingNow: false
    property real optimizeProgress: 0
    property string optimizeStageText: ""
    property string optimizeStatusText: "System running smoothly"
    property double _lastAutoOptMs: 0
    property int _pendingCpuBoost: -1
    property int _pendingGpuBoost: -1

    // PowerProfiles SSOT helpers
    readonly property int currentPowerProfile: PowerProfiles.profile
    readonly property string powerProfileId: {
        if (currentPowerProfile === PowerProfile.Performance)
            return "performance";
        if (currentPowerProfile === PowerProfile.PowerSaver)
            return "power-saver";
        return "balanced";
    }
    readonly property string powerProfileName: {
        if (currentPowerProfile === PowerProfile.Performance)
            return "Performance";
        if (currentPowerProfile === PowerProfile.PowerSaver)
            return "Power Saver";
        return "Balanced";
    }
    readonly property string powerProfileIcon: {
        if (currentPowerProfile === PowerProfile.Performance)
            return "speed";
        if (currentPowerProfile === PowerProfile.PowerSaver)
            return "battery_saver";
        return "balance";
    }

    readonly property string smartPresetId: {
        if (currentPowerProfile === PowerProfile.PowerSaver)
            return "saver";
        if (currentPowerProfile === PowerProfile.Performance)
            return "gaming";
        return "balanced";
    }
    readonly property bool protectionActive: svcAnanicy && svcOomd && svcPowerd && svcFstrim

    function _formatKib(kib: real): string {
        if (kib >= 1048576)
            return `${(kib / 1048576).toFixed(1)} GiB`;
        if (kib >= 1024)
            return `${Math.round(kib / 1024)} MiB`;
        return `${Math.round(kib)} KiB`;
    }

    function _formatBytes(b: real): string {
        if (b >= 1073741824)
            return `${(b / 1073741824).toFixed(1)} GiB`;
        if (b >= 1048576)
            return `${(b / 1048576).toFixed(1)} MiB`;
        if (b >= 1024)
            return `${Math.round(b / 1024)} KiB`;
        return `${Math.round(b)} B`;
    }

    function _recomputeHealth(): void {
        let score = 100;
        if (ramPct > 85)
            score -= 18;
        else if (ramPct > 72)
            score -= 8;

        const maxTemp = Math.max(cpuTemp, gpuTemp);
        if (maxTemp > 90)
            score -= 20;
        else if (maxTemp > 80)
            score -= 10;

        if (rootDiskPct > 90)
            score -= 15;
        else if (rootDiskPct > 82)
            score -= 6;

        if (failedUnits > 0)
            score -= Math.min(10, failedUnits * 5);

        if (!svcAnanicy)
            score -= 4;

        healthScore = Math.max(40, Math.min(100, score));
        if (healthScore >= 90)
            healthLabel = "Great";
        else if (healthScore >= 75)
            healthLabel = "Good";
        else
            healthLabel = "Fair";
    }

    onPowerProfileIdChanged: {
        if (loaded)
            powerTuneTimer.restart();
    }

    function applySmartPreset(preset: string): void {
        if (preset === "saver") {
            _autoCoolLevel = 0;
            setPowerProfile("power-saver");
            setThermalMode("power-saver");
            setScxScheduler("bpfland", "PowerSave");
            ExtraConfig.syncModeFromPreset("sleep");
        } else if (preset === "gaming") {
            _autoCoolLevel = 0;
            setPowerProfile("performance");
            if (!cpuTurboEnabled)
                setCpuTurbo(true);
            setThermalMode("performance");
            setScxScheduler("lavd", "Gaming");
            ExtraConfig.syncModeFromPreset("gaming");
        } else {
            setPowerProfile("balanced");
            setThermalMode("balanced");
            setScxScheduler(preferredScxSched || "cosmos", preferredScxMode || "Auto");
            ExtraConfig.syncModeFromPreset("standard");
        }
    }

    function toggleMaxCooling(enableGmode: bool): void {
        if (enableGmode) {
            setThermalMode("gmode");
        } else {
            setThermalMode(powerProfileId === "performance" ? "performance" : "balanced");
        }
    }

    function setPowerProfile(prof: string): void {
        if (prof === "performance")
            PowerProfiles.profile = PowerProfile.Performance;
        else if (prof === "power-saver")
            PowerProfiles.profile = PowerProfile.PowerSaver;
        else
            PowerProfiles.profile = PowerProfile.Balanced;
        Qt.callLater(refreshTelemetry);
    }

    function cyclePowerProfile(): void {
        if (powerProfileId === "balanced")
            setPowerProfile("performance");
        else if (powerProfileId === "performance")
            setPowerProfile("power-saver");
        else
            setPowerProfile("balanced");
    }

    function refreshTelemetry(): void {
        if (!telemetryProc.running)
            telemetryProc.running = true;
    }

    function runDeepOptimize(): void {
        if (optimizingNow)
            return;
        optimizingNow = true;
        optimizeProgress = 0.05;
        optimizeStageText = "Starting deep optimization...";
        optimizeStatusText = "Optimizing system...";

        const args = ["pkexec", "/usr/local/bin/caelestia-optimize", "deep-optimize", `--user-home=${Quickshell.env("HOME")}`];
        if (cleanPacman)
            args.push("--pacman");
        if (cleanTrim)
            args.push("--trim");
        if (cleanTrash)
            args.push("--trash");

        optimizeProc.command = args;
        optimizeProc.running = true;
    }

    function setThermalMode(mode: string): void {
        thermalProfile = mode;
        _autoCoolLevel = 0;
        const cmd = ["pkexec", "/usr/local/bin/caelestia-optimize", "thermal", mode];
        if (mode === "performance") {
            cmd.push(String(cpuFanBoost));
            cmd.push(String(gpuFanBoost));
        } else if (mode === "balanced") {
            cmd.push("0");
            cmd.push("0");
            cmd.push(smartCoolEnabled ? "1" : "0");
        }
        actionProc.command = cmd;
        actionProc.running = true;
    }

    function setFanBoost(cpuVal: int, gpuVal: int): void {
        cpuFanBoost = Math.max(0, Math.min(100, cpuVal));
        gpuFanBoost = Math.max(0, Math.min(100, gpuVal));
        _pendingCpuBoost = cpuFanBoost;
        _pendingGpuBoost = gpuFanBoost;
        fanDebounceTimer.restart();
    }

    function setCpuTurbo(enabled: bool): void {
        cpuTurboEnabled = enabled;
        actionProc.command = ["pkexec", "/usr/local/bin/caelestia-optimize", "cpu-boost", enabled ? "1" : "0"];
        actionProc.running = true;
    }

    function setIoScheduler(sched: string): void {
        ioScheduler = sched;
        actionProc.command = ["pkexec", "/usr/local/bin/caelestia-optimize", "io-scheduler", "nvme0n1", sched];
        actionProc.running = true;
    }

    function setScxScheduler(sched: string, mode = ""): void {
        if (scxBusy)
            return;
        scxBusy = true;
        const targetMode = mode.length > 0 ? mode : (scxMode === "Default" ? preferredScxMode : scxMode);
        if (sched === "eevdf") {
            scxProc.command = ["scxctl", "stop"];
        } else if (scxSched === "eevdf") {
            scxProc.command = ["scxctl", "start", "-s", sched, "-m", targetMode.toLowerCase()];
        } else {
            scxProc.command = ["scxctl", "switch", "-s", sched, "-m", targetMode.toLowerCase()];
        }
        if (sched !== "eevdf") {
            preferredScxSched = sched;
            preferredScxMode = targetMode;
            save();
        }
        scxProc.running = true;
    }

    function setScxBoot(enabled: bool): void {
        scxBootEnabled = enabled;
        const sched = scxSched === "eevdf" ? preferredScxSched : scxSched;
        const mode = scxMode === "Default" ? preferredScxMode : scxMode;
        actionProc.command = ["pkexec", "/usr/local/bin/caelestia-optimize", "scx-boot", enabled ? "enable" : "disable", sched, mode];
        actionProc.running = true;
    }

    function terminateProcess(pid: int): void {
        if (pid <= 1)
            return;
        actionProc.command = ["kill", "-TERM", String(pid)];
        actionProc.running = true;
    }

    function save(): void {
        if (loaded)
            saveTimer.restart();
    }

    Component.onCompleted: refreshTelemetry()

    // Fan slider debounce so dragging doesn't spawn 50 pkexec calls
    Timer {
        id: fanDebounceTimer

        interval: 150
        onTriggered: {
            if (root._pendingCpuBoost < 0)
                return;
            actionProc.command = ["pkexec", "/usr/local/bin/caelestia-optimize", "fan-boost", String(root._pendingCpuBoost), String(root._pendingGpuBoost)];
            actionProc.running = true;
        }
    }

    // Telemetry Reader
    Process {
        id: telemetryProc

        command: ["/usr/local/bin/caelestia-telemetry"]
        property var _procsBuf: []

        onStarted: _procsBuf = []
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (!line)
                    return;
                const parts = line.split("|");
                const tag = parts[0];
                const kv = {};
                for (let i = 1; i < parts.length; i++) {
                    const eq = parts[i].indexOf("=");
                    if (eq > 0)
                        kv[parts[i].slice(0, eq)] = parts[i].slice(eq + 1);
                }

                if (tag === "MEM") {
                    const total = Number(kv.total_kib) || 0;
                    const used = Number(kv.used_kib) || 0;
                    const avail = Number(kv.avail_kib) || 0;
                    root.ramPct = Number(kv.pct) || 0;
                    root.ramUsageText = `${(used / 1048576).toFixed(1)} / ${(total / 1048576).toFixed(1)} GiB`;
                    root.ramFreeText = `${(avail / 1048576).toFixed(1)} GiB available`;
                } else if (tag === "ZRAM") {
                    const disk = Number(kv.disk) || 0;
                    const dataB = Number(kv.data) || 0;
                    const compr = Number(kv.compr) || 0;
                    root.zramText = `${root._formatBytes(compr)} (from ${root._formatBytes(dataB)}) / ${root._formatBytes(disk)}`;
                } else if (tag === "DISK") {
                    const used = Number(kv.used_kib) || 0;
                    const total = Number(kv.total_kib) || 0;
                    root.rootDiskPct = Number(kv.pct) || 0;
                    root.rootDiskText = `${(used / 1048576).toFixed(1)} / ${(total / 1048576).toFixed(1)} GiB`;
                } else if (tag === "CPU") {
                    root.cpuTurboEnabled = kv.boost === "1";
                    root.cpuGov = kv.gov || "powersave";
                    root.cpuEpp = kv.epp || "balance_performance";
                    root.cpuTemp = Number(kv.temp) || 0;
                } else if (tag === "SCX") {
                    root.scxSched = kv.sched || "eevdf";
                    root.scxMode = kv.mode || "Default";
                    root.scxBootEnabled = kv.boot === "1";
                } else if (tag === "THERMAL") {
                    root.platformProfile = kv.profile || "balanced";
                    root.cpuFanRpm = Number(kv.cpu_rpm) || 0;
                    root.gpuFanRpm = Number(kv.gpu_rpm) || 0;
                    root.cpuFanMaxRpm = Number(kv.cpu_max) || 4700;
                    root.gpuFanMaxRpm = Number(kv.gpu_max) || 4400;
                    root.cpuFanBoost = Number(kv.cpu_boost) || 0;
                    root.gpuFanBoost = Number(kv.gpu_boost) || 0;
                    root.sodimmTemp = Number(kv.sodimm_temp) || 0;

                    if (root.platformProfile === "performance" && root.cpuFanBoost >= 95 && root.gpuFanBoost >= 95)
                        root.thermalProfile = "gmode";
                    else if (root.platformProfile === "performance")
                        root.thermalProfile = "performance";
                    else
                        root.thermalProfile = "balanced";
                } else if (tag === "GPU") {
                    root.amdGpuTemp = Number(kv.amd_temp) || 0;
                    root.gpuTemp = Number(kv.nv_temp) || root.amdGpuTemp;
                    root.nvGpuUtil = Number(kv.nv_util) || 0;
                    root.nvGpuPower = kv.nv_power || "0 W";
                    root.nvGpuVram = kv.nv_vram || "0 / 4096 MiB";
                } else if (tag === "IO") {
                    root.ioScheduler = kv.sched || "kyber";
                    if (kv.avail)
                        root.ioAvailable = kv.avail.split(" ").filter(s => s.length > 0);
                } else if (tag === "SVC") {
                    root.svcAnanicy = kv.ananicy === "1";
                    root.svcOomd = kv.oomd === "1";
                    root.svcPowerd = kv.powerd === "1";
                    root.svcScx = kv.scx === "1";
                    root.svcNvidia = kv.nvidia === "1";
                    root.svcFstrim = kv.fstrim === "1";
                    root.failedUnits = Number(kv.failed) || 0;
                } else if (tag === "CACHE") {
                    root.thumbSize = root._formatKib(Number(kv.thumb_kib) || 0);
                    root.trashSize = root._formatKib(Number(kv.trash_kib) || 0);
                    root.pacmanCacheSize = root._formatKib(Number(kv.pacman_kib) || 0);
                    root.journalSize = kv.journal || "0M";
                } else if (tag === "PROC") {
                    telemetryProc._procsBuf.push({
                        pid: Number(kv.pid) || 0,
                        name: kv.name || "",
                        mib: Number(kv.mib) || 0,
                        pct: kv.pct || "0"
                    });
                }
            }
        }
        onExited: {
            root.topProcesses = telemetryProc._procsBuf.slice();
            root._recomputeHealth();

            // Adaptive Smart Cooling for Balanced Mode (keeps fans spinning gently whenever warm, never silent 0 RPM above 48°C)
            if (root.smartCoolEnabled && root.thermalProfile === "balanced" && root.cpuFanBoost === 0 && root.gpuFanBoost === 0 && !coolProc.running) {
                const peak = Math.max(root.cpuTemp, root.gpuTemp);
                let targetLevel = root._autoCoolLevel;
                if (peak >= 72)
                    targetLevel = 3;
                else if (peak >= 60)
                    targetLevel = root._autoCoolLevel === 3 && peak > 65 ? 3 : Math.max(targetLevel, 2);
                else if (peak >= 48)
                    targetLevel = root._autoCoolLevel >= 2 && peak > 54 ? targetLevel : Math.max(targetLevel, 1);
                else if (peak <= 43)
                    targetLevel = 0;

                if (targetLevel !== root._autoCoolLevel) {
                    root._autoCoolLevel = targetLevel;
                    coolProc.command = ["pkexec", "/usr/local/bin/caelestia-optimize", "auto-cool", String(targetLevel)];
                    coolProc.running = true;
                }
            } else if (!root.smartCoolEnabled && root._autoCoolLevel !== 0 && !coolProc.running) {
                root._autoCoolLevel = 0;
                coolProc.command = ["pkexec", "/usr/local/bin/caelestia-optimize", "auto-cool", "0"];
                coolProc.running = true;
            }

            // Optional Auto-RAM guard (cooldown 10 mins)
            if (root.autoRamThreshold > 0 && root.ramPct >= root.autoRamThreshold && !root.optimizingNow) {
                const now = Date.now();
                if (now - root._lastAutoOptMs > 600000) {
                    root._lastAutoOptMs = now;
                    root.runDeepOptimize();
                }
            }
        }
    }

    // Deep Optimization Runner
    Process {
        id: optimizeProc

        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (!line)
                    return;
                const parts = line.split("|");
                if (parts[0] === "STAGE" && parts.length >= 3) {
                    root.optimizeProgress = Number(parts[1]) || root.optimizeProgress;
                    root.optimizeStageText = parts[2];
                    root.optimizeStatusText = parts[2];
                } else if (parts[0] === "RESULT") {
                    const kv = {};
                    for (let i = 1; i < parts.length; i++) {
                        const eq = parts[i].indexOf("=");
                        if (eq > 0)
                            kv[parts[i].slice(0, eq)] = parts[i].slice(eq + 1);
                    }
                    const rMiB = Number(kv.reclaimed_mib) || 0;
                    const dMiB = Number(kv.disk_freed_mib) || 0;
                    root.lastReclaimedMiB = rMiB;
                    root.lastDiskFreedMiB = dMiB;
                    const d = new Date();
                    root.lastOptimizedTime = Qt.formatTime(d, "hh:mm");
                    root.optimizeProgress = 1.0;

                    const msgParts = [];
                    if (rMiB > 0)
                        msgParts.push(`+${rMiB} MiB RAM`);
                    if (dMiB > 0)
                        msgParts.push(`${dMiB} MiB disk freed`);
                    root.optimizeStatusText = msgParts.length > 0 ? `Boosted: ${msgParts.join(" • ")}` : "System caches & services optimized";
                    root.save();
                }
            }
        }
        onExited: {
            root.optimizingNow = false;
            root.optimizeStageText = "";
            Qt.callLater(root.refreshTelemetry);
        }
    }

    // Single Hardware Action Runner (Thermal, Fan, Turbo, IO, SCX Boot)
    Process {
        id: actionProc

        onExited: Qt.callLater(root.refreshTelemetry)
    }

    // SCX D-Bus Switcher
    Process {
        id: scxProc

        onExited: {
            root.scxBusy = false;
            Qt.callLater(root.refreshTelemetry);
        }
    }

    // Smart Adaptive Fan Curve Runner
    Process {
        id: coolProc

        onExited: Qt.callLater(root.refreshTelemetry)
    }

    // Delayed CPU EPP/Cap Tuning after PowerProfiles D-Bus changes
    Timer {
        id: powerTuneTimer

        interval: 350
        onTriggered: {
            if (actionProc.running)
                return;
            actionProc.command = ["pkexec", "/usr/local/bin/caelestia-optimize", "apply-power-tuning", root.powerProfileId, root.smartCoolEnabled ? "1" : "0"];
            actionProc.running = true;
        }
    }

    // Periodic Telemetry Poll (lightweight 110ms helper)
    Timer {
        interval: 4000
        running: true
        repeat: true
        onTriggered: root.refreshTelemetry()
    }

    Timer {
        id: saveTimer

        interval: 250
        onTriggered: {
            const payload = {
                showDashboardTab: root.showDashboardTab,
                smartCoolEnabled: root.smartCoolEnabled,
                cleanPacman: root.cleanPacman,
                cleanTrim: root.cleanTrim,
                cleanTrash: root.cleanTrash,
                autoRamThreshold: root.autoRamThreshold,
                preferredScxSched: root.preferredScxSched,
                preferredScxMode: root.preferredScxMode,
                lastReclaimedMiB: root.lastReclaimedMiB,
                lastDiskFreedMiB: root.lastDiskFreedMiB,
                lastOptimizedTime: root.lastOptimizedTime
            };
            storage.setText(JSON.stringify(payload, null, 4));
        }
    }

    FileView {
        id: storage

        printErrors: false
        path: `${Paths.config}/optimizer.json`
        onLoaded: {
            try {
                const d = JSON.parse(text());
                if (d.showDashboardTab !== undefined)
                    root.showDashboardTab = Boolean(d.showDashboardTab);
                if (d.smartCoolEnabled !== undefined)
                    root.smartCoolEnabled = Boolean(d.smartCoolEnabled);
                if (d.cleanPacman !== undefined)
                    root.cleanPacman = Boolean(d.cleanPacman);
                if (d.cleanTrim !== undefined)
                    root.cleanTrim = Boolean(d.cleanTrim);
                if (d.cleanTrash !== undefined)
                    root.cleanTrash = Boolean(d.cleanTrash);
                if (d.autoRamThreshold !== undefined)
                    root.autoRamThreshold = Number(d.autoRamThreshold) || 0;
                if (d.preferredScxSched)
                    root.preferredScxSched = String(d.preferredScxSched);
                if (d.preferredScxMode)
                    root.preferredScxMode = String(d.preferredScxMode);
                if (d.lastReclaimedMiB !== undefined)
                    root.lastReclaimedMiB = Number(d.lastReclaimedMiB) || 0;
                if (d.lastDiskFreedMiB !== undefined)
                    root.lastDiskFreedMiB = Number(d.lastDiskFreedMiB) || 0;
                if (d.lastOptimizedTime)
                    root.lastOptimizedTime = String(d.lastOptimizedTime);
            } catch (e) {}
            root.loaded = true;
            if (root.smartCoolEnabled)
                Qt.callLater(() => powerTuneTimer.restart());
        }
        onLoadFailed: err => {
            root.loaded = true;
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => saveTimer.restart());
        }
    }
}
