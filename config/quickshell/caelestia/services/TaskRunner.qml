pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Global Task Runner State
    property bool running: false
    property string taskTitle: ""
    property string taskIcon: "sync"
    property string statusText: ""
    property real progress: -1 // -1 = indeterminate, 0.0..1.0 = determinate
    property int exitCode: 0
    property bool hasTask: false
    property bool drawerExpanded: false
    property bool refreshOnFinish: false
    property list<string> logLines: []
    property string logOutput: ""

    // Persistent System Updates & Driver State
    property list<var> repoUpdates: []
    property list<var> aurUpdates: []
    property list<var> flatpakUpdates: []
    property list<var> driverProfiles: []
    property bool checkingUpdates: false
    property string lastChecked: ""
    property int totalPackages: 0
    property string kernelVersion: ""
    property string cacheSize: "..."
    property int orphanCount: 0
    readonly property int totalUpdateCount: repoUpdates.length + aurUpdates.length + flatpakUpdates.length

    function appendLog(line: string): void {
        const cleaned = line.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "").trim();
        if (!cleaned)
            return;

        // Parse progress percentage if present (e.g. "45%" or "(3/10)")
        const pctMatch = cleaned.match(/\b(\d{1,3})%/);
        if (pctMatch) {
            const p = parseInt(pctMatch[1], 10);
            if (p >= 0 && p <= 100)
                root.progress = p / 100.0;
        } else {
            const stepMatch = cleaned.match(/\((\d+)\/(\d+)\)/);
            if (stepMatch) {
                const cur = parseInt(stepMatch[1], 10);
                const tot = parseInt(stepMatch[2], 10);
                if (tot > 0 && cur <= tot)
                    root.progress = cur / tot;
            }
        }

        if (!cleaned.startsWith("$ ") && cleaned.length > 2) {
            root.statusText = cleaned.length > 90 ? cleaned.slice(0, 88) + "…" : cleaned;
        }

        const next = root.logLines.slice(-250);
        next.push(cleaned);
        root.logLines = next;
        root.logOutput = next.join("\n");
    }

    function clearLog(): void {
        root.logLines = [];
        root.logOutput = "";
        root.progress = -1;
    }

    function run(title: string, command: string, usePkexec: bool, iconName: string, refreshUpdates = false): void {
        if (root.running) {
            appendLog(">>> Another task is already running. Please wait or stop it first.");
            return;
        }
        clearLog();
        root.taskTitle = title;
        root.taskIcon = iconName || "sync";
        root.statusText = "Starting task...";
        root.running = true;
        root.hasTask = true;
        root.exitCode = 0;
        root.drawerExpanded = false; // Default to sleek progress bar only; user clicks "Show Code" to expand
        root.refreshOnFinish = refreshUpdates;

        appendLog(`$ ${title}`);
        if (usePkexec) {
            taskProc.command = ["pkexec", "bash", "-c", command];
        } else {
            taskProc.command = ["bash", "-c", command];
        }
        taskProc.running = true;
    }

    function stopTask(): void {
        if (taskProc.running) {
            taskProc.running = false;
            root.running = false;
            root.progress = -1;
            root.statusText = "Stopped by user";
            appendLog(">>> [Task cancelled]");
        }
    }

    function checkUpdates(): void {
        if (root.checkingUpdates)
            return;
        root.checkingUpdates = true;
        statsProc.running = true;
        checkUpdatesProc.running = true;
        driverCheckProc.running = true;
    }

    function runSystemUpdate(mode: string): void {
        if (mode === "full") {
            run(
                "Full System Update (Official Repos + AUR + Flatpak)",
                "pkexec pacman -Syu --noconfirm && (command -v paru >/dev/null && paru --sudo pkexec -Sua --noconfirm || true) && (command -v flatpak >/dev/null && flatpak update -y || true)",
                false,
                "system_update_alt",
                true
            );
        } else if (mode === "repo") {
            run(
                "Update Official Packages (pacman -Syu)",
                "pacman -Syu --noconfirm",
                true,
                "update",
                true
            );
        } else if (mode === "aur") {
            run(
                "Update AUR Packages (paru -Sua)",
                "paru --sudo pkexec -Sua --noconfirm",
                false,
                "inventory_2",
                true
            );
        } else if (mode === "flatpak") {
            run(
                "Update Flatpak Applications",
                "flatpak update -y",
                false,
                "widgets",
                true
            );
        } else if (mode === "drivers") {
            run(
                "Install Recommended Hardware Drivers (chwd -a)",
                "chwd -a && mkinitcpio -P || true",
                true,
                "developer_board",
                true
            );
        } else if (mode === "firmware") {
            run(
                "Check & Update System Firmware (fwupdmgr)",
                "fwupdmgr refresh --force && fwupdmgr get-updates -y || echo 'All firmware is up to date.'",
                true,
                "memory",
                false
            );
        }
    }

    Process {
        id: taskProc

        stdout: SplitParser {
            onRead: data => root.appendLog(data)
        }

        stderr: SplitParser {
            onRead: data => root.appendLog(data)
        }

        onExited: code => {
            root.running = false;
            root.exitCode = code;
            root.progress = code === 0 ? 1.0 : -1;
            if (code === 0) {
                root.statusText = "Completed successfully";
                root.appendLog(">>> [Completed successfully (exit code 0)]");
            } else {
                root.statusText = `Failed with exit code ${code}`;
                root.appendLog(`>>> [Exited with error code: ${code}]`);
            }
            if (root.refreshOnFinish) {
                root.checkUpdates();
            }
        }
    }

    Process {
        id: statsProc

        command: ["sh", "-c", "echo \"PKGS:$(pacman -Qq 2>/dev/null | wc -l)\"; echo \"KERNEL:$(uname -r)\"; echo \"CACHE:$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)\"; echo \"ORPHANS:$(pacman -Qdtq 2>/dev/null | wc -l)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                for (const line of lines) {
                    if (line.startsWith("PKGS:"))
                        root.totalPackages = parseInt(line.slice(5).trim(), 10) || 0;
                    else if (line.startsWith("KERNEL:"))
                        root.kernelVersion = line.slice(7).trim();
                    else if (line.startsWith("CACHE:"))
                        root.cacheSize = line.slice(6).trim() || "0B";
                    else if (line.startsWith("ORPHANS:"))
                        root.orphanCount = parseInt(line.slice(8).trim(), 10) || 0;
                }
            }
        }
    }

    Process {
        id: driverCheckProc

        command: ["python3", "-c", `
import subprocess, json

def sh(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""

nv_ver = sh("nvidia-smi --query-gpu=driver_version --format=csv,noheader")
nv_name = sh("nvidia-smi --query-gpu=name --format=csv,noheader") or "NVIDIA GeForce RTX 3050 Laptop GPU"
mesa_ver = sh("pacman -Q mesa | awk '{print $2}'")
amd_vulkan = sh("pacman -Q vulkan-radeon | awk '{print $2}'")
nv_pkg = sh("pacman -Q linux-cachyos-nvidia-open 2>/dev/null || pacman -Q nvidia-open-dkms 2>/dev/null || pacman -Q nvidia-utils 2>/dev/null")
ucode = sh("pacman -Q amd-ucode | awk '{print $2}'")

profiles = [
    {
        "id": "nvidia-open-dkms.prime",
        "device": nv_name,
        "pci": "0000:01:00.0",
        "profile": "nvidia-open-dkms.prime",
        "version": nv_ver or (nv_pkg.split()[-1] if nv_pkg else "Installed"),
        "status": "Active (PRIME Render Offload)" if nv_ver else "Available",
        "installed": bool(nv_ver or nv_pkg),
        "recommended": True,
        "icon": "developer_board"
    },
    {
        "id": "amd",
        "device": "AMD Radeon Vega Integrated Graphics",
        "pci": "0000:06:00.0",
        "profile": "amd (Mesa + RADV Vulkan)",
        "version": f"Mesa {mesa_ver}" if mesa_ver else "Installed",
        "status": f"Active (RADV {amd_vulkan})" if amd_vulkan else "Active",
        "installed": bool(mesa_ver),
        "recommended": True,
        "icon": "memory"
    },
    {
        "id": "amd-ucode",
        "device": "AMD Ryzen 5 5600H Microcode & P-State",
        "pci": "CPU Firmware",
        "profile": "amd-ucode + amd_pstate",
        "version": ucode or "Installed",
        "status": "Active",
        "installed": bool(ucode),
        "recommended": True,
        "icon": "speed"
    }
]
print(json.dumps(profiles))
`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.driverProfiles = JSON.parse(text.trim());
                } catch (e) {}
            }
        }
    }

    Process {
        id: checkUpdatesProc

        command: ["sh", "-c", "echo '===REPO==='; (checkupdates 2>/dev/null || pacman -Qu 2>/dev/null || true); echo '===AUR==='; (paru -Qua 2>/dev/null || yay -Qua 2>/dev/null || true); echo '===FLATPAK==='; (flatpak remote-ls --updates --columns=application,version,branch 2>/dev/null || true)"]
        stdout: StdioCollector {
            onStreamFinished: {
                const repo = [];
                const aur = [];
                const fp = [];
                let section = "";

                const lines = text.split("\n");
                for (const raw of lines) {
                    const line = raw.trim();
                    if (!line)
                        continue;
                    if (line === "===REPO===") {
                        section = "repo";
                        continue;
                    }
                    if (line === "===AUR===") {
                        section = "aur";
                        continue;
                    }
                    if (line === "===FLATPAK===") {
                        section = "flatpak";
                        continue;
                    }

                    if (section === "repo" || section === "aur") {
                        const m = line.match(/^(\S+)\s+(\S+)\s+->\s+(\S+)/);
                        if (m) {
                            const item = {
                                name: m[1],
                                oldVer: m[2],
                                newVer: m[3],
                                source: section === "repo" ? "Official" : "AUR"
                            };
                            if (section === "repo")
                                repo.push(item);
                            else
                                aur.push(item);
                        }
                    } else if (section === "flatpak") {
                        const parts = line.split(/\s+/);
                        if (parts.length >= 1 && parts[0].includes(".")) {
                            fp.push({
                                name: parts[0],
                                oldVer: parts[2] || "installed",
                                newVer: parts[1] || "latest",
                                source: "Flatpak"
                            });
                        }
                    }
                }

                root.repoUpdates = repo;
                root.aurUpdates = aur;
                root.flatpakUpdates = fp;
                root.checkingUpdates = false;
                root.lastChecked = Qt.formatTime(new Date(), "HH:mm:ss");
            }
        }
    }

    Component.onCompleted: {
        Qt.callLater(() => root.checkUpdates());
    }
}
