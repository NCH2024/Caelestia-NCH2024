pragma Singleton

import QtQuick
import Caelestia.I18n

QtObject {
    id: root

    readonly property list<var> pages: [
        // Smart & Hardware
        {
            label: Tr.tr("Modes & Routines"),
            icon: "routine",
            description: Tr.tr("Usage profiles, If/Then automation"),
            category: "smart"
        },
        {
            label: Tr.tr("Power, Fans & Care"),
            icon: "shield_with_heart",
            description: Tr.tr("Power profiles, screen timeouts, fans, GPUs & RAM"),
            category: "smart"
        },

        // Appearance
        {
            label: Tr.tr("Wallpaper & style"),
            icon: "palette",
            description: Tr.tr("Wallpaper, Material 3 colours, desktop clock"),
            category: "appearance"
        },

        // Connectivity & Media
        {
            label: Tr.tr("Network"),
            icon: "wifi",
            description: Tr.tr("Wi-Fi, Ethernet, VPN & Quick DNS"),
            category: "connectivity"
        },
        {
            label: Tr.tr("Connected devices"),
            icon: "devices_other",
            description: Tr.tr("Bluetooth pairing, A2DP/HFP audio codec"),
            category: "connectivity",
            noFill: true
        },
        {
            label: Tr.tr("Audio & Equalizer"),
            icon: "equalizer",
            description: Tr.tr("10-band Studio EQ, boost, noise filter"),
            category: "connectivity"
        },

        // System & Hardware
        {
            label: Tr.tr("Disks & Storage"),
            icon: "hard_drive",
            description: Tr.tr("Partitions, Mount/Unmount, fstab, NTFS"),
            category: "system"
        },
        {
            label: Tr.tr("Updates & Drivers"),
            icon: "system_update_alt",
            description: Tr.tr("System updates, GPU drivers, firmware"),
            category: "system"
        },
        {
            label: Tr.tr("Daemons & Timers"),
            icon: "extension",
            description: Tr.tr("Scheduled tasks, background services, processes"),
            category: "system"
        },

        // Shell
        {
            label: Tr.tr("Panels & Taskbar"),
            icon: "dock_to_bottom",
            description: Tr.tr("Left bar, Dashboard, Launcher, Quick Settings"),
            category: "shell"
        },
        {
            label: Tr.tr("Apps"),
            icon: "apps",
            description: Tr.tr("Default apps, favourites, hidden apps"),
            category: "shell"
        },
        {
            label: Tr.tr("Services"),
            icon: "build",
            description: Tr.tr("Poll intervals, lyrics backend, notifications"),
            category: "shell"
        },
        {
            label: Tr.tr("Language, Region & Weather"),
            icon: "globe",
            description: Tr.tr("Weather location, units, time format"),
            category: "shell"
        },
        {
            label: Tr.tr("Keybinds & Shortcuts"),
            icon: "keyboard",
            description: Tr.tr("View system hotkeys & bind modes/commands"),
            category: "shell"
        },

        // AI Automation
        {
            label: Tr.tr("AI Automation"),
            icon: "auto_awesome",
            description: Tr.tr("Antigravity CLI, chat language, model failover & automation"),
            category: "ai"
        },

        // About
        {
            label: Tr.tr("About"),
            icon: "info",
            description: Tr.tr("System information, versions & credits"),
            category: "about"
        }
    ]
}
