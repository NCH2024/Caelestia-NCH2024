pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property list<var> physicalDisks: []
    property list<var> partitions: []
    property string fstabContent: ""
    property string editingPartPath: ""
    property bool scanning: false

    function refreshDisks(): void {
        if (root.scanning)
            return;
        root.scanning = true;
        fstabFile.reload();
        lsblkProc.running = true;
    }

    function isUuidInFstab(uuid: string): bool {
        if (!uuid || !root.fstabContent)
            return false;
        const lines = root.fstabContent.split("\n");
        for (const raw of lines) {
            const line = raw.trim();
            if (!line || line.startsWith("#"))
                continue;
            if (line.includes(uuid))
                return true;
        }
        return false;
    }

    function toggleMount(part: var): void {
        if (!part || !part.path)
            return;
        if (part.mountpoint) {
            if (part.mountpoint === "/" || part.mountpoint === "/boot" || part.mountpoint === "[SWAP]")
                return;
            TaskRunner.run(
                `Unmount ${part.path} (${part.label || part.name})`,
                `udisksctl unmount -b "${part.path}" 2>/dev/null || pkexec umount "${part.path}"`,
                false,
                "eject"
            );
        } else {
            const mp = `/mnt/${part.label || part.uuid || part.name}`;
            TaskRunner.run(
                `Mount ${part.path} (${part.label || part.name})`,
                `udisksctl mount -b "${part.path}" 2>/dev/null || pkexec bash -c 'mkdir -p "${mp}" && mount "${part.path}" "${mp}"'`,
                false,
                "hard_drive"
            );
        }
        reloadTimer.restart();
    }

    function toggleAutoMountFstab(part: var, enable: bool, customMountPoint: string, customOpts: string): void {
        if (!part || !part.uuid)
            return;
        const uuid = part.uuid;
        const safeName = (part.label || uuid).replace(/[^a-zA-Z0-9_-]/g, "_");
        const targetMp = (customMountPoint && customMountPoint.trim().length > 0) ? customMountPoint.trim() : `/mnt/${safeName}`;
        const isNtfsOrFat = ["ntfs", "vfat", "exfat"].includes(String(part.fstype).toLowerCase());
        const defaultOpts = isNtfsOrFat
            ? `nosuid,nodev,nofail,x-gvfs-show,x-gvfs-name=${safeName},uid=1001,gid=1001,umask=0022`
            : `defaults,noatime,nofail,x-gvfs-show`;
        const opts = (customOpts && customOpts.trim().length > 0) ? customOpts.trim() : defaultOpts;

        if (enable) {
            const line = `/dev/disk/by-uuid/${uuid} ${targetMp} auto ${opts} 0 0`;
            const cmd = `
                cp /etc/fstab /etc/fstab.caelestia.bak
                sed -i "\\|${uuid}|d" /etc/fstab
                mkdir -p "${targetMp}"
                echo '${line}' >> /etc/fstab
                systemctl daemon-reload
                mount "${targetMp}" 2>/dev/null || true
                echo "Configured auto-mount for ${part.path} at ${targetMp}"
            `;
            TaskRunner.run(`Enable Auto-Mount for ${part.label || part.name}`, cmd, true, "save");
        } else {
            const cmd = `
                cp /etc/fstab /etc/fstab.caelestia.bak
                sed -i "\\|${uuid}|d" /etc/fstab
                systemctl daemon-reload
                echo "Removed ${part.label || part.name} from /etc/fstab"
            `;
            TaskRunner.run(`Disable Auto-Mount for ${part.label || part.name}`, cmd, true, "delete");
        }
        reloadTimer.restart();
    }

    function fixNtfsPartition(part: var): void {
        if (!part || !part.path)
            return;
        const cmd = `
            umount "${part.path}" 2>/dev/null || true
            if command -v ntfsfix >/dev/null 2>&1; then
                ntfsfix -d "${part.path}"
            else
                pacman -S --noconfirm ntfs-3g && ntfsfix -d "${part.path}"
            fi
            mount -a 2>/dev/null || udisksctl mount -b "${part.path}" 2>/dev/null || true
        `;
        TaskRunner.run(`Repair NTFS Partition (${part.path})`, cmd, true, "build");
        reloadTimer.restart();
    }

    title: Tr.tr("Disks & Storage")

    Component.onCompleted: refreshDisks()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Timer {
            id: reloadTimer

            interval: 1500
            onTriggered: root.refreshDisks()
        }

        FileView {
            id: fstabFile

            printErrors: false
            path: "/etc/fstab"
            onLoaded: root.fstabContent = text()
        }

        Process {
            id: lsblkProc

            command: ["lsblk", "-J", "-o", "NAME,KNAME,PATH,TYPE,FSTYPE,LABEL,UUID,SIZE,FSUSED,FSAVAIL,FSUSE%,MOUNTPOINT,MODEL,ROTA,TRAN,RM"]
            stdout: StdioCollector {
                onStreamFinished: {
                    root.scanning = false;
                    try {
                        const data = JSON.parse(text);
                        const disks = [];
                        const parts = [];
                        for (const dev of (data.blockdevices || [])) {
                            if (dev.type === "disk" && dev.name !== "zram0") {
                                disks.push({
                                    name: dev.name,
                                    path: dev.path,
                                    model: dev.model || "Storage Drive",
                                    size: dev.size || "",
                                    tran: (dev.tran || (dev.rota ? "HDD" : "SSD")).toUpperCase(),
                                    removable: Boolean(dev.rm),
                                    partCount: (dev.children || []).length
                                });
                                for (const ch of (dev.children || [])) {
                                    if (!ch.fstype && !ch.mountpoint && !ch.uuid)
                                        continue;
                                    const usePctStr = String(ch["fsuse%"] || "0").replace("%", "");
                                    parts.push({
                                        diskName: dev.name,
                                        diskModel: dev.model || dev.name,
                                        name: ch.name,
                                        path: ch.path,
                                        fstype: ch.fstype || "raw",
                                        label: ch.label || "",
                                        uuid: ch.uuid || "",
                                        size: ch.size || "",
                                        fsused: ch.fsused || "0B",
                                        fsavail: ch.fsavail || "",
                                        usePct: parseInt(usePctStr, 10) || 0,
                                        mountpoint: ch.mountpoint || ""
                                    });
                                }
                            }
                        }
                        root.physicalDisks = disks;
                        root.partitions = parts;
                    } catch (e) {}
                }
            }
        }

        // Physical Drives Overview
        SectionHeader {
            first: true
            text: `Physical Drives (${root.physicalDisks.length})`
        }

        Repeater {
            model: root.physicalDisks

            delegate: ConnectedRect {
                id: diskCard

                required property var modelData
                required property int index

                Layout.fillWidth: true
                implicitHeight: diskRow.implicitHeight + Tokens.padding.large * 2
                first: index === 0
                last: index === root.physicalDisks.length - 1

                RowLayout {
                    id: diskRow

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: 44
                        implicitHeight: 44
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primaryContainer

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: diskCard.modelData.removable ? "usb" : "hard_drive"
                            color: Colours.palette.m3onPrimaryContainer
                            fontStyle: Tokens.font.icon.medium
                            fill: 1
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: `${diskCard.modelData.model}  (${diskCard.modelData.path})`
                            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: `Bus: ${diskCard.modelData.tran}  •  Capacity: ${diskCard.modelData.size}  •  ${diskCard.modelData.partCount} partitions`
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                        }
                    }

                    IconButton {
                        icon: "refresh"
                        type: IconButton.Text
                        padding: Tokens.padding.small
                        onClicked: root.refreshDisks()
                    }
                }
            }
        }

        // Partitions & Mount Controls
        SectionHeader {
            text: Tr.tr("Partitions & Mount Management (/etc/fstab)")
        }

        Repeater {
            model: root.partitions

            delegate: ConnectedRect {
                id: partCard

                required property var modelData
                required property int index
                readonly property bool isMounted: Boolean(modelData.mountpoint && modelData.mountpoint.length > 0)
                readonly property bool isSystemPart: modelData.mountpoint === "/" || modelData.mountpoint === "/boot"
                readonly property bool isAutoMounted: root.isUuidInFstab(modelData.uuid)
                readonly property bool isExpanded: root.editingPartPath === modelData.path

                Layout.fillWidth: true
                implicitHeight: partCol.implicitHeight + Tokens.padding.large * 2
                first: index === 0
                last: index === root.partitions.length - 1

                ColumnLayout {
                    id: partCol

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.small

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        StyledRect {
                            implicitWidth: 42
                            implicitHeight: 42
                            radius: Tokens.rounding.full
                            color: partCard.isMounted ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: partCard.isSystemPart ? "dns" : (partCard.isMounted ? "folder_managed" : "folder_off")
                                color: partCard.isMounted ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                fontStyle: Tokens.font.icon.medium
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small

                                StyledText {
                                    text: partCard.modelData.label ? `${partCard.modelData.label} (${partCard.modelData.path})` : partCard.modelData.path
                                    font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                                }

                                StyledRect {
                                    implicitWidth: fsTxt.implicitWidth + 12
                                    implicitHeight: 20
                                    radius: 6
                                    color: Colours.palette.m3secondaryContainer

                                    StyledText {
                                        id: fsTxt

                                        anchors.centerIn: parent
                                        text: String(partCard.modelData.fstype).toUpperCase()
                                        color: Colours.palette.m3onSecondaryContainer
                                        font: Tokens.font.label.small
                                    }
                                }

                                StyledRect {
                                    visible: partCard.isAutoMounted
                                    implicitWidth: fstabBadge.implicitWidth + 12
                                    implicitHeight: 20
                                    radius: 6
                                    color: Colours.palette.m3tertiaryContainer

                                    StyledText {
                                        id: fstabBadge

                                        anchors.centerIn: parent
                                        text: "Auto-Mount (fstab)"
                                        color: Colours.palette.m3onTertiaryContainer
                                        font: Tokens.font.label.small
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: partCard.isMounted
                                    ? `Mounted at: ${partCard.modelData.mountpoint}  •  Used: ${partCard.modelData.fsused} / ${partCard.modelData.size} (${partCard.modelData.fsavail} free)`
                                    : `Unmounted  •  Size: ${partCard.modelData.size}  •  UUID: ${partCard.modelData.uuid}`
                                color: partCard.isMounted ? Colours.palette.m3primary : Colours.palette.m3outline
                                font: Tokens.font.label.small
                                elide: Text.ElideRight
                            }
                        }

                        IconButton {
                            visible: partCard.isMounted
                            icon: "folder_open"
                            type: IconButton.Tonal
                            padding: Tokens.padding.small
                            onClicked: Quickshell.execDetached(["xdg-open", partCard.modelData.mountpoint])
                        }

                        StyledRect {
                            visible: !partCard.isSystemPart
                            implicitWidth: mntBtnTxt.implicitWidth + Tokens.padding.medium * 2
                            implicitHeight: 34
                            radius: Tokens.rounding.full
                            color: partCard.isMounted ? Colours.palette.m3errorContainer : Colours.palette.m3primary

                            StateLayer {
                                radius: parent.radius
                                onClicked: root.toggleMount(partCard.modelData)
                            }

                            StyledText {
                                id: mntBtnTxt

                                anchors.centerIn: parent
                                text: partCard.isMounted ? "Unmount" : "Mount"
                                color: partCard.isMounted ? Colours.palette.m3onErrorContainer : Colours.palette.m3onPrimary
                                font: Tokens.font.label.small
                            }
                        }

                        IconButton {
                            icon: partCard.isExpanded ? "expand_less" : "tune"
                            type: IconButton.Text
                            padding: Tokens.padding.small
                            onClicked: root.editingPartPath = partCard.isExpanded ? "" : partCard.modelData.path
                        }
                    }

                    StyledProgressBar {
                        visible: partCard.isMounted && partCard.modelData.usePct > 0
                        Layout.fillWidth: true
                        implicitHeight: 6
                        value: partCard.modelData.usePct / 100.0
                    }

                    StyledRect {
                        visible: partCard.isExpanded
                        Layout.fillWidth: true
                        implicitHeight: advCol.implicitHeight + Tokens.padding.medium * 2
                        radius: Tokens.rounding.medium
                        color: Colours.palette.m3surfaceContainerHighest

                        ColumnLayout {
                            id: advCol

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.small

                            StyledText {
                                text: `Mount Options & Partition Tools (${partCard.modelData.path})`
                                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                            }

                            StyledText {
                                text: `UUID: ${partCard.modelData.uuid}  •  Drive: ${partCard.modelData.diskModel}`
                                color: Colours.palette.m3outline
                                font: Tokens.font.mono.small
                            }

                            RowLayout {
                                visible: !partCard.isSystemPart
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small

                                StyledRect {
                                    Layout.fillWidth: true
                                    implicitHeight: 36
                                    radius: Tokens.rounding.small
                                    color: Colours.palette.m3surfaceContainerLowest

                                    StyledTextField {
                                        id: customMpField

                                        anchors.fill: parent
                                        anchors.leftMargin: Tokens.padding.medium
                                        anchors.rightMargin: Tokens.padding.medium
                                        verticalAlignment: TextInput.AlignVCenter
                                        text: partCard.modelData.mountpoint || `/mnt/${partCard.modelData.label || partCard.modelData.uuid}`
                                        placeholderText: "Mount path (e.g. /mnt/Data)..."
                                    }
                                }

                                StyledRect {
                                    implicitWidth: applyFstabTxt.implicitWidth + Tokens.padding.medium * 2
                                    implicitHeight: 36
                                    radius: Tokens.rounding.small
                                    color: Colours.palette.m3primary

                                    StateLayer {
                                        radius: parent.radius
                                        onClicked: root.toggleAutoMountFstab(partCard.modelData, true, customMpField.text, "")
                                    }

                                    StyledText {
                                        id: applyFstabTxt

                                        anchors.centerIn: parent
                                        text: "Save Auto-Mount (fstab)"
                                        color: Colours.palette.m3onPrimary
                                        font: Tokens.font.label.small
                                    }
                                }

                                StyledRect {
                                    visible: partCard.isAutoMounted
                                    implicitWidth: rmFstabTxt.implicitWidth + Tokens.padding.medium * 2
                                    implicitHeight: 36
                                    radius: Tokens.rounding.small
                                    color: Colours.palette.m3errorContainer

                                    StateLayer {
                                        radius: parent.radius
                                        onClicked: root.toggleAutoMountFstab(partCard.modelData, false, "", "")
                                    }

                                    StyledText {
                                        id: rmFstabTxt

                                        anchors.centerIn: parent
                                        text: "Remove from fstab"
                                        color: Colours.palette.m3onErrorContainer
                                        font: Tokens.font.label.small
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small

                                StyledRect {
                                    visible: String(partCard.modelData.fstype).toLowerCase() === "ntfs"
                                    implicitWidth: ntfsFixTxt.implicitWidth + Tokens.padding.medium * 2
                                    implicitHeight: 32
                                    radius: Tokens.rounding.full
                                    color: Colours.palette.m3secondaryContainer

                                    StateLayer {
                                        radius: parent.radius
                                        onClicked: root.fixNtfsPartition(partCard.modelData)
                                    }

                                    StyledText {
                                        id: ntfsFixTxt

                                        anchors.centerIn: parent
                                        text: "Fix NTFS Dirty Bit (ntfsfix -d)"
                                        color: Colours.palette.m3onSecondaryContainer
                                        font: Tokens.font.label.small
                                    }
                                }

                                StyledRect {
                                    implicitWidth: benchTxt.implicitWidth + Tokens.padding.medium * 2
                                    implicitHeight: 32
                                    radius: Tokens.rounding.full
                                    color: Colours.palette.m3surfaceContainer

                                    StateLayer {
                                        radius: parent.radius
                                        onClicked: TaskRunner.run(
                                            `Read Speed Benchmark (${partCard.modelData.path})`,
                                            `dd if="${partCard.modelData.path}" of=/dev/null bs=1M count=256 status=progress 2>&1`,
                                            true,
                                            "speed"
                                        )
                                    }

                                    StyledText {
                                        id: benchTxt

                                        anchors.centerIn: parent
                                        text: "Benchmark Read Speed (256 MB)"
                                        color: Colours.palette.m3onSurface
                                        font: Tokens.font.label.small
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Global Storage Actions
        SectionHeader {
            text: Tr.tr("Storage Maintenance")
        }

        RowButton {
            first: true
            icon: "play_for_work"
            text: Tr.tr("Mount All Configured Partitions (mount -a)")
            subtext: Tr.tr("Mount all drives configured in /etc/fstab immediately")
            onClicked: {
                TaskRunner.run("Mount All (/etc/fstab)", "mount -a && echo 'All /etc/fstab partitions mounted.'", true, "hard_drive");
                reloadTimer.restart();
            }
        }

        RowButton {
            last: true
            icon: "speed"
            text: Tr.tr("Optimize NVMe SSDs (fstrim -av)")
            subtext: Tr.tr("Discard unused blocks across all mounted SSD filesystems")
            onClicked: TaskRunner.run("NVMe SSD TRIM (fstrim -av)", "fstrim -av", true, "speed")
        }
    }
}
