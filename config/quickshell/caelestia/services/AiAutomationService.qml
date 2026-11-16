pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.services
import qs.utils

Singleton {
    id: root

    // Environment & CLI diagnostics
    property bool cliInstalled: false
    property string cliPath: ""
    property string cliVersion: ""
    property string authStatus: "unknown" // "unknown" | "checking" | "authenticated" | "unauthenticated"
    property string authDetail: "Not checked yet"
    property bool checkingCli: false
    property bool ydotoolActive: false
    property var availableModels: []

    // Persisted settings
    property bool enabled: true
    property string supervisorModel: "gemini-4-hydrogen-high"
    property string workerModel: "gemini-4-argon-high"
    property bool autoSwitchOnQuota: true
    property var fallbackModels: [
        "gemini-4-hydrogen-high",
        "gemini-4-argon-high",
        "claude-sonnet-5-5-high",
        "gemini-3.8-flash-high",
        "gemini-3.8-flash-medium",
        "gpt-oss-120b-medium"
    ]
    property bool fullPermissions: true
    property bool openWorkerTerminal: true
    property bool allowDesktopActions: true
    property bool askOnInvalidResult: true

    // Runtime orchestration & chat state
    property bool loaded: false
    property bool running: false
    property string currentPhase: "idle" // "idle" | "planning" | "working" | "verifying" | "waiting_user" | "done" | "error"
    property string phaseDetail: ""
    property string currentLogPath: ""
    property string streamingWorkerText: ""
    property string streamingWorkerModel: ""
    property string activeSupervisorModel: supervisorModel
    property string activeWorkerModel: workerModel
    property bool hasPendingQuestion: false
    property var pendingQuestion: null
    property var chatMessages: []
    property int _msgSeq: 0
    property string pendingLauncherText: ""

    signal monitorRequested()

    function nowStamp(): string {
        const d = new Date();
        const pad = n => String(n).padStart(2, "0");
        return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
    }

    function appendMessage(role: string, title: string, text: string, model: string): void {
        _msgSeq += 1;
        const next = chatMessages.slice();
        next.push({
            id: _msgSeq,
            role: role,
            title: title,
            text: text,
            model: model || "",
            ts: nowStamp()
        });
        chatMessages = next;
    }

    function clearChat(): void {
        if (running)
            return;
        chatMessages = [];
        streamingWorkerText = "";
        hasPendingQuestion = false;
        pendingQuestion = null;
        currentPhase = "idle";
        phaseDetail = "";
    }

    function refreshEnvironment(): void {
        if (checkingCli)
            return;
        checkingCli = true;
        envCheckProc.running = false;
        envCheckProc.running = true;
    }

    function verifyAuthLive(): void {
        if (!cliInstalled || authProbeProc.running)
            return;
        authStatus = "checking";
        authDetail = "Testing live Antigravity CLI session...";
        authProbeProc.running = true;
    }

    function openLoginTerminal(): void {
        const script = "export PATH=\"$HOME/.local/bin:$PATH\"; echo '=== Antigravity CLI Account Setup ==='; echo 'Complete login prompts if shown (or run /login inside agy, then Ctrl+D twice to exit).'; echo ''; agy; echo ''; read -p 'Press Enter to close and refresh Nexus... ' _";
        Quickshell.execDetached(["foot", "--app-id", "caelestia-ai-login", "-T", "Antigravity CLI — Account Login", "-e", "bash", "-c", script]);
        authRefreshTimer.restart();
    }

    function installCli(): void {
        const script = "echo 'Installing Antigravity CLI...'; curl -fsSL https://antigravity.google/install.sh | bash || true; echo ''; read -p 'Press Enter to close... ' _";
        Quickshell.execDetached(["foot", "--app-id", "caelestia-ai-install", "-T", "Install Antigravity CLI", "-e", "bash", "-c", script]);
        authRefreshTimer.restart();
    }

    function enableYdotool(): void {
        ydotoolEnableProc.running = true;
    }

    function toggleFallbackModel(modelId: string): void {
        const list = (fallbackModels || []).slice();
        const idx = list.indexOf(modelId);
        if (idx >= 0) {
            list.splice(idx, 1);
        } else {
            list.push(modelId);
        }
        fallbackModels = list;
        saveConfig();
    }

    function moveFallbackModel(modelId: string, delta: int): void {
        const list = (fallbackModels || []).slice();
        const idx = list.indexOf(modelId);
        if (idx < 0)
            return;
        const target = idx + delta;
        if (target < 0 || target >= list.length)
            return;
        const tmp = list[idx];
        list[idx] = list[target];
        list[target] = tmp;
        fallbackModels = list;
        saveConfig();
    }

    function openWorkerTerminalWindow(): void {
        if (!currentLogPath)
            return;
        Quickshell.execDetached([
            "foot",
            "--app-id", "caelestia-ai-terminal",
            "-T", "AI Agent Terminal — Live Execution",
            "-e", "bash", "-c",
            `touch '${currentLogPath}' && tail -n +1 -F '${currentLogPath}'`
        ]);
    }

    function runTask(promptText: string): void {
        const clean = String(promptText ?? "").trim();
        if (!clean)
            return;

        monitorRequested();

        if (!cliInstalled) {
            appendMessage("system", "CLI Missing", "Antigravity CLI (agy) was not found. Please install and log in under Settings -> AI Automation.", "");
            currentPhase = "error";
            phaseDetail = "agy binary not found";
            return;
        }

        if (running) {
            if (hasPendingQuestion) {
                sendReply("retry", clean);
            } else {
                appendMessage("system", "Busy", "An AI task is already running. Stop it first or reply when prompted.", "");
            }
            return;
        }

        const logFile = `/tmp/caelestia-ai-${Date.now()}.log`;
        currentLogPath = logFile;
        running = true;
        currentPhase = "planning";
        phaseDetail = "Initializing Agent A (Supervisor) -> Agent B (Worker)...";
        streamingWorkerText = "";
        streamingWorkerModel = workerModel;
        activeSupervisorModel = supervisorModel;
        activeWorkerModel = workerModel;
        hasPendingQuestion = false;
        pendingQuestion = null;

        appendMessage("user", "Task Request", clean, "");

        const cfg = {
            supervisorModel: root.supervisorModel,
            workerModel: root.workerModel,
            autoSwitchOnQuota: root.autoSwitchOnQuota,
            fallbackModels: root.fallbackModels,
            fullPermissions: root.fullPermissions,
            allowDesktopActions: root.allowDesktopActions,
            askOnInvalidResult: root.askOnInvalidResult,
            cwd: "/home/mew"
        };

        orchestratorProc.command = [
            "python3",
            Quickshell.shellPath("scripts/ai_orchestrator.py"),
            JSON.stringify(cfg),
            logFile,
            clean
        ];
        orchestratorProc.running = true;

        if (openWorkerTerminal)
            Qt.callLater(() => root.openWorkerTerminalWindow());
    }

    function sendReply(action: string, text: string): void {
        if (!running)
            return;
        const clean = String(text ?? "").trim();
        if (clean.length > 0)
            appendMessage("user", "User Reply", clean, "");
        else if (action === "accept")
            appendMessage("user", "Confirmation", "Accepted Agent B's result.", "");
        else if (action === "retry")
            appendMessage("user", "Confirmation", "Requested Agent B to retry with corrections.", "");
        else if (action === "abort")
            appendMessage("user", "Confirmation", "Aborted task.", "");

        hasPendingQuestion = false;
        pendingQuestion = null;
        orchestratorProc.write(JSON.stringify({
            type: "user_reply",
            action: action,
            text: clean
        }) + "\n");
    }

    function stopTask(): void {
        if (!running)
            return;
        try {
            orchestratorProc.write(JSON.stringify({ type: "stop" }) + "\n");
        } catch (e) {}
        killTimer.restart();
    }

    function _handleEvent(line: string): void {
        const trimmed = line.trim();
        if (!trimmed)
            return;
        let ev = null;
        try {
            ev = JSON.parse(trimmed);
        } catch (e) {
            return;
        }
        const t = ev.type;
        if (t === "phase") {
            currentPhase = ev.phase || "working";
            phaseDetail = ev.detail || "";
        } else if (t === "agent_start") {
            if (ev.role === "agent_a")
                activeSupervisorModel = ev.model || supervisorModel;
            else {
                activeWorkerModel = ev.model || workerModel;
                streamingWorkerModel = activeWorkerModel;
                streamingWorkerText = "";
            }
        } else if (t === "agent_delta") {
            if (ev.role === "agent_b" && ev.text)
                streamingWorkerText += ev.text;
        } else if (t === "agent_tool") {
            if (ev.role === "agent_b")
                streamingWorkerText += `\n[Tool Step #${ev.step}] ${ev.detail}\n`;
        } else if (t === "model_switch") {
            const msg = `Quota/rate limit reached on ${ev.fromModel}. Auto-switched ${ev.role === "agent_a" ? "Agent A" : "Agent B"} to ${ev.toModel}.`;
            appendMessage("system", "Auto Model Switch", msg, ev.toModel);
            Notifs.notify({
                appName: "AI Automation",
                summary: "Model Auto-Switched",
                body: msg,
                appIcon: "auto_awesome"
            });
        } else if (t === "agent_message") {
            if (ev.role === "agent_b")
                streamingWorkerText = "";
            appendMessage(ev.role || "agent_a", ev.title || "Update", ev.text || "", ev.model || "");
        } else if (t === "user_question") {
            streamingWorkerText = "";
            hasPendingQuestion = true;
            pendingQuestion = {
                question: ev.question || "Agent A needs confirmation to proceed.",
                verification: ev.verification || "",
                suggestedFix: ev.suggestedFix || ""
            };
            appendMessage("question", "Agent A Requires Confirmation", pendingQuestion.question, ev.model || "");
            monitorRequested();
            Notifs.notify({
                appName: "AI Automation",
                summary: "Agent A Needs Confirmation",
                body: pendingQuestion.question,
                appIcon: "help"
            });
        } else if (t === "task_complete") {
            currentPhase = "done";
            phaseDetail = "Task verified & completed by Agent A.";
            running = false;
            hasPendingQuestion = false;
            pendingQuestion = null;
            Notifs.notify({
                appName: "AI Automation",
                summary: "AI Task Completed",
                body: String(ev.summary || "Completed successfully.").slice(0, 140),
                appIcon: "check_circle"
            });
        } else if (t === "task_error") {
            currentPhase = "error";
            phaseDetail = ev.message || "Task failed.";
            running = false;
            hasPendingQuestion = false;
            pendingQuestion = null;
            appendMessage("system", "Task Stopped / Error", ev.message || "Unknown error.", "");
        }
    }

    function saveConfig(): void {
        if (!loaded)
            return;
        saveTimer.restart();
    }

    Component.onCompleted: {
        refreshEnvironment();
    }

    Timer {
        id: authRefreshTimer
        interval: 4000
        repeat: false
        onTriggered: {
            root.refreshEnvironment();
            Qt.callLater(() => root.verifyAuthLive());
        }
    }

    Timer {
        id: killTimer
        interval: 1200
        repeat: false
        onTriggered: {
            if (orchestratorProc.running)
                orchestratorProc.running = false;
            root.running = false;
            root.currentPhase = "error";
            root.phaseDetail = "Stopped by user.";
        }
    }

    Timer {
        id: saveTimer
        interval: 250
        repeat: false
        onTriggered: {
            const payload = {
                enabled: root.enabled,
                supervisorModel: root.supervisorModel,
                workerModel: root.workerModel,
                autoSwitchOnQuota: root.autoSwitchOnQuota,
                fallbackModels: root.fallbackModels,
                fullPermissions: root.fullPermissions,
                openWorkerTerminal: root.openWorkerTerminal,
                allowDesktopActions: root.allowDesktopActions,
                askOnInvalidResult: root.askOnInvalidResult
            };
            configFile.setText(JSON.stringify(payload, null, 2));
        }
    }

    Process {
        id: orchestratorProc
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => root._handleEvent(data)
        }
        stderr: SplitParser {
            onRead: data => {
                const s = data.trim();
                if (s)
                    console.warn("AI Orchestrator:", s);
            }
        }
        onExited: exitCode => {
            killTimer.stop();
            if (root.running) {
                root.running = false;
                if (root.currentPhase !== "done" && root.currentPhase !== "error") {
                    root.currentPhase = exitCode === 0 ? "done" : "error";
                    root.phaseDetail = exitCode === 0 ? "Completed." : `Orchestrator exited (${exitCode})`;
                }
            }
        }
    }

    Process {
        id: envCheckProc
        command: ["bash", "-c",
            "export PATH=\"$HOME/.local/bin:$PATH\"; " +
            "BIN=$(command -v agy 2>/dev/null || true); " +
            "echo \"BIN:$BIN\"; " +
            "if [ -n \"$BIN\" ]; then " +
            "  VER=$(\"$BIN\" --version 2>/dev/null | head -n1); " +
            "  echo \"VER:$VER\"; " +
            "  YD=$(systemctl --user is-active ydotool 2>/dev/null || echo inactive); " +
            "  echo \"YD:$YD\"; " +
            "  \"$BIN\" models 2>/dev/null | awk -F '\\t' 'NF>=1 && $1 !~ /Fetching/ {print \"MOD:\" $1 \"\\t\" $2}'; " +
            "fi"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                let bin = "";
                let ver = "";
                let yd = false;
                const mods = [];
                for (const l of lines) {
                    if (l.startsWith("BIN:"))
                        bin = l.slice(4).trim();
                    else if (l.startsWith("VER:"))
                        ver = l.slice(4).trim();
                    else if (l.startsWith("YD:"))
                        yd = l.slice(3).trim() === "active";
                    else if (l.startsWith("MOD:")) {
                        const parts = l.slice(4).split("\t");
                        const mid = (parts[0] || "").trim();
                        const mlabel = (parts[1] || mid).trim();
                        if (mid)
                            mods.push({ id: mid, label: mlabel });
                    }
                }
                root.cliPath = bin;
                root.cliInstalled = bin.length > 0;
                root.cliVersion = ver;
                root.ydotoolActive = yd;
                if (mods.length > 0)
                    root.availableModels = mods;
                root.checkingCli = false;
                if (root.cliInstalled && root.authStatus === "unknown")
                    root.verifyAuthLive();
            }
        }
    }

    Process {
        id: authProbeProc
        command: ["bash", "-c", "export PATH=\"$HOME/.local/bin:$PATH\"; agy -p \"Reply with OK\" --output-format json --model gemini-3.8-flash-low --dangerously-skip-permissions"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                const lower = t.toLowerCase();
                if (lower.includes("not logged") || lower.includes("sign in") || lower.includes("unauthorized")) {
                    root.authStatus = "unauthenticated";
                    root.authDetail = "Login required — click Sign In to authenticate.";
                } else if (t.includes("\"SUCCESS\"") || t.includes("OK")) {
                    root.authStatus = "authenticated";
                    root.authDetail = `Ready (${root.availableModels.length} models discovered)`;
                } else {
                    root.authStatus = "unauthenticated";
                    root.authDetail = t ? t.slice(0, 120) : "Unable to verify session.";
                }
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0 && root.authStatus === "checking") {
                root.authStatus = "unauthenticated";
                root.authDetail = `Verification failed (exit ${exitCode}) — try signing in.`;
            }
        }
    }

    Process {
        id: ydotoolEnableProc
        command: ["systemctl", "--user", "enable", "--now", "ydotool"]
        onExited: exitCode => {
            root.ydotoolActive = exitCode === 0;
            root.refreshEnvironment();
        }
    }

    FileView {
        id: configFile
        path: `${Paths.config}/ai_automation.json`
        onLoaded: {
            try {
                const d = JSON.parse(text());
                if (d.enabled !== undefined)
                    root.enabled = Boolean(d.enabled);
                if (d.supervisorModel)
                    root.supervisorModel = String(d.supervisorModel);
                if (d.workerModel)
                    root.workerModel = String(d.workerModel);
                if (d.autoSwitchOnQuota !== undefined)
                    root.autoSwitchOnQuota = Boolean(d.autoSwitchOnQuota);
                if (Array.isArray(d.fallbackModels) && d.fallbackModels.length > 0)
                    root.fallbackModels = d.fallbackModels;
                if (d.fullPermissions !== undefined)
                    root.fullPermissions = Boolean(d.fullPermissions);
                if (d.openWorkerTerminal !== undefined)
                    root.openWorkerTerminal = Boolean(d.openWorkerTerminal);
                if (d.allowDesktopActions !== undefined)
                    root.allowDesktopActions = Boolean(d.allowDesktopActions);
                if (d.askOnInvalidResult !== undefined)
                    root.askOnInvalidResult = Boolean(d.askOnInvalidResult);
            } catch (e) {}
            root.loaded = true;
            root.activeSupervisorModel = root.supervisorModel;
            root.activeWorkerModel = root.workerModel;
        }
        onLoadFailed: err => {
            root.loaded = true;
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => saveTimer.restart());
        }
    }
}
