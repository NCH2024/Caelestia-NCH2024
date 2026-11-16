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
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    property bool showAllEqBands: true

    title: Tr.tr("Audio & Studio Equalizer")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Output Section
        SectionHeader {
            first: true
            text: Tr.tr("Audio Output")
        }

        SliderRow {
            first: true
            icon: Icons.getVolumeIcon(Audio.volume, Audio.muted)
            label: Tr.trCtx("Output volume", "audio output")
            valueLabel: Strings.percentOne(value)
            from: 0
            to: EqualizerService.volumeOverdrive ? 1.5 : 1.0
            value: Audio.volume
            enabled: !Audio.muted
            onMoved: v => {
                if (EqualizerService.volumeOverdrive && v > 1.0)
                    EqualizerService.setOverdriveVolume(Math.round(v * 100));
                else
                    Audio.setVolume(v);
            }
        }

        ToggleRow {
            text: Tr.tr("Volume Overdrive Boost (Up to 150%)")
            subtext: Tr.tr("Allow amplifying speaker/headphone volume beyond 100%")
            checked: EqualizerService.volumeOverdrive
            onToggled: {
                EqualizerService.volumeOverdrive = checked;
                EqualizerService.saveState();
            }
        }

        SliderRow {
            icon: "speaker_group"
            label: Tr.tr("Channel Balance (Left / Right)")
            valueLabel: {
                const b = Math.round(value * 100);
                if (b === 0)
                    return "Center (0)";
                return b < 0 ? `Left ${Math.abs(b)}%` : `Right ${b}%`;
            }
            from: -1.0
            to: 1.0
            value: EqualizerService.balance
            onMoved: v => EqualizerService.setChannelBalance(v)
        }

        ToggleRow {
            text: Tr.trCtx("Mute output", "audio output muted")
            checked: Audio.muted
            onToggled: Audio.setStreamMuted(Audio.sink, checked)
        }

        AudioDeviceList {
            nodes: Audio.sinks.filter(s => !String(s.name ?? "").includes("caelestia_eq"))
            currentId: Audio.sink?.id ?? -1
            iconName: "speaker"
            placeholderIcon: "speaker"
            placeholderText: Tr.trCtx("No output devices", "no audio outputs")
            onSelected: node => Audio.setAudioSink(node)
        }

        NavRow {
            last: true
            icon: "tune"
            text: Tr.tr("App Volume Mixer")
            subtext: Audio.streams.length === 0 ? Tr.tr("No apps playing audio") : Tr.trN("%n app playing audio", "%n apps playing audio", Audio.streams.length)
            onClicked: root.nState.openSubPage(1)
        }

        // 10-Band Equalizer & Sound Effects Studio
        SectionHeader {
            text: Tr.tr("10-Band Studio Equalizer & DSP Effects")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Enable Studio Equalizer")
            subtext: EqualizerService.enabled
                ? `Active — Preset: ${EqualizerService.activePresetName}`
                : "Bypassed (Direct hardware audio pass-through)"
            checked: EqualizerService.enabled
            onToggled: {
                EqualizerService.enabled = checked;
                EqualizerService.scheduleApply();
            }
        }

        // Presets Grid
        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: presetsCol.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: presetsCol

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Equalizer Presets")
                        font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                    }

                    StyledRect {
                        implicitWidth: resetEqTxt.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: 28
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3secondaryContainer

                        StateLayer {
                            radius: parent.radius
                            onClicked: EqualizerService.resetFlat()
                        }

                        StyledText {
                            id: resetEqTxt

                            anchors.centerIn: parent
                            text: Tr.tr("Reset Flat (0 dB)")
                            color: Colours.palette.m3onSecondaryContainer
                            font: Tokens.font.label.small
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: EqualizerService.presets

                        delegate: StyledRect {
                            required property var modelData
                            readonly property bool active: EqualizerService.activePreset === modelData.id

                            implicitWidth: presetChipRow.implicitWidth + Tokens.padding.medium * 2
                            implicitHeight: 34
                            radius: Tokens.rounding.full
                            color: active ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                            StateLayer {
                                radius: parent.radius
                                onClicked: EqualizerService.selectPreset(modelData.id)
                            }

                            RowLayout {
                                id: presetChipRow

                                anchors.centerIn: parent
                                spacing: 6

                                MaterialIcon {
                                    text: modelData.icon
                                    color: active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                    fontStyle: Tokens.font.icon.small
                                }

                                StyledText {
                                    text: modelData.name
                                    color: active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                    font: Tokens.font.label.small
                                }
                            }
                        }
                    }
                }
            }
        }

        // Bass Boost & Treble Enhancer Sliders
        SliderRow {
            icon: "speaker"
            label: Tr.tr("Bass Boost")
            valueLabel: `${value >= 0 ? "+" : ""}${value.toFixed(1)} dB`
            from: -6.0
            to: 12.0
            value: EqualizerService.bassBoost
            onMoved: v => {
                EqualizerService.bassBoost = Math.round(v * 2) / 2;
                if (!EqualizerService.enabled)
                    EqualizerService.enabled = true;
                EqualizerService.scheduleApply();
            }
        }

        SliderRow {
            icon: "graphic_eq"
            label: Tr.tr("Treble Clarity")
            valueLabel: `${value >= 0 ? "+" : ""}${value.toFixed(1)} dB`
            from: -6.0
            to: 12.0
            value: EqualizerService.trebleBoost
            onMoved: v => {
                EqualizerService.trebleBoost = Math.round(v * 2) / 2;
                if (!EqualizerService.enabled)
                    EqualizerService.enabled = true;
                EqualizerService.scheduleApply();
            }
        }

        SliderRow {
            icon: "volume_up"
            label: Tr.tr("Preamp Gain")
            valueLabel: `${value >= 0 ? "+" : ""}${value.toFixed(1)} dB`
            from: -12.0
            to: 6.0
            value: EqualizerService.preamp
            onMoved: v => {
                EqualizerService.preamp = Math.round(v * 2) / 2;
                EqualizerService.scheduleApply();
            }
        }

        RowButton {
            last: !root.showAllEqBands
            icon: root.showAllEqBands ? "expand_less" : "expand_more"
            text: Tr.tr("10-Band Frequency Sliders (31 Hz – 16 kHz)")
            subtext: Tr.tr("Fine-tune individual frequency bands (-12 dB to +12 dB)")
            onClicked: root.showAllEqBands = !root.showAllEqBands
        }

        Repeater {
            model: root.showAllEqBands ? EqualizerService.bandInfo : []

            delegate: SliderRow {
                required property var modelData
                required property int index

                last: index === 9
                icon: "equalizer"
                label: `Band ${modelData.label}`
                valueLabel: {
                    const g = Number(EqualizerService.bands[index] ?? 0);
                    return `${g >= 0 ? "+" : ""}${g.toFixed(1)} dB`;
                }
                from: -12.0
                to: 12.0
                value: Number(EqualizerService.bands[index] ?? 0)
                onMoved: v => EqualizerService.setBand(index, v)
            }
        }

        // Input / Microphone Section
        SectionHeader {
            text: Tr.tr("Microphone Input & Noise Cancellation")
        }

        SliderRow {
            first: true
            icon: Icons.getMicVolumeIcon(Audio.sourceVolume, Audio.sourceMuted)
            label: Tr.trCtx("Input volume", "audio input")
            valueLabel: Strings.percentOne(value)
            value: Audio.sourceVolume
            enabled: !Audio.sourceMuted
            onMoved: v => Audio.setSourceVolume(v)
        }

        ToggleRow {
            text: Tr.trCtx("Mute microphone", "audio input muted")
            checked: Audio.sourceMuted
            onToggled: Audio.setStreamMuted(Audio.source, checked)
        }

        ToggleRow {
            text: Tr.tr("AI Microphone Noise Suppression (RNNoise)")
            subtext: Tr.tr("Filter background fan and keyboard noise during calls")
            checked: EqualizerService.micNoiseCancel
            onToggled: EqualizerService.toggleMicNoiseCancel(checked)
        }

        AudioDeviceList {
            last: true
            nodes: Audio.sources
            currentId: Audio.source?.id ?? -1
            iconName: "mic"
            placeholderIcon: "mic_off"
            placeholderText: Tr.trCtx("No input devices", "no audio inputs")
            onSelected: node => Audio.setAudioSource(node)
        }
    }
}
