pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common
import qs.modules.ai

PageBase {
    id: root

    title: Tr.tr("AI Automation")

    readonly property list<MenuItem> languageItems: [
        MenuItem {
            text: "Tiếng Việt (Vietnamese)"
            icon: "translate"
            readonly property string value: "vi"
        },
        MenuItem {
            text: "English"
            icon: "language"
            readonly property string value: "en"
        },
        MenuItem {
            text: "Auto (Match Prompt)"
            icon: "auto_awesome"
            readonly property string value: "auto"
        }
    ]

    readonly property list<MenuItem> retentionItems: [
        MenuItem {
            text: "7 Days (1 Week)"
            icon: "schedule"
            readonly property int value: 7
        },
        MenuItem {
            text: "14 Days (2 Weeks)"
            icon: "schedule"
            readonly property int value: 14
        },
        MenuItem {
            text: "30 Days (1 Month)"
            icon: "calendar_month"
            readonly property int value: 30
        },
        MenuItem {
            text: "90 Days (3 Months)"
            icon: "calendar_month"
            readonly property int value: 90
        },
        MenuItem {
            text: "180 Days (6 Months)"
            icon: "calendar_month"
            readonly property int value: 180
        },
        MenuItem {
            text: "Never (Keep Forever)"
            icon: "all_inclusive"
            readonly property int value: 0
        }
    ]

    readonly property list<MenuItem> voiceModelItems: [
        MenuItem {
            text: "Whisper Tiny (Fastest Wake & Commands)"
            icon: "bolt"
            readonly property string value: "tiny"
        },
        MenuItem {
            text: "Whisper Base (Recommended Vietnamese)"
            icon: "graphic_eq"
            readonly property string value: "base"
        },
        MenuItem {
            text: "Whisper Small (Higher Accuracy)"
            icon: "high_quality"
            readonly property string value: "small"
        }
    ]

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Hero status card
        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: heroCol.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: heroCol
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: 46
                        implicitHeight: 46
                        radius: Tokens.rounding.extraLarge
                        color: AiAutomationService.cliInstalled && AiAutomationService.authStatus === "authenticated"
                            ? Colours.palette.m3primaryContainer
                            : Colours.palette.m3errorContainer

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "auto_awesome"
                            color: AiAutomationService.cliInstalled && AiAutomationService.authStatus === "authenticated"
                                ? Colours.palette.m3onPrimaryContainer
                                : Colours.palette.m3onErrorContainer
                            fontStyle: Tokens.font.icon.large
                            fill: 1
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: AiAutomationService.cliInstalled
                                ? `Antigravity CLI v${AiAutomationService.cliVersion || "installed"}`
                                : "Antigravity CLI (agy) Not Found"
                            font: Tokens.font.title.medium
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: AiAutomationService.cliInstalled
                                ? `${AiAutomationService.cliPath} • ${AiAutomationService.authDetail}`
                                : "Install Antigravity CLI to enable autonomous Agent A -> Agent B task execution."
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                            wrapMode: Text.WordWrap
                        }
                    }

                    StyledRect {
                        implicitWidth: badgeText.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: 26
                        radius: Tokens.rounding.full
                        color: {
                            if (!AiAutomationService.cliInstalled || AiAutomationService.authStatus === "unauthenticated")
                                return Colours.palette.m3errorContainer;
                            if (AiAutomationService.authStatus === "authenticated")
                                return Colours.palette.m3tertiaryContainer;
                            return Colours.palette.m3secondaryContainer;
                        }

                        StyledText {
                            id: badgeText
                            anchors.centerIn: parent
                            font: Tokens.font.label.small
                            text: {
                                if (!AiAutomationService.cliInstalled)
                                    return "Not Installed";
                                if (AiAutomationService.authStatus === "authenticated")
                                    return "Signed In";
                                if (AiAutomationService.authStatus === "checking")
                                    return "Checking...";
                                if (AiAutomationService.authStatus === "unauthenticated")
                                    return "Login Needed";
                                return "Detected";
                            }
                            color: {
                                if (!AiAutomationService.cliInstalled || AiAutomationService.authStatus === "unauthenticated")
                                    return Colours.palette.m3onErrorContainer;
                                if (AiAutomationService.authStatus === "authenticated")
                                    return Colours.palette.m3onTertiaryContainer;
                                return Colours.palette.m3onSecondaryContainer;
                            }
                        }
                    }
                }

                // Action buttons row
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    IconTextButton {
                        icon: "refresh"
                        text: AiAutomationService.checkingCli ? "Scanning..." : "Scan CLI & Models"
                        type: IconTextButton.Tonal
                        onClicked: {
                            AiAutomationService.refreshEnvironment();
                            AiAutomationService.verifyAuthLive();
                        }
                    }

                    IconTextButton {
                        visible: AiAutomationService.cliInstalled
                        icon: "login"
                        text: AiAutomationService.authStatus === "authenticated" ? "Account / Re-login" : "Sign In to Antigravity"
                        type: AiAutomationService.authStatus === "authenticated" ? IconTextButton.Tonal : IconTextButton.Filled
                        onClicked: AiAutomationService.openLoginTerminal()
                    }

                    IconTextButton {
                        visible: !AiAutomationService.cliInstalled
                        icon: "download"
                        text: "Install Antigravity CLI"
                        type: IconTextButton.Filled
                        onClicked: AiAutomationService.installCli()
                    }

                    IconTextButton {
                        icon: "forum"
                        text: "Open Meow AI Chat"
                        type: IconTextButton.Filled
                        onClicked: AiWindowFactory.create()
                    }

                    IconTextButton {
                        visible: AiAutomationService.hasActiveCooldowns()
                        icon: "restart_alt"
                        text: "Reset Quota Cooldowns"
                        type: IconTextButton.Tonal
                        onClicked: AiAutomationService.clearModelCooldowns()
                    }
                }

                // Inline test / quick launch box
                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 46
                    radius: Tokens.rounding.large
                    color: Colours.tPalette.m3surfaceContainer

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.padding.small
                        anchors.leftMargin: Tokens.padding.medium
                        spacing: Tokens.spacing.small

                        TextFieldBase {
                            id: quickPrompt
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            background: Item {}
                            leftPadding: 0
                            rightPadding: Tokens.padding.small
                            topPadding: 4
                            bottomPadding: 4
                            font: Tokens.font.body.small

                            onAccepted: {
                                const t = quickPrompt.text.trim();
                                if (!t)
                                    return;
                                quickPrompt.text = "";
                                AiAutomationService.runTask(t);
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !quickPrompt.text
                                text: "Run an AI task right now (or press SUPER + > anywhere)..."
                                color: Colours.palette.m3outline
                                font: Tokens.font.body.small
                            }
                        }

                        IconTextButton {
                            icon: "play_arrow"
                            text: "Run"
                            type: IconTextButton.Filled
                            onClicked: {
                                const t = quickPrompt.text.trim();
                                if (!t)
                                    return;
                                quickPrompt.text = "";
                                AiAutomationService.runTask(t);
                            }
                        }
                    }
                }
            }
        }

        // Section: Language, Models & Auto Quota Fallback
        SectionHeader {
            text: Tr.tr("Chat Language, Models & Failover")
        }

        SelectRow {
            first: true
            label: "AI Chat & Response Language"
            subtext: "Language used for plans, step updates, verification summaries & confirmation prompts"
            menuItems: root.languageItems
            active: root.languageItems.find(i => i.value === AiAutomationService.chatLanguage) ?? root.languageItems[0]
            onSelected: item => {
                AiAutomationService.chatLanguage = item.value;
                AiAutomationService.saveConfig();
            }
        }

        DialogSelectButton {
            id: supModelBtn
            rootParent: root.flickable
            icon: "auto_awesome"
            label: `Primary Coordinator Model: ${AiAutomationService.supervisorModel}`
            header: "Select Primary Coordinator Model"
            acceptLabel: "Select"
            model: AiAutomationService.availableModels
            onAccepted: {
                if (supModelBtn.selectedItem) {
                    AiAutomationService.supervisorModel = String(supModelBtn.selectedItem);
                    AiAutomationService.activeSupervisorModel = String(supModelBtn.selectedItem);
                    AiAutomationService.saveConfig();
                }
            }
        }

        DialogSelectButton {
            id: workModelBtn
            rootParent: root.flickable
            icon: "memory"
            label: `Task Execution Model: ${AiAutomationService.workerModel}`
            header: "Select Task Execution Model"
            acceptLabel: "Select"
            model: AiAutomationService.availableModels
            onAccepted: {
                if (workModelBtn.selectedItem) {
                    AiAutomationService.workerModel = String(workModelBtn.selectedItem);
                    AiAutomationService.activeWorkerModel = String(workModelBtn.selectedItem);
                    AiAutomationService.saveConfig();
                }
            }
        }

        ToggleRow {
            last: true
            text: "Auto-Switch Model When Quota Runs Out"
            subtext: "Automatically switch to the next fallback model on 429 / quota / rate-limit errors"
            checked: AiAutomationService.autoSwitchOnQuota
            onToggled: {
                AiAutomationService.autoSwitchOnQuota = checked;
                AiAutomationService.saveConfig();
            }
        }

        // Fallback Chain & Discovered Models List
        SectionHeader {
            text: `Available Models (${AiAutomationService.availableModels.length}) & Fallback Priority`
        }

        ConnectedRect {
            first: true
            last: true
            Layout.fillWidth: true
            implicitHeight: modelsCol.implicitHeight + Tokens.padding.medium * 2

            ColumnLayout {
                id: modelsCol
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    Layout.fillWidth: true
                    visible: AiAutomationService.availableModels.length === 0
                    text: "No models fetched yet. Click 'Scan CLI & Models' above."
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                Repeater {
                    model: AiAutomationService.availableModels

                    delegate: StyledRect {
                        id: modRow
                        required property var modelData
                        readonly property int fbIdx: (AiAutomationService.fallbackModels || []).indexOf(modelData.id)
                        readonly property bool inFallback: fbIdx >= 0

                        Layout.fillWidth: true
                        implicitHeight: 42
                        radius: Tokens.rounding.medium
                        color: inFallback
                            ? Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
                            : Colours.tPalette.m3surfaceContainerLow

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.small
                            spacing: Tokens.spacing.small

                            StyledText {
                                text: modRow.inFallback ? `#${modRow.fbIdx + 1}` : "—"
                                font: Tokens.font.label.medium
                                color: modRow.inFallback ? Colours.palette.m3primary : Colours.palette.m3outline
                                Layout.preferredWidth: 26
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    text: modRow.modelData.label
                                    font: Tokens.font.body.small
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                StyledText {
                                    text: modRow.modelData.id
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3outline
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            StyledRect {
                                id: cdBadge
                                readonly property bool cooled: AiAutomationService.cooldownSecondsLeft(modRow.modelData.id) > 0
                                implicitWidth: cdTxt.implicitWidth + Tokens.padding.medium
                                implicitHeight: 22
                                radius: Tokens.rounding.full
                                color: cooled ? Colours.palette.m3errorContainer : Colours.palette.m3tertiaryContainer

                                StyledText {
                                    id: cdTxt
                                    anchors.centerIn: parent
                                    text: AiAutomationService.cooldownLabel(modRow.modelData.id)
                                    font: Tokens.font.label.small
                                    color: cdBadge.cooled ? Colours.palette.m3onErrorContainer : Colours.palette.m3onTertiaryContainer
                                }
                            }

                            IconButton {
                                visible: modRow.inFallback
                                icon: "arrow_upward"
                                type: IconButton.Text
                                padding: Tokens.padding.extraSmall
                                enabled: modRow.fbIdx > 0
                                onClicked: AiAutomationService.moveFallbackModel(modRow.modelData.id, -1)
                            }

                            IconButton {
                                visible: modRow.inFallback
                                icon: "arrow_downward"
                                type: IconButton.Text
                                padding: Tokens.padding.extraSmall
                                enabled: modRow.fbIdx < (AiAutomationService.fallbackModels.length - 1)
                                onClicked: AiAutomationService.moveFallbackModel(modRow.modelData.id, 1)
                            }

                            StyledSwitch {
                                checked: modRow.inFallback
                                onToggled: AiAutomationService.toggleFallbackModel(modRow.modelData.id)
                            }
                        }
                    }
                }
            }
        }

        // Section: Permissions, Verification & Desktop Control
        SectionHeader {
            text: Tr.tr("Execution Permissions & Progress Display")
        }

        ToggleRow {
            first: true
            text: "Full Autonomous Execution (--dangerously-skip-permissions)"
            subtext: "Grant full non-interactive tool & command permissions during automated tasks"
            checked: AiAutomationService.fullPermissions
            onToggled: {
                AiAutomationService.fullPermissions = checked;
                AiAutomationService.saveConfig();
            }
        }

        ToggleRow {
            text: "Verify Result & Ask Confirmation If Invalid"
            subtext: "Audit output against your request after execution and pause to ask you if incomplete or wrong"
            checked: AiAutomationService.askOnInvalidResult
            onToggled: {
                AiAutomationService.askOnInvalidResult = checked;
                AiAutomationService.saveConfig();
            }
        }

        ToggleRow {
            text: "Show Background Terminal Window (Optional)"
            subtext: "When OFF, execution stays hidden and live steps stream directly inside the AI Chat window"
            checked: AiAutomationService.openWorkerTerminal
            onToggled: {
                AiAutomationService.openWorkerTerminal = checked;
                AiAutomationService.saveConfig();
            }
        }

        ToggleRow {
            text: "Allow Desktop, App Launch & Human-like Input"
            subtext: "Allow AI to open GUI apps, inspect screenshots (grim) & control cursor smoothly"
            checked: AiAutomationService.allowDesktopActions
            onToggled: {
                AiAutomationService.allowDesktopActions = checked;
                AiAutomationService.saveConfig();
            }
        }

        ToggleRow {
            text: "Show Live AI Ghost Cursor & Click Ripples"
            subtext: "Render animated pointer cursor & click ripples on screen during desktop automation"
            checked: AiAutomationService.showGhostCursor
            onToggled: {
                AiAutomationService.showGhostCursor = checked;
                AiAutomationService.saveConfig();
            }
        }

        ToggleRow {
            text: "Prefer Visual Mouse/UI Navigation"
            subtext: "Move cursor & click buttons visually on-screen (instead of silent curl/URL shortcuts)"
            checked: AiAutomationService.preferVisualCursor
            onToggled: {
                AiAutomationService.preferVisualCursor = checked;
                AiAutomationService.saveConfig();
            }
        }

        RowButton {
            last: true
            icon: AiAutomationService.ydotoolActive ? "mouse" : "play_circle"
            text: AiAutomationService.ydotoolActive
                ? "Human Input Daemon (ydotoold): Active"
                : "Human Input Daemon (ydotoold): Inactive — Click to Enable"
            subtext: "Enables simulated mouse clicks & keyboard typing for GUI automation"
            disabled: AiAutomationService.ydotoolActive
            onClicked: AiAutomationService.enableYdotool()
        }

        // Section: Push-to-Talk & Speech Output (Optional)
        SectionHeader {
            text: Tr.tr("Voice Input & Speech (Optional)")
        }

        ToggleRow {
            first: true
            text: "Speak AI Replies Aloud (Push-to-Talk Runs)"
            subtext: "Automatically speaks complete answers when you trigger AI via Speak Command Now"
            checked: AiAutomationService.voiceReplyEnabled
            onToggled: {
                AiAutomationService.voiceReplyEnabled = checked;
                AiAutomationService.saveConfig();
            }
        }

        SelectRow {
            label: "Speech Recognition Model"
            subtext: "Local faster-whisper model used for one-shot voice commands"
            menuItems: root.voiceModelItems
            active: root.voiceModelItems.find(i => i.value === AiAutomationService.voiceModel) ?? root.voiceModelItems[1]
            onSelected: item => {
                AiAutomationService.voiceModel = item.value;
                AiAutomationService.saveConfig();
            }
        }

        RowButton {
            last: true
            icon: "mic"
            text: "Speak Command Now (One-Shot Voice Prompt)"
            subtext: !AiAutomationService.voiceVenvInstalled
                ? "Voice runtime missing (~/.local/share/caelestia/voice-venv)"
                : "Click to record one Vietnamese/English voice command without always-on listening"
            disabled: !AiAutomationService.voiceVenvInstalled || AiAutomationService.running
            onClicked: AiAutomationService.listenVoiceOnce()
        }

        // Section: Self-Learning Knowledge Base
        SectionHeader {
            text: Tr.tr("Self-Learning Knowledge Base")
        }

        RowButton {
            first: true
            icon: "psychology"
            text: `Learned System Recipes (${AiAutomationService.learnedRecipeCount} rules) — Click to Sync AGENTS.md`
            subtext: AiAutomationService.learnedLatestNote
                ? `${AiAutomationService.learnedStatsText} • Latest: ${AiAutomationService.learnedLatestNote}`
                : AiAutomationService.learnedStatsText
            onClicked: AiAutomationService.rebuildKnowledgeMap()
        }

        RowButton {
            last: true
            icon: "delete_sweep"
            text: "Reset Learned Automation Memory"
            subtext: "Restore default core recipes and clear recorded run statistics"
            onClicked: AiAutomationService.clearKnowledge()
        }

        // Section: History & Execution Logs
        SectionHeader {
            text: Tr.tr("History & Execution Logs")
        }

        SelectRow {
            first: true
            label: "Auto-Delete History & Logs After"
            subtext: "Automatically clean up older conversations and execution log files"
            menuItems: root.retentionItems
            active: root.retentionItems.find(i => i.value === AiAutomationService.logRetentionDays) ?? root.retentionItems[2]
            onSelected: item => {
                AiAutomationService.logRetentionDays = item.value;
                AiAutomationService.saveConfig();
                AiAutomationService.pruneExpiredHistory();
            }
        }

        RowButton {
            icon: "cleaning_services"
            text: `Prune Expired Logs Now (${AiAutomationService.historySessions.length} chats • ${AiAutomationService.totalLogFiles} logs • ${AiAutomationService.formatBytes(AiAutomationService.totalLogBytes)})`
            subtext: "Delete conversations & logs exceeding your retention window"
            onClicked: AiAutomationService.pruneExpiredHistory()
        }

        RowButton {
            icon: "folder_open"
            text: "Open Persistent Logs Folder"
            subtext: AiAutomationService.logsDir
            onClicked: AiAutomationService.openLogsFolder()
        }

        RowButton {
            last: true
            icon: "delete_forever"
            text: "Clear All Chat History & Execution Logs"
            subtext: "Permanently remove all saved conversations and log files from disk"
            disabled: AiAutomationService.running || (AiAutomationService.historySessions.length === 0 && AiAutomationService.totalLogFiles === 0)
            onClicked: AiAutomationService.clearAllHistory()
        }

        // Section: Quick Access Shortcuts
        SectionHeader {
            text: Tr.tr("Launcher & Hotkeys")
        }

        RowButton {
            first: true
            last: true
            icon: "keyboard"
            text: "Quick AI Prompt: SUPER + >  (or type '>ai ' in Launcher)"
            subtext: "Launches straight into AI Auto Task prompt; type command and press Enter to execute"
            onClicked: Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "drawers", "openAiLauncher"])
        }
    }
}
