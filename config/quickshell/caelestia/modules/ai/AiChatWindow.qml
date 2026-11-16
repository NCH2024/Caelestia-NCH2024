pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.containers
import qs.services

Item {
    id: root

    property bool pinned: false
    signal close()

    function roleBg(role: string): color {
        switch (role) {
        case "user":
            return Colours.palette.m3primaryContainer;
        case "assistant":
            return Colours.palette.m3secondaryContainer;
        case "execution":
            return Colours.layer(Colours.palette.m3surfaceContainerHigh, 2);
        case "question":
            return Colours.palette.m3errorContainer;
        default:
            return Colours.palette.m3tertiaryContainer;
        }
    }

    function roleFg(role: string): color {
        switch (role) {
        case "user":
            return Colours.palette.m3onPrimaryContainer;
        case "assistant":
            return Colours.palette.m3onSecondaryContainer;
        case "execution":
            return Colours.palette.m3onSurface;
        case "question":
            return Colours.palette.m3onErrorContainer;
        default:
            return Colours.palette.m3onTertiaryContainer;
        }
    }

    function roleIcon(role: string): string {
        switch (role) {
        case "user":
            return "person";
        case "assistant":
            return "auto_awesome";
        case "execution":
            return "memory";
        case "question":
            return "help";
        default:
            return "swap_horiz";
        }
    }

    function escapeHtml(s: string): string {
        return String(s || "")
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;");
    }

    function formatInline(s: string, codeBg: string, linkColor: string): string {
        let out = escapeHtml(s);
        // Inline code: `code`
        out = out.replace(/`([^`\n]+)`/g, `<code style="font-family: monospace; background-color: ${codeBg}; padding: 1px 4px;">$1</code>`);
        // Bold: **text** or __text__
        out = out.replace(/\*\*([^*\n]+)\*\*/g, "<b>$1</b>");
        out = out.replace(/__([^_\n]+)__/g, "<b>$1</b>");
        // Italic: *text*
        out = out.replace(/(^|[^*])\*([^*\n]+)\*(?!\*)/g, "$1<i>$2</i>");
        // Links: [text](url)
        out = out.replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, `<a href="$2" style="color: ${linkColor}; text-decoration: underline;">$1</a>`);
        return out;
    }

    function renderMarkdown(md: string, role: string): string {
        const text = String(md || "");
        if (!text)
            return "";

        const isUser = role === "user";
        const codeBg = isUser ? Qt.alpha(Colours.palette.m3onPrimaryContainer, 0.14) : Qt.alpha(Colours.palette.m3surface, 0.65);
        const tableBg = isUser ? Qt.alpha(Colours.palette.m3onPrimaryContainer, 0.08) : Qt.alpha(Colours.palette.m3surface, 0.45);
        const headerBg = isUser ? Qt.alpha(Colours.palette.m3onPrimaryContainer, 0.18) : Qt.alpha(Colours.palette.m3primary, 0.18);
        const accentColor = isUser ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3primary;
        const linkColor = accentColor;

        // Extract fenced code blocks first
        const codeBlocks = [];
        const tokenized = text.replace(/```([a-zA-Z0-9_+-]*)\n([\s\S]*?)```/g, function(_, lang, code) {
            const idx = codeBlocks.length;
            const langLabel = lang ? `<div style="font-size: 10px; font-weight: bold; color: ${accentColor}; margin-bottom: 4px;">${escapeHtml(lang.toUpperCase())}</div>` : "";
            const blockHtml = `<table width="100%" cellspacing="0" cellpadding="8" style="background-color: ${codeBg}; margin-top: 6px; margin-bottom: 6px;"><tr><td>${langLabel}<pre style="font-family: monospace; white-space: pre-wrap; margin: 0;">${escapeHtml(code.replace(/\n$/, ""))}</pre></td></tr></table>`;
            codeBlocks.push(blockHtml);
            return `@@CODEBLOCK_${idx}@@`;
        });

        const lines = tokenized.split(/\r?\n/);
        const htmlParts = [];
        let i = 0;

        while (i < lines.length) {
            const line = lines[i];
            const trimmed = line.trim();

            if (!trimmed) {
                i++;
                continue;
            }

            // Code block placeholder
            const cbMatch = trimmed.match(/^@@CODEBLOCK_(\d+)@@$/);
            if (cbMatch) {
                htmlParts.push(codeBlocks[parseInt(cbMatch[1])]);
                i++;
                continue;
            }

            // Horizontal rule
            if (/^(-{3,}|\*{3,}|_{3,})$/.test(trimmed)) {
                htmlParts.push("<hr/>");
                i++;
                continue;
            }

            // Headings
            const hMatch = trimmed.match(/^(#{1,4})\s+(.+)$/);
            if (hMatch) {
                const level = hMatch[1].length;
                const sizes = [16, 14, 13, 12];
                const sz = sizes[level - 1] || 12;
                htmlParts.push(`<p style="font-size: ${sz}px; font-weight: bold; color: ${accentColor}; margin-top: 6px; margin-bottom: 3px;">${formatInline(hMatch[2], codeBg, linkColor)}</p>`);
                i++;
                continue;
            }

            // Markdown table
            if (trimmed.startsWith("|") && i + 1 < lines.length && /^\|?[\s:-]+\|/.test(lines[i + 1].trim())) {
                const parseRow = r => r.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map(c => c.trim());
                const headers = parseRow(trimmed);
                i += 2; // skip header and separator
                let tableHtml = `<table width="100%" cellspacing="1" cellpadding="5" style="background-color: ${tableBg}; margin-top: 6px; margin-bottom: 6px;">`;
                tableHtml += `<tr style="background-color: ${headerBg};">` + headers.map(h => `<th align="left"><b>${formatInline(h, codeBg, linkColor)}</b></th>`).join("") + "</tr>";
                while (i < lines.length && lines[i].trim().startsWith("|")) {
                    const cols = parseRow(lines[i]);
                    tableHtml += "<tr>" + cols.map(c => `<td>${formatInline(c, codeBg, linkColor)}</td>`).join("") + "</tr>";
                    i++;
                }
                tableHtml += "</table>";
                htmlParts.push(tableHtml);
                continue;
            }

            // Blockquote
            if (trimmed.startsWith(">")) {
                const quoteLines = [];
                while (i < lines.length && lines[i].trim().startsWith(">")) {
                    quoteLines.push(lines[i].trim().replace(/^>\s?/, ""));
                    i++;
                }
                htmlParts.push(`<table width="100%" cellspacing="0" cellpadding="6" style="background-color: ${tableBg}; margin-top: 4px; margin-bottom: 4px;"><tr><td style="font-style: italic;">${quoteLines.map(q => formatInline(q, codeBg, linkColor)).join("<br/>")}</td></tr></table>`);
                continue;
            }

            // Unordered list
            if (/^[-*+]\s+/.test(trimmed)) {
                let listHtml = `<ul style="margin-top: 3px; margin-bottom: 3px; margin-left: -14px;">`;
                while (i < lines.length && /^\s*[-*+]\s+/.test(lines[i])) {
                    const item = lines[i].replace(/^\s*[-*+]\s+/, "");
                    listHtml += `<li style="margin-bottom: 2px;">${formatInline(item, codeBg, linkColor)}</li>`;
                    i++;
                }
                listHtml += "</ul>";
                htmlParts.push(listHtml);
                continue;
            }

            // Ordered list
            if (/^\d+\.\s+/.test(trimmed)) {
                let listHtml = `<ol style="margin-top: 3px; margin-bottom: 3px; margin-left: -14px;">`;
                while (i < lines.length && /^\s*\d+\.\s+/.test(lines[i])) {
                    const item = lines[i].replace(/^\s*\d+\.\s+/, "");
                    listHtml += `<li style="margin-bottom: 2px;">${formatInline(item, codeBg, linkColor)}</li>`;
                    i++;
                }
                listHtml += "</ol>";
                htmlParts.push(listHtml);
                continue;
            }

            // Normal paragraph
            const paraLines = [];
            while (i < lines.length) {
                const cur = lines[i].trim();
                if (!cur || /^@@CODEBLOCK_\d+@@$/.test(cur) || /^(#{1,4}\s+|[-*+]\s+|\d+\.\s+|>\s?|---|\*\*\*|\|)/.test(cur))
                    break;
                paraLines.push(formatInline(lines[i], codeBg, linkColor));
                i++;
            }
            if (paraLines.length > 0)
                htmlParts.push(`<p style="margin-top: 2px; margin-bottom: 4px;">${paraLines.join("<br/>")}</p>`);
        }

        return htmlParts.join("");
    }

    function roleName(role: string): string {
        switch (role) {
        case "user":
            return AiAutomationService.trChat("Bạn", "You");
        case "assistant":
            return "Meow AI";
        case "execution":
            return AiAutomationService.trChat("Tiến trình thực thi", "Execution Summary");
        case "question":
            return AiAutomationService.trChat("Meow AI • Cần xác nhận", "Meow AI • Confirmation");
        default:
            return AiAutomationService.trChat("Hệ thống", "System");
        }
    }

    function phaseLabel(): string {
        switch (AiAutomationService.currentPhase) {
        case "planning":
            return AiAutomationService.trChat("Đang lập kế hoạch", "Planning");
        case "working":
            return AiAutomationService.trChat("Đang thực thi", "Running");
        case "verifying":
            return AiAutomationService.trChat("Đang kiểm chứng", "Verifying");
        case "waiting_user":
            return AiAutomationService.trChat("Chờ xác nhận", "Needs Reply");
        case "done":
            return AiAutomationService.trChat("Hoàn tất", "Done");
        case "error":
            return AiAutomationService.trChat("Cần chú ý", "Attention");
        default:
            return AiAutomationService.trChat("Sẵn sàng", "Ready");
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        // Header bar
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.extraLarge
            color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

            RowLayout {
                id: headerRow
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.large
                anchors.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.small

                StyledRect {
                    implicitWidth: 34
                    implicitHeight: 34
                    radius: Tokens.rounding.full
                    color: AiAutomationService.running ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: AiAutomationService.hasPendingQuestion ? "help" : "auto_awesome"
                        color: AiAutomationService.running ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                        fontStyle: Tokens.font.icon.medium
                        fill: 1
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    StyledText {
                        text: "Meow AI Assistant"
                        font: Tokens.font.title.small
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        spacing: Tokens.spacing.small

                        StyledRect {
                            implicitWidth: phaseTxt.implicitWidth + Tokens.padding.medium
                            implicitHeight: 18
                            radius: Tokens.rounding.full
                            color: AiAutomationService.hasPendingQuestion
                                ? Colours.palette.m3errorContainer
                                : (AiAutomationService.running ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest)

                            StyledText {
                                id: phaseTxt
                                anchors.centerIn: parent
                                text: root.phaseLabel()
                                font: Tokens.font.label.small
                                color: AiAutomationService.hasPendingQuestion
                                    ? Colours.palette.m3onErrorContainer
                                    : (AiAutomationService.running ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant)
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: AiAutomationService.phaseDetail || AiAutomationService.trChat(
                                "Tự động lập kế hoạch, thực thi và đối chiếu kết quả ngay tại đây.",
                                "Plans, executes, and verifies desktop & shell tasks inline."
                            )
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }
                }

                // Optional raw log viewer
                IconButton {
                    visible: AiAutomationService.currentLogPath.length > 0
                    icon: "terminal"
                    type: IconButton.Text
                    padding: Tokens.padding.extraSmall
                    onClicked: AiAutomationService.openWorkerTerminalWindow()
                }

                IconButton {
                    icon: "keep"
                    type: IconButton.Text
                    padding: Tokens.padding.extraSmall
                    label.fill: root.pinned ? 1 : 0
                    inactiveOnColour: root.pinned ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    onClicked: {
                        root.pinned = !root.pinned;
                        Quickshell.execDetached([
                            "bash", "-c",
                            "hyprctl dispatch 'hl.dsp.window.pin({ window = \"title:^(Meow AI).*\" })' >/dev/null 2>&1 || hyprctl dispatch pin 'title:^(Meow AI).*' >/dev/null 2>&1 || true"
                        ]);
                    }
                }

                IconButton {
                    icon: "tune"
                    type: IconButton.Text
                    padding: Tokens.padding.extraSmall
                    onClicked: Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "nexus", "openPage", "14"])
                }

                IconButton {
                    visible: !AiAutomationService.running && AiAutomationService.chatMessages.length > 0
                    icon: "delete_sweep"
                    type: IconButton.Text
                    padding: Tokens.padding.extraSmall
                    onClicked: AiAutomationService.clearChat()
                }

                IconButton {
                    visible: AiAutomationService.running
                    icon: "stop_circle"
                    type: IconButton.Text
                    padding: Tokens.padding.extraSmall
                    inactiveOnColour: Colours.palette.m3error
                    onClicked: AiAutomationService.stopTask()
                }

                IconButton {
                    icon: "close"
                    type: IconButton.Text
                    padding: Tokens.padding.extraSmall
                    inactiveOnColour: Colours.palette.m3error
                    onClicked: root.close()
                }
            }
        }

        // Compact status + progress strip
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: telemetryCol.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.large
            color: Colours.layer(Colours.palette.m3surfaceContainerLow, 2)

            ColumnLayout {
                id: telemetryCol
                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.extraSmall

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    StyledText {
                        text: `${AiAutomationService.trChat("Điều phối", "Planner")}: ${AiAutomationService.activeSupervisorModel || AiAutomationService.supervisorModel}`
                        font: Tokens.font.label.small
                        color: Colours.palette.m3primary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: `${AiAutomationService.trChat("Thực thi", "Runner")}: ${AiAutomationService.activeWorkerModel || AiAutomationService.workerModel}`
                        font: Tokens.font.label.small
                        color: Colours.palette.m3secondary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: AiAutomationService.chatLanguage.toUpperCase()
                        font: Tokens.font.label.small
                        color: Colours.palette.m3tertiary
                    }
                }

                // Thin inline progress bar during execution
                StyledRect {
                    visible: AiAutomationService.running || AiAutomationService.currentPhase === "done"
                    Layout.fillWidth: true
                    implicitHeight: 4
                    radius: 2
                    color: Colours.palette.m3surfaceContainerHighest

                    StyledRect {
                        height: parent.height
                        radius: 2
                        width: parent.width * Math.max(0.06, Math.min(1.0, AiAutomationService.currentProgress / 100))
                        color: AiAutomationService.currentPhase === "done" ? Colours.palette.m3tertiary : Colours.palette.m3primary

                        Behavior on width {
                            Anim {}
                        }
                    }
                }
            }
        }

        // Chat Timeline
        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Tokens.rounding.extraLarge
            color: Colours.layer(Colours.palette.m3surfaceContainer, 1)

            ListView {
                id: chatList
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small
                clip: true

                model: AiAutomationService.chatMessages

                onCountChanged: Qt.callLater(() => chatList.positionViewAtEnd())

                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: chatList
                }

                header: Item {
                    width: chatList.width
                    height: AiAutomationService.chatMessages.length === 0 ? 180 : 0
                    visible: AiAutomationService.chatMessages.length === 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 32, 360)
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            Layout.alignment: Qt.AlignHCenter
                            text: "auto_awesome"
                            fontStyle: Tokens.font.icon.extraLarge
                            color: Colours.palette.m3primary
                            fill: 1
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: AiAutomationService.trChat("Trợ lý Tự động hóa Meow AI", "Meow AI Task Automation")
                            font: Tokens.font.title.small
                        }

                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: AiAutomationService.trChat(
                                "Nhấn SUPER + > hoặc nhập >ai <câu lệnh> từ Launcher. Tiến trình thực thi và đối chiếu kết quả sẽ hiển thị trực tiếp tại đây.",
                                "Press SUPER + > or type >ai <task> from the Launcher. Execution steps and verification render directly in this chat."
                            )
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }

                footer: Item {
                    width: chatList.width
                    height: liveBox.visible ? liveBox.implicitHeight + Tokens.spacing.small : 0

                    // Embedded Live Progress Card (replaces popup terminal window)
                    StyledRect {
                        id: liveBox
                        visible: AiAutomationService.running
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: Tokens.spacing.extraSmall
                        implicitHeight: liveCol.implicitHeight + Tokens.padding.medium * 2
                        radius: Tokens.rounding.large
                        color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

                        onImplicitHeightChanged: Qt.callLater(() => chatList.positionViewAtEnd())

                        ColumnLayout {
                            id: liveCol
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.extraSmall

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    text: "progress_activity"
                                    fontStyle: Tokens.font.icon.small
                                    color: Colours.palette.m3primary
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: AiAutomationService.phaseDetail || AiAutomationService.trChat("Đang xử lý tác vụ...", "Processing task...")
                                    font: Tokens.font.label.medium
                                    color: Colours.palette.m3primary
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    text: `${AiAutomationService.currentProgress}%`
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3onSurfaceVariant
                                }
                            }

                            // Recent tool execution steps inline
                            Repeater {
                                model: AiAutomationService.liveSteps.slice(-6)

                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: Tokens.spacing.small

                                    MaterialIcon {
                                        text: "terminal"
                                        fontStyle: Tokens.font.icon.small
                                        color: Colours.palette.m3secondary
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: `${modelData.ts}  ${modelData.label}`
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3onSurfaceVariant
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: AiAutomationService.streamingWorkerText.length > 0
                                text: AiAutomationService.streamingWorkerText
                                wrapMode: Text.WordWrap
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurface
                            }
                        }
                    }
                }

                delegate: Item {
                    id: msgWrap
                    required property var modelData
                    required property int index

                    readonly property bool isUser: modelData.role === "user"
                    readonly property bool isSystem: modelData.role === "system"

                    width: chatList.width
                    implicitHeight: bubble.implicitHeight

                    StyledRect {
                        id: bubble

                        property bool copied: false

                        width: msgWrap.isSystem ? parent.width : Math.min(parent.width * 0.92, parent.width - 24)
                        anchors.right: msgWrap.isUser ? parent.right : undefined
                        anchors.left: msgWrap.isUser ? undefined : parent.left
                        implicitHeight: bubbleCol.implicitHeight + Tokens.padding.medium * 2
                        radius: Tokens.rounding.large
                        color: root.roleBg(msgWrap.modelData.role)

                        Timer {
                            id: copyResetTimer
                            interval: 1500
                            onTriggered: bubble.copied = false
                        }

                        ColumnLayout {
                            id: bubbleCol
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.small

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    text: root.roleIcon(msgWrap.modelData.role)
                                    fontStyle: Tokens.font.icon.small
                                    color: root.roleFg(msgWrap.modelData.role)
                                    fill: 1
                                }

                                StyledText {
                                    text: `${root.roleName(msgWrap.modelData.role)} • ${msgWrap.modelData.title}`
                                    font: Tokens.font.label.medium
                                    color: root.roleFg(msgWrap.modelData.role)
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    visible: Boolean(msgWrap.modelData.model)
                                    text: msgWrap.modelData.model
                                    font: Tokens.font.label.small
                                    color: Qt.alpha(root.roleFg(msgWrap.modelData.role), 0.75)
                                }

                                StyledText {
                                    text: msgWrap.modelData.ts
                                    font: Tokens.font.label.small
                                    color: Qt.alpha(root.roleFg(msgWrap.modelData.role), 0.65)
                                }

                                MouseArea {
                                    id: copyBtn
                                    implicitWidth: 20
                                    implicitHeight: 20
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Quickshell.clipboardText = msgWrap.modelData.text;
                                        bubble.copied = true;
                                        copyResetTimer.restart();
                                    }

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        text: bubble.copied ? "check" : "content_copy"
                                        fontStyle: Tokens.font.icon.small
                                        color: bubble.copied
                                            ? Colours.palette.m3primary
                                            : Qt.alpha(root.roleFg(msgWrap.modelData.role), copyBtn.containsMouse ? 0.95 : 0.55)
                                    }
                                }
                            }

                            TextEdit {
                                Layout.fillWidth: true
                                readOnly: true
                                selectByMouse: true
                                textFormat: Text.RichText
                                text: root.renderMarkdown(msgWrap.modelData.text, msgWrap.modelData.role)
                                wrapMode: Text.WordWrap
                                font: Tokens.font.body.medium
                                color: root.roleFg(msgWrap.modelData.role)
                                selectionColor: Colours.palette.m3primary
                                selectedTextColor: Colours.palette.m3onPrimary
                                onLinkActivated: link => Qt.openUrlExternally(link)
                            }
                        }
                    }
                }
            }
        }

        // Interactive Confirmation Card
        StyledRect {
            visible: AiAutomationService.hasPendingQuestion
            Layout.fillWidth: true
            implicitHeight: confirmCol.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.extraLarge
            color: Colours.palette.m3errorContainer

            ColumnLayout {
                id: confirmCol
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                RowLayout {
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "warning"
                        color: Colours.palette.m3onErrorContainer
                        fontStyle: Tokens.font.icon.medium
                        fill: 1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: AiAutomationService.trChat(
                            "Kết quả chưa khớp hoặc cần xác nhận. Nhập phản hồi bên dưới hoặc chọn thao tác:",
                            "Verification flagged an issue. Type instructions below or choose an action:"
                        )
                        font: Tokens.font.label.medium
                        color: Colours.palette.m3onErrorContainer
                        wrapMode: Text.WordWrap
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    IconTextButton {
                        icon: "refresh"
                        text: AiAutomationService.trChat("Thử lại", "Retry")
                        type: IconTextButton.Filled
                        onClicked: {
                            const txt = promptInput.text.trim();
                            promptInput.text = "";
                            AiAutomationService.sendReply("retry", txt);
                        }
                    }

                    IconTextButton {
                        icon: "check"
                        text: AiAutomationService.trChat("Chấp nhận", "Accept")
                        type: IconTextButton.Tonal
                        onClicked: AiAutomationService.sendReply("accept", "")
                    }

                    IconTextButton {
                        icon: "close"
                        text: AiAutomationService.trChat("Hủy bỏ", "Abort")
                        type: IconTextButton.Text
                        onClicked: AiAutomationService.sendReply("abort", "")
                    }
                }
            }
        }

        // Bottom task/reply input (TextFieldBase supports fcitx5 Vietnamese IME cleanly)
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: Math.max(48, inputRow.implicitHeight + Tokens.padding.small * 2)
            radius: Tokens.rounding.extraLarge
            color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

            RowLayout {
                id: inputRow
                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                anchors.leftMargin: Tokens.padding.medium
                spacing: Tokens.spacing.small

                TextFieldBase {
                    id: promptInput
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    background: Item {}
                    leftPadding: Tokens.padding.small
                    rightPadding: Tokens.padding.small
                    topPadding: 6
                    bottomPadding: 6
                    font: Tokens.font.body.small

                    onAccepted: {
                        const txt = promptInput.text.trim();
                        if (!txt)
                            return;
                        promptInput.text = "";
                        AiAutomationService.runTask(txt);
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Tokens.padding.small
                        visible: !promptInput.text
                        text: AiAutomationService.hasPendingQuestion
                            ? AiAutomationService.trChat("Nhập hướng dẫn sửa và nhấn Enter...", "Type guidance and press Enter...")
                            : AiAutomationService.trChat("Nhập yêu cầu mới (sẽ làm mới đoạn chat)...", "Type a new automation task (starts fresh chat)...")
                        color: Colours.palette.m3outline
                        font: Tokens.font.body.small
                    }

                    Component.onCompleted: Qt.callLater(() => promptInput.forceActiveFocus())
                }

                IconButton {
                    icon: "send"
                    type: IconButton.Filled
                    enabled: promptInput.text.trim().length > 0 && (!AiAutomationService.running || AiAutomationService.hasPendingQuestion)
                    onClicked: {
                        const txt = promptInput.text.trim();
                        if (!txt)
                            return;
                        promptInput.text = "";
                        AiAutomationService.runTask(txt);
                    }
                }
            }
        }
    }
}
