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
    property var modelCooldowns: ({})

    // Persisted settings
    property bool enabled: true
    property string supervisorModel: "gemini-4-hydrogen-high"
    property string workerModel: "gemini-4-argon-high"
    property string chatLanguage: "vi" // "vi" | "en" | "auto"
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
    property bool openWorkerTerminal: false // Hidden by default; live progress renders in Chat
    property bool allowDesktopActions: true
    property bool askOnInvalidResult: true
    property bool showGhostCursor: true
    property bool preferVisualCursor: false
    property int logRetentionDays: 30 // 7, 14, 30, 90, 180, or 0 (never)

    // Persistent conversation history & log storage
    readonly property string dataRoot: `${Paths.data}/ai`
    readonly property string logsDir: `${dataRoot}/logs`
    property var historySessions: []
    property string activeSessionId: ""
    property int totalLogFiles: 0
    property int totalLogBytes: 0

    // Compact Mini HUD & Animated AI Ghost Cursor states
    property bool miniHudVisible: false
    property bool miniHudHovered: false
    property bool compactRunActive: false
    property real cursorX: 960
    property real cursorY: 540
    property string cursorAction: "move"
    property string cursorLabel: ""
    property real cursorOverlayOpacity: 0.0

    signal monitorRequested()
    signal cursorPulseTriggered()

    // Runtime orchestration & chat state
    property bool loaded: false
    property bool running: false
    property string currentPhase: "idle" // "idle" | "planning" | "working" | "verifying" | "waiting_user" | "done" | "error"
    property int currentProgress: 0 // 0..100
    property string phaseDetail: ""
    property string currentLogPath: ""
    property string streamingWorkerText: ""
    property string streamingWorkerModel: ""
    property var liveSteps: [] // Live tool steps shown inside the chat progress card
    property string activeSupervisorModel: supervisorModel
    property string activeWorkerModel: workerModel
    property bool hasPendingQuestion: false
    property var pendingQuestion: null
    property var chatMessages: []
    property int _msgSeq: 0
    property string pendingLauncherText: ""

    function isVi(): bool {
        return chatLanguage === "vi";
    }

    function trChat(viStr: string, enStr: string): string {
        return isVi() ? viStr : enStr;
    }

    function refreshCooldowns(): void {
        cooldownFile.reload();
    }

    function cooldownSecondsLeft(modelId: string): int {
        const entry = modelCooldowns ? modelCooldowns[modelId] : null;
        if (!entry || !entry.until)
            return 0;
        const left = Math.floor(Number(entry.until) - (Date.now() / 1000));
        return left > 0 ? left : 0;
    }

    function cooldownLabel(modelId: string): string {
        const sec = cooldownSecondsLeft(modelId);
        if (sec <= 0)
            return "Ready";
        const h = Math.floor(sec / 3600);
        const m = Math.floor((sec % 3600) / 60);
        if (h >= 24) {
            const d = Math.floor(h / 24);
            const rh = h % 24;
            return `Cooldown ${d}d ${rh}h`;
        }
        if (h > 0)
            return `Cooldown ${h}h ${m}m`;
        return `Cooldown ${Math.max(1, m)}m`;
    }

    function hasActiveCooldowns(): bool {
        if (!modelCooldowns)
            return false;
        const keys = Object.keys(modelCooldowns);
        for (const k of keys) {
            if (cooldownSecondsLeft(k) > 0)
                return true;
        }
        return false;
    }

    function clearModelCooldowns(): void {
        modelCooldowns = ({});
        clearCooldownProc.running = true;
    }

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
        activeSessionId = "";
        currentLogPath = "";
        chatMessages = [];
        liveSteps = [];
        streamingWorkerText = "";
        hasPendingQuestion = false;
        pendingQuestion = null;
        currentPhase = "idle";
        currentProgress = 0;
        phaseDetail = "";
    }

    function formatBytes(bytes: int): string {
        if (bytes < 1024)
            return `${bytes} B`;
        if (bytes < 1048576)
            return `${(bytes / 1024).toFixed(1)} KB`;
        return `${(bytes / 1048576).toFixed(2)} MB`;
    }

    function formatDateTime(ms: real): string {
        const d = new Date(ms);
        const pad = n => String(n).padStart(2, "0");
        return `${pad(d.getDate())}/${pad(d.getMonth() + 1)} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
    }

    function refreshLogStats(): void {
        logStatsProc.running = false;
        logStatsProc.running = true;
    }

    function saveCurrentSession(): void {
        if (!activeSessionId || chatMessages.length === 0)
            return;
        const firstUser = chatMessages.find(m => m.role === "user");
        const title = firstUser ? String(firstUser.text).slice(0, 80) : "AI Task";
        const nowMs = Date.now();
        const entry = {
            id: activeSessionId,
            title: title,
            createdAt: Number(activeSessionId.split("-")[0]) || nowMs,
            updatedAt: nowMs,
            status: currentPhase,
            supervisorModel: activeSupervisorModel || supervisorModel,
            workerModel: activeWorkerModel || workerModel,
            logPath: currentLogPath,
            messages: chatMessages,
            steps: liveSteps
        };
        const list = (historySessions || []).slice();
        const idx = list.findIndex(s => s.id === activeSessionId);
        if (idx >= 0)
            list[idx] = entry;
        else
            list.unshift(entry);
        // Keep newest 200 metadata records bounded
        historySessions = list.slice(0, 200);
        historySaveTimer.restart();
    }

    function loadHistorySession(sessionId: string): void {
        if (running)
            return;
        const found = (historySessions || []).find(s => s.id === sessionId);
        if (!found)
            return;
        activeSessionId = found.id;
        chatMessages = (found.messages || []).slice();
        liveSteps = (found.steps || []).slice();
        currentLogPath = found.logPath || "";
        activeSupervisorModel = found.supervisorModel || supervisorModel;
        activeWorkerModel = found.workerModel || workerModel;
        currentPhase = found.status === "error" ? "error" : "done";
        currentProgress = currentPhase === "done" ? 100 : 0;
        phaseDetail = trChat(`Lịch sử (${formatDateTime(found.updatedAt)})`, `History (${formatDateTime(found.updatedAt)})`);
        hasPendingQuestion = false;
        pendingQuestion = null;
        streamingWorkerText = "";
    }

    function openSessionLog(logPath: string): void {
        if (!logPath)
            return;
        Quickshell.execDetached([
            "foot",
            "--app-id", "caelestia-ai-terminal",
            "-T", "Meow AI — Execution Log",
            "-e", "bash", "-c",
            `if [ -f '${logPath}' ]; then less -R +G '${logPath}'; else echo 'Log file removed or expired.'; read -p 'Press Enter...' _; fi`
        ]);
    }

    function deleteHistorySession(sessionId: string): void {
        const list = (historySessions || []).slice();
        const idx = list.findIndex(s => s.id === sessionId);
        if (idx < 0)
            return;
        const logPath = list[idx].logPath || "";
        list.splice(idx, 1);
        historySessions = list;
        if (activeSessionId === sessionId && !running)
            clearChat();
        historySaveTimer.restart();
        if (logPath)
            Quickshell.execDetached(["rm", "-f", logPath]);
        Qt.callLater(() => refreshLogStats());
    }

    function pruneExpiredHistory(): void {
        if (logRetentionDays <= 0)
            return;
        const cutoffMs = Date.now() - (logRetentionDays * 86400000);
        const kept = [];
        const expiredLogs = [];
        for (const s of (historySessions || [])) {
            const ts = Number(s.updatedAt || s.createdAt || 0);
            if (ts > 0 && ts < cutoffMs) {
                if (s.logPath)
                    expiredLogs.push(s.logPath);
            } else {
                kept.push(s);
            }
        }
        if (kept.length !== (historySessions || []).length) {
            historySessions = kept;
            historySaveTimer.restart();
        }
        // Also prune any orphaned/old .log files on disk older than logRetentionDays
        pruneLogsProc.command = [
            "bash", "-c",
            `mkdir -p '${root.logsDir}' && find '${root.logsDir}' -type f -name '*.log' -mtime +${Math.max(1, root.logRetentionDays)} -delete 2>/dev/null; ` +
            expiredLogs.map(p => `rm -f '${p}'`).join("; ")
        ];
        pruneLogsProc.running = true;
    }

    function clearAllHistory(): void {
        if (running)
            return;
        historySessions = [];
        clearChat();
        historySaveTimer.restart();
        clearLogsProc.running = true;
    }

    function openLogsFolder(): void {
        Quickshell.execDetached(["bash", "-c", `mkdir -p '${root.logsDir}' && setsid -f xdg-open '${root.logsDir}' >/dev/null 2>&1`]);
    }

    function updateCursor(x: int, y: int, action: string, label: string, clicked: bool): void {
        if (!showGhostCursor)
            return;
        cursorX = x;
        cursorY = y;
        cursorAction = action || "move";
        cursorLabel = label || "Operating";
        cursorOverlayOpacity = 1.0;
        if (clicked)
            cursorPulseTriggered();
        cursorHideTimer.restart();
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
        const script = "export PATH=\"$HOME/.local/bin:$PATH\"; echo 'Installing Antigravity CLI...'; curl -fsSL https://antigravity.google/cli/install.sh | bash && agy install --skip-aliases || (paru -S --needed --noconfirm antigravity-cli || true); echo ''; read -p 'Press Enter to close... ' _";
        Quickshell.execDetached(["foot", "--app-id", "caelestia-ai-install", "-T", "Install Antigravity CLI", "-e", "bash", "-c", script]);
        authRefreshTimer.restart();
    }

    function enableYdotool(): void {
        ydotoolEnableProc.running = true;
    }

    function toggleFallbackModel(modelId: string): void {
        const list = (fallbackModels || []).slice();
        const idx = list.indexOf(modelId);
        if (idx >= 0)
            list.splice(idx, 1);
        else
            list.push(modelId);
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
            "-T", "Meow AI — Execution Log",
            "-e", "bash", "-c",
            `touch '${currentLogPath}' && tail -n +1 -F '${currentLogPath}'`
        ]);
    }

    function runTask(promptText: string, compactMode: bool): void {
        const clean = String(promptText ?? "").trim();
        if (!clean)
            return;

        if (running) {
            if (!compactMode)
                monitorRequested();
            else
                miniHudVisible = true;
            if (hasPendingQuestion) {
                sendReply("retry", clean);
            } else {
                appendMessage(
                    "system",
                    trChat("Đang bận", "Busy"),
                    trChat("Một tác vụ AI khác đang chạy. Hãy dừng tác vụ hiện tại trước hoặc đợi hoàn tất.", "An AI task is already running. Stop it first or wait for completion."),
                    ""
                );
            }
            return;
        }

        // Refresh chat screen cleanly for every new user request
        clearChat();
        compactRunActive = Boolean(compactMode);
        if (compactRunActive) {
            miniHudVisible = true;
            miniHudAutoHideTimer.stop();
        } else {
            miniHudVisible = false;
            monitorRequested();
        }

        if (!cliInstalled) {
            appendMessage(
                "system",
                trChat("Thiếu CLI", "CLI Missing"),
                trChat("Không tìm thấy Antigravity CLI (agy). Vui lòng cài đặt và đăng nhập trong Settings -> AI Automation.", "Antigravity CLI (agy) was not found. Please install and sign in under Settings -> AI Automation."),
                ""
            );
            currentPhase = "error";
            phaseDetail = "agy binary not found";
            return;
        }

        const sid = `${Date.now()}`;
        const logFile = `${root.logsDir}/ai-${sid}.log`;
        activeSessionId = sid;
        currentLogPath = logFile;
        running = true;
        currentPhase = "planning";
        currentProgress = 10;
        phaseDetail = trChat("Đang khởi tạo trợ lý AI...", "Initializing AI assistant...");
        streamingWorkerText = "";
        streamingWorkerModel = workerModel;
        activeSupervisorModel = supervisorModel;
        activeWorkerModel = workerModel;
        hasPendingQuestion = false;
        pendingQuestion = null;

        appendMessage("user", trChat("Yêu cầu", "Request"), clean, "");

        const cfg = {
            supervisorModel: root.supervisorModel,
            workerModel: root.workerModel,
            chatLanguage: root.chatLanguage,
            autoSwitchOnQuota: root.autoSwitchOnQuota,
            fallbackModels: root.fallbackModels,
            fullPermissions: root.fullPermissions,
            allowDesktopActions: root.allowDesktopActions,
            preferVisualCursor: root.preferVisualCursor,
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
            appendMessage("user", trChat("Phản hồi", "Reply"), clean, "");
        else if (action === "accept")
            appendMessage("user", trChat("Xác nhận", "Confirmation"), trChat("Chấp nhận kết quả hiện tại.", "Accepted current result."), "");
        else if (action === "retry")
            appendMessage("user", trChat("Xác nhận", "Confirmation"), trChat("Yêu cầu thực hiện lại để khắc phục.", "Requested retry with corrections."), "");
        else if (action === "abort")
            appendMessage("user", trChat("Xác nhận", "Confirmation"), trChat("Đã hủy tác vụ.", "Aborted task."), "");

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
            if (ev.progress !== undefined)
                currentProgress = Number(ev.progress) || currentProgress;
            phaseDetail = ev.detail || "";
        } else if (t === "engine_start") {
            const label = ev.label || "";
            if (ev.role === "coordinator") {
                activeSupervisorModel = ev.model || supervisorModel;
            } else {
                activeWorkerModel = ev.model || workerModel;
                const nextSteps = liveSteps.slice();
                nextSteps.push({
                    ts: nowStamp(),
                    label: trChat(`Khởi chạy phân hệ: ${label} (${activeWorkerModel})`, `Starting track: ${label} (${activeWorkerModel})`)
                });
                liveSteps = nextSteps;
            }
        } else if (t === "engine_step") {
            const who = ev.worker ? `${ev.worker} • ` : "";
            const nextSteps = liveSteps.slice();
            nextSteps.push({
                ts: nowStamp(),
                label: `${who}${ev.detail}`
            });
            liveSteps = nextSteps;
        } else if (t === "model_switch") {
            refreshCooldowns();
            const msg = trChat(
                `Model ${ev.fromModel} đã hết hạn mức. Tự động chuyển sang ${ev.toModel}.`,
                `Quota/rate limit reached on ${ev.fromModel}. Auto-switched to ${ev.toModel}.`
            );
            appendMessage("system", trChat("Tự động đổi Model", "Auto Model Switch"), msg, ev.toModel);
            Toaster.toast(
                trChat("Đã tự động đổi Model", "Model Auto-Switched"),
                msg,
                "auto_awesome"
            );
        } else if (t === "assistant_message") {
            appendMessage("assistant", ev.title || "Meow AI", ev.text || "", ev.model || "");
            saveCurrentSession();
        } else if (t === "user_question") {
            streamingWorkerText = "";
            hasPendingQuestion = true;
            pendingQuestion = {
                question: ev.question || trChat("Cần xác nhận từ bạn để tiếp tục.", "Confirmation needed to proceed."),
                verification: ev.verification || "",
                suggestedFix: ev.suggestedFix || ""
            };
            appendMessage("question", trChat("Cần bạn xác nhận", "Confirmation Needed"), pendingQuestion.question, ev.model || "");
            saveCurrentSession();
            if (compactRunActive)
                miniHudVisible = true;
            else
                monitorRequested();
            Toaster.toast(
                trChat("AI cần xác nhận của bạn", "AI Needs Confirmation"),
                pendingQuestion.question,
                "help"
            );
        } else if (t === "task_complete") {
            currentPhase = "done";
            currentProgress = 100;
            phaseDetail = trChat("Đã hoàn tất và kiểm chứng thành công.", "Verified & completed.");
            running = false;
            hasPendingQuestion = false;
            pendingQuestion = null;
            saveCurrentSession();
            refreshLogStats();
            if (compactRunActive)
                miniHudAutoHideTimer.restart();
            Toaster.toast(
                trChat("Hoàn tất tác vụ AI", "AI Task Completed"),
                String(ev.summary || "Done.").replace(/[*`#]/g, "").slice(0, 140),
                "check_circle"
            );
        } else if (t === "task_error") {
            currentPhase = "error";
            phaseDetail = ev.message || trChat("Tác vụ gặp lỗi.", "Task failed.");
            running = false;
            hasPendingQuestion = false;
            pendingQuestion = null;
            appendMessage("system", trChat("Thông báo", "Notice"), ev.message || "Unknown error.", "");
            saveCurrentSession();
            refreshLogStats();
        }
    }

    function saveConfig(): void {
        if (!loaded)
            return;
        saveTimer.restart();
    }

    Component.onCompleted: {
        ensureDirsProc.running = true;
        refreshEnvironment();
        refreshLogStats();
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
            root.phaseDetail = root.trChat("Đã dừng theo yêu cầu.", "Stopped by user.");
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
                chatLanguage: root.chatLanguage,
                autoSwitchOnQuota: root.autoSwitchOnQuota,
                fallbackModels: root.fallbackModels,
                fullPermissions: root.fullPermissions,
                openWorkerTerminal: root.openWorkerTerminal,
                allowDesktopActions: root.allowDesktopActions,
                askOnInvalidResult: root.askOnInvalidResult,
                showGhostCursor: root.showGhostCursor,
                preferVisualCursor: root.preferVisualCursor,
                logRetentionDays: root.logRetentionDays
            };
            configFile.setText(JSON.stringify(payload, null, 2));
        }
    }

    Timer {
        id: cursorHideTimer
        interval: 2200
        repeat: false
        onTriggered: root.cursorOverlayOpacity = 0.0
    }

    Timer {
        id: miniHudAutoHideTimer
        interval: 10000
        repeat: false
        onTriggered: {
            if (!root.running && !root.hasPendingQuestion && !root.miniHudHovered)
                root.miniHudVisible = false;
            else if (root.miniHudHovered)
                restart();
        }
    }

    Timer {
        id: historySaveTimer
        interval: 200
        repeat: false
        onTriggered: {
            historyFile.setText(JSON.stringify({ sessions: root.historySessions }, null, 2));
        }
    }

    Process {
        id: ensureDirsProc
        command: ["bash", "-c", `mkdir -p '${root.logsDir}' && python3 '${Quickshell.shellPath("scripts/build_system_map.py")}' >/dev/null 2>&1 || true`]
    }

    Process {
        id: logStatsProc
        command: ["bash", "-c", `mkdir -p '${root.logsDir}' && find '${root.logsDir}' -type f -name '*.log' -printf '%s\n' 2>/dev/null | awk '{c++; s+=$1} END {print c+0 " " s+0}'`]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                root.totalLogFiles = Number(parts[0] || 0);
                root.totalLogBytes = Number(parts[1] || 0);
            }
        }
    }

    Process {
        id: pruneLogsProc
        onExited: root.refreshLogStats()
    }

    Process {
        id: clearLogsProc
        command: ["bash", "-c", `rm -f '${root.logsDir}'/*.log /tmp/caelestia-ai-*.log 2>/dev/null || true`]
        onExited: root.refreshLogStats()
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
            root.refreshCooldowns();
            if (root.running) {
                root.running = false;
                if (root.currentPhase !== "done" && root.currentPhase !== "error") {
                    root.currentPhase = exitCode === 0 ? "done" : "error";
                    root.currentProgress = exitCode === 0 ? 100 : root.currentProgress;
                    root.phaseDetail = exitCode === 0
                        ? root.trChat("Đã hoàn tất.", "Completed.")
                        : `Orchestrator exited (${exitCode})`;
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
        command: ["bash", "-c", "export PATH=\"$HOME/.local/bin:$PATH\"; agy -p \"Reply with OK\" --output-format json --model gemini-4-hydrogen-low --dangerously-skip-permissions 2>&1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                const lower = t.toLowerCase();
                if (lower.includes("not logged") || lower.includes("sign in") || lower.includes("unauthorized")) {
                    root.authStatus = "unauthenticated";
                    root.authDetail = "Login required — click Sign In to authenticate.";
                } else if (t.includes("\"SUCCESS\"") || t.includes("OK") || lower.includes("resource_exhausted") || lower.includes("429") || lower.includes("quota")) {
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
        id: clearCooldownProc
        command: ["rm", "-f", `${Paths.cache}/ai_model_cooldowns.json`]
    }

    FileView {
        id: cooldownFile
        path: `${Paths.cache}/ai_model_cooldowns.json`
        onLoaded: {
            try {
                const raw = JSON.parse(text());
                root.modelCooldowns = (raw && typeof raw === "object") ? raw : ({});
            } catch (e) {
                root.modelCooldowns = ({});
            }
        }
        onLoadFailed: {
            root.modelCooldowns = ({});
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
                if (d.chatLanguage)
                    root.chatLanguage = String(d.chatLanguage);
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
                if (d.showGhostCursor !== undefined)
                    root.showGhostCursor = Boolean(d.showGhostCursor);
                if (d.preferVisualCursor !== undefined)
                    root.preferVisualCursor = Boolean(d.preferVisualCursor);
                if (d.logRetentionDays !== undefined)
                    root.logRetentionDays = Number(d.logRetentionDays);
            } catch (e) {}
            root.loaded = true;
            root.activeSupervisorModel = root.supervisorModel;
            root.activeWorkerModel = root.workerModel;
            Qt.callLater(() => root.pruneExpiredHistory());
        }
        onLoadFailed: err => {
            root.loaded = true;
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => saveTimer.restart());
        }
    }

    FileView {
        id: historyFile
        path: `${root.dataRoot}/history.json`
        onLoaded: {
            try {
                const raw = JSON.parse(text());
                if (raw && Array.isArray(raw.sessions))
                    root.historySessions = raw.sessions;
            } catch (e) {}
            if (root.loaded)
                Qt.callLater(() => root.pruneExpiredHistory());
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                root.historySessions = [];
        }
    }
}
