pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services
import qs.modules.nexus.common

PageBase {
    id: root

    property string searchQuery: ""

    title: Tr.tr("Colours")
    isSubPage: true

    Component.onCompleted: {
        Schemes.reload();
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // ---- Current Active Palette Preview ----------------------------------
        SectionHeader {
            first: true
            text: Tr.tr("Active palette")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: paletteCol.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: paletteCol

                anchors.centerIn: parent
                width: parent.width - Tokens.padding.largeIncreased * 2
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: "palette"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.large
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            text: `${Colours.scheme || "default"} • ${Colours.flavour || "default"}`
                            font: Tokens.font.title.medium
                        }

                        StyledText {
                            text: Tr.tr("Variant: %1 • Mode: %2").arg(Schemes.currentVariant || "tonalspot").arg(Colours.light ? Tr.tr("Light") : Tr.tr("Dark"))
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }
                    }
                }

                // Core M3 Swatches
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: [
                            { label: "Primary", col: Colours.palette.m3primary, onCol: Colours.palette.m3onPrimary },
                            { label: "Secondary", col: Colours.palette.m3secondary, onCol: Colours.palette.m3onSecondary },
                            { label: "Tertiary", col: Colours.palette.m3tertiary, onCol: Colours.palette.m3onTertiary },
                            { label: "Container", col: Colours.palette.m3primaryContainer, onCol: Colours.palette.m3onPrimaryContainer },
                            { label: "Surface", col: Colours.palette.m3surfaceContainerHigh, onCol: Colours.palette.m3onSurface },
                            { label: "Error", col: Colours.palette.m3error, onCol: Colours.palette.m3onError }
                        ]

                        StyledRect {
                            id: swatch

                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: Tokens.rounding.medium
                            color: modelData.col
                            border.width: 1
                            border.color: Qt.alpha(Colours.palette.m3outline, 0.3)

                            StyledText {
                                anchors.centerIn: parent
                                text: swatch.modelData.label
                                color: swatch.modelData.onCol
                                font: Tokens.font.label.small
                            }
                        }
                    }
                }

                // Terminal 0..15 ANSI strip
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: [
                            Colours.palette.term0, Colours.palette.term1, Colours.palette.term2, Colours.palette.term3,
                            Colours.palette.term4, Colours.palette.term5, Colours.palette.term6, Colours.palette.term7,
                            Colours.palette.term8, Colours.palette.term9, Colours.palette.term10, Colours.palette.term11,
                            Colours.palette.term12, Colours.palette.term13, Colours.palette.term14, Colours.palette.term15
                        ]

                        StyledRect {
                            required property color modelData

                            Layout.fillWidth: true
                            implicitHeight: 14
                            radius: Tokens.rounding.extraSmall
                            color: modelData
                        }
                    }
                }
            }
        }

        // ---- Mode & Dynamic Wallpaper Scheme ---------------------------------
        SectionHeader {
            text: Tr.tr("Theme mode & dynamic colours")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Dark theme")
            subtext: Tr.tr("Use dark surfaces across the shell and applications")
            checked: !Colours.light
            onToggled: Colours.setMode(checked ? "dark" : "light")
        }

        ToggleRow {
            text: Tr.tr("Smart colour scheme")
            subtext: Tr.tr("Automatically derive colours when changing wallpaper")
            checked: GlobalConfig.services.smartScheme
            onToggled: GlobalConfig.services.smartScheme = checked
        }

        RowButton {
            last: true
            icon: "auto_awesome"
            text: Tr.tr("Generate dynamic colours from current wallpaper")
            trailingIcon: "chevron_right"
            onClicked: {
                Quickshell.execDetached(["caelestia", "scheme", "set", "--notify", "-n", "dynamic"]);
                Qt.callLater(() => Schemes.reload());
            }
        }

        // ---- Material 3 Palette Variants -------------------------------------
        SectionHeader {
            text: Tr.tr("Material 3 palette variant")
        }

        Repeater {
            model: M3Variants.list

            ConnectedRect {
                id: variantCard

                required property var modelData
                required property int index
                readonly property bool isCurrent: Schemes.currentVariant === modelData.variant

                Layout.fillWidth: true
                first: index === 0
                last: index === M3Variants.list.length - 1
                implicitHeight: variantRow.implicitHeight + Tokens.padding.medium * 2

                StateLayer {
                    topLeftRadius: parent.topLeftRadius
                    topRightRadius: parent.topRightRadius
                    bottomLeftRadius: parent.bottomLeftRadius
                    bottomRightRadius: parent.bottomRightRadius
                    onClicked: {
                        Schemes.currentVariant = variantCard.modelData.variant;
                        Quickshell.execDetached(["caelestia", "scheme", "set", "--notify", "-v", variantCard.modelData.variant]);
                    }
                }

                RowLayout {
                    id: variantRow

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: 36
                        implicitHeight: 36
                        radius: Tokens.rounding.full
                        color: variantCard.isCurrent ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: variantCard.modelData.icon
                            color: variantCard.isCurrent ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                            fontStyle: Tokens.font.icon.medium
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: variantCard.modelData.name
                            font: Tokens.font.body.medium
                            color: variantCard.isCurrent ? Colours.palette.m3primary : Colours.palette.m3onSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: variantCard.modelData.description
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    MaterialIcon {
                        visible: variantCard.isCurrent
                        text: "check_circle"
                        fill: 1
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.medium
                    }
                }
            }
        }

        // ---- Colour Schemes & Flavours ---------------------------------------
        SectionHeader {
            text: Tr.tr("Colour schemes & presets")
        }

        StyledTextField {
            id: schemeSearch

            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.extraSmall
            Layout.bottomMargin: Tokens.spacing.small
            placeholderText: Tr.tr("Search colour schemes (e.g. catppuccin, rosepine, tokyonight, gruvbox)...")
            leadingIcon: "search"
            onTextEdited: root.searchQuery = text.trim().toLowerCase()
        }

        Repeater {
            id: schemeRepeater

            model: ScriptModel {
                values: {
                    const q = root.searchQuery;
                    const all = [...Schemes.list];
                    if (!q)
                        return all;
                    return all.filter(s => `${s.name} ${s.flavour}`.toLowerCase().includes(q));
                }
            }

            ConnectedRect {
                id: schemeRow

                required property var modelData
                required property int index
                readonly property bool isCurrent: (Colours.scheme === modelData.name && Colours.flavour === modelData.flavour) || (`${modelData.name} ${modelData.flavour}` === Schemes.currentScheme)

                Layout.fillWidth: true
                first: index === 0
                last: index === schemeRepeater.count - 1
                implicitHeight: schemeLayout.implicitHeight + Tokens.padding.medium * 2

                StateLayer {
                    topLeftRadius: parent.topLeftRadius
                    topRightRadius: parent.topRightRadius
                    bottomLeftRadius: parent.bottomLeftRadius
                    bottomRightRadius: parent.bottomRightRadius
                    onClicked: {
                        Schemes.currentScheme = `${schemeRow.modelData.name} ${schemeRow.modelData.flavour}`;
                        Quickshell.execDetached(["caelestia", "scheme", "set", "--notify", "-n", schemeRow.modelData.name, "-f", schemeRow.modelData.flavour]);
                    }
                }

                RowLayout {
                    id: schemeLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    // 4-colour preview pill
                    RowLayout {
                        spacing: 4

                        Repeater {
                            model: [
                                `#${schemeRow.modelData.colours?.surface ?? "1e1e2e"}`,
                                `#${schemeRow.modelData.colours?.primary ?? "cba6f7"}`,
                                `#${schemeRow.modelData.colours?.secondary ?? "f5c2e7"}`,
                                `#${schemeRow.modelData.colours?.tertiary ?? "94e2d5"}`
                            ]

                            StyledRect {
                                required property string modelData

                                implicitWidth: 18
                                implicitHeight: 28
                                radius: Tokens.rounding.small
                                color: modelData
                                border.width: 1
                                border.color: Qt.alpha(Colours.palette.m3outline, 0.35)
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: `${schemeRow.modelData.name} — ${schemeRow.modelData.flavour}`
                            font: Tokens.font.body.medium
                            color: schemeRow.isCurrent ? Colours.palette.m3primary : Colours.palette.m3onSurface
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: `#${schemeRow.modelData.colours?.primary ?? ""} • #${schemeRow.modelData.colours?.secondary ?? ""} • #${schemeRow.modelData.colours?.tertiary ?? ""}`
                            color: Colours.palette.m3outline
                            font: Tokens.font.mono.small
                            elide: Text.ElideRight
                        }
                    }

                    MaterialIcon {
                        visible: schemeRow.isCurrent
                        text: "check_circle"
                        fill: 1
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.medium
                    }
                }
            }
        }
    }
}
