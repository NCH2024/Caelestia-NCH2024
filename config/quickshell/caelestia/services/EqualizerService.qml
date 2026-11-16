pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Singleton {
    id: root

    property bool enabled: false
    property string activePreset: "flat"
    property real preamp: 0.0
    property real bassBoost: 0.0
    property real trebleBoost: 0.0
    property bool volumeOverdrive: false
    property real balance: 0.0 // -1.0 (Left) to +1.0 (Right)
    property bool micNoiseCancel: false
    property list<real> bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

    readonly property string activePresetName: {
        const found = presets.find(p => p.id === root.activePreset);
        return found ? found.name : "Custom";
    }

    readonly property list<var> bandInfo: [
        { freq: 31.0, label: "31 Hz", type: "bq_lowshelf" },
        { freq: 62.0, label: "62 Hz", type: "bq_peaking" },
        { freq: 125.0, label: "125 Hz", type: "bq_peaking" },
        { freq: 250.0, label: "250 Hz", type: "bq_peaking" },
        { freq: 500.0, label: "500 Hz", type: "bq_peaking" },
        { freq: 1000.0, label: "1 kHz", type: "bq_peaking" },
        { freq: 2000.0, label: "2 kHz", type: "bq_peaking" },
        { freq: 4000.0, label: "4 kHz", type: "bq_peaking" },
        { freq: 8000.0, label: "8 kHz", type: "bq_peaking" },
        { freq: 16000.0, label: "16 kHz", type: "bq_highshelf" }
    ]

    readonly property list<var> presets: [
        { id: "flat", name: "Flat", icon: "equalizer", values: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
        { id: "bass_boost", name: "Bass Boost", icon: "speaker", values: [7, 6, 5, 3, 1, 0, 0, 1, 1, 2] },
        { id: "v_shape", name: "Dynamic V-Shape", icon: "bolt", values: [5, 4, 2, 0, -2, -1, 1, 3, 5, 6] },
        { id: "vocal", name: "Vocal & Podcast", icon: "record_voice_over", values: [-2, -1, 0, 2, 4, 5, 4, 2, 0, -1] },
        { id: "gaming", name: "Gaming", icon: "sports_esports", values: [-3, -2, 0, 2, 3, 5, 6, 7, 5, 3] },
        { id: "cinema", name: "Cinema Surround", icon: "movie", values: [6, 5, 3, 1, 0, 1, 2, 4, 5, 4] },
        { id: "rock", name: "Rock", icon: "music_note", values: [5, 4, 3, -1, -2, 0, 3, 4, 5, 5] },
        { id: "pop", name: "Pop", icon: "album", values: [-1, 1, 3, 4, 3, 0, -1, 1, 2, 3] },
        { id: "electronic", name: "Electronic", icon: "graphic_eq", values: [6, 5, 2, 0, -2, 1, 0, 2, 5, 6] },
        { id: "custom", name: "Custom", icon: "tune", values: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] }
    ]

    function selectPreset(presetId: string): void {
        const found = presets.find(p => p.id === presetId);
        if (!found)
            return;
        root.activePreset = presetId;
        if (presetId !== "custom") {
            root.bands = found.values.slice();
        }
        if (!root.enabled && presetId !== "flat") {
            root.enabled = true;
        }
        scheduleApply();
    }

    function setBand(idx: int, val: real): void {
        if (idx < 0 || idx >= 10)
            return;
        const copy = root.bands.slice();
        copy[idx] = Math.round(val * 2) / 2;
        root.bands = copy;
        root.activePreset = "custom";
        if (!root.enabled)
            root.enabled = true;
        scheduleApply();
    }

    function resetFlat(): void {
        root.preamp = 0.0;
        root.bassBoost = 0.0;
        root.trebleBoost = 0.0;
        selectPreset("flat");
    }

    function setChannelBalance(bal: real): void {
        root.balance = Math.max(-1.0, Math.min(1.0, bal));
        const leftPct = Math.round((root.balance <= 0 ? 1.0 : (1.0 - root.balance)) * 100);
        const rightPct = Math.round((root.balance >= 0 ? 1.0 : (1.0 + root.balance)) * 100);
        Quickshell.execDetached(["sh", "-c", `pactl set-sink-volume @DEFAULT_SINK@ ${leftPct}% ${rightPct}%`]);
    }

    function setOverdriveVolume(pct: int): void {
        const frac = (Math.max(0, Math.min(150, pct)) / 100.0).toFixed(2);
        Quickshell.execDetached(["wpctl", "set-volume", "-l", "1.5", "@DEFAULT_AUDIO_SINK@", frac]);
    }

    function toggleMicNoiseCancel(on: bool): void {
        root.micNoiseCancel = on;
        if (on) {
            Quickshell.execDetached(["sh", "-c", "systemctl --user stop caelestia-rnnoise.service 2>/dev/null || true; systemctl --user reset-failed caelestia-rnnoise.service 2>/dev/null || true; systemd-run --user --unit=caelestia-rnnoise --collect pipewire -c /usr/share/pipewire/filter-chain/source-rnnoise.conf >/dev/null 2>&1 || true"]);
        } else {
            Quickshell.execDetached(["sh", "-c", "systemctl --user stop caelestia-rnnoise.service 2>/dev/null || true"]);
        }
        saveState();
    }

    function scheduleApply(): void {
        applyTimer.restart();
        saveState();
    }

    function saveState(): void {
        const data = {
            enabled: root.enabled,
            activePreset: root.activePreset,
            preamp: root.preamp,
            bassBoost: root.bassBoost,
            trebleBoost: root.trebleBoost,
            volumeOverdrive: root.volumeOverdrive,
            micNoiseCancel: root.micNoiseCancel,
            bands: root.bands
        };
        stateFile.setText(JSON.stringify(data, null, 2));
    }

    function computeGain(i: int): real {
        let gain = Number(root.bands[i] ?? 0);
        if (i <= 1)
            gain += root.bassBoost;
        else if (i === 2)
            gain += root.bassBoost * 0.5;
        if (i >= 8)
            gain += root.trebleBoost;
        else if (i === 7)
            gain += root.trebleBoost * 0.5;
        if (i === 0)
            gain += root.preamp;
        return Math.max(-15.0, Math.min(15.0, gain));
    }

    function buildFilterChainConf(): string {
        let nodesStr = "";
        let linksStr = "";
        for (let i = 0; i < 10; i++) {
            const info = root.bandInfo[i];
            const gain = computeGain(i);

            nodesStr += `
                    {
                        type  = builtin
                        name  = eq_band_${i + 1}
                        label = ${info.type}
                        control = { "Freq" = ${info.freq.toFixed(1)} "Q" = 1.41 "Gain" = ${gain.toFixed(2)} }
                    }`;
            if (i < 9) {
                linksStr += `\n                    { output = "eq_band_${i + 1}:Out" input = "eq_band_${i + 2}:In" }`;
            }
        }

        return `context.properties = {
    log.level = 0
}
context.spa-libs = {
    audio.convert.* = audioconvert/libspa-audioconvert
    support.*       = support/libspa-support
}
context.modules = [
    { name = libpipewire-module-rt
        args = { nice.level = -11 }
        flags = [ ifexists nofail ]
    }
    { name = libpipewire-module-protocol-native }
    { name = libpipewire-module-client-node }
    { name = libpipewire-module-adapter }
    { name = libpipewire-module-filter-chain
        args = {
            node.description = "Caelestia Studio Equalizer"
            media.name       = "Caelestia Studio Equalizer"
            filter.graph = {
                nodes = [${nodesStr}
                ]
                links = [${linksStr}
                ]
            }
            audio.channels = 2
            audio.position = [ FL FR ]
            capture.props = {
                node.name   = "effect_input.caelestia_eq"
                media.class = Audio/Sink
            }
            playback.props = {
                node.name   = "effect_output.caelestia_eq"
                node.passive = true
                target.object = "@HW_SINK@"
            }
        }
    }
]
`;
    }

    Timer {
        id: applyTimer

        interval: 180
        onTriggered: {
            if (!root.enabled) {
                const stopCmd = `
                    HW_SINK=$(pactl list short sinks 2>/dev/null | awk '$2 != "effect_input.caelestia_eq" {print $2; exit}')
                    if [ -n "$HW_SINK" ]; then
                        pactl set-default-sink "$HW_SINK" 2>/dev/null || true
                        for si in $(pactl list short sink-inputs 2>/dev/null | cut -f1); do
                            pactl move-sink-input "$si" "$HW_SINK" 2>/dev/null || true
                        done
                    fi
                    systemctl --user stop caelestia-eq.service 2>/dev/null || true
                `;
                Quickshell.execDetached(["bash", "-c", stopCmd]);
                return;
            }

            let paramsList = [];
            for (let i = 0; i < 10; i++) {
                const gain = root.computeGain(i);
                paramsList.push(`"eq_band_${i + 1}:Gain" ${gain.toFixed(2)}`);
            }
            const paramStr = paramsList.join(" ");
            const rawConf = root.buildFilterChainConf();
            eqConfFile.setText(rawConf);

            const cmd = `
                sleep 0.05
                HW_SINK=$(pactl list short sinks 2>/dev/null | awk '$2 != "effect_input.caelestia_eq" {print $2; exit}')
                if [ -n "$HW_SINK" ] && [ -f "${Paths.config}/caelestia-eq.conf" ]; then
                    sed -i "s|@HW_SINK@|$HW_SINK|g" "${Paths.config}/caelestia-eq.conf"
                fi
                NODE_ID=$(python3 -c '
import json, subprocess
try:
    d = json.loads(subprocess.check_output(["pw-dump"], text=True))
    for o in d:
        if o.get("info", {}).get("props", {}).get("node.name") == "effect_input.caelestia_eq":
            print(o["id"])
            break
except Exception:
    pass
' 2>/dev/null)
                if [ -n "$NODE_ID" ] && systemctl --user is-active --quiet caelestia-eq.service; then
                    pw-cli s "$NODE_ID" Props '{ params = [ ${paramStr} ] }' >/dev/null 2>&1 || true
                else
                    systemctl --user stop caelestia-eq.service 2>/dev/null || true
                    systemctl --user reset-failed caelestia-eq.service 2>/dev/null || true
                    systemd-run --user --unit=caelestia-eq --collect pipewire -c "${Paths.config}/caelestia-eq.conf" >/dev/null 2>&1 || true
                    for _ in 1 2 3 4 5 6; do
                        sleep 0.2
                        if pactl list short sinks 2>/dev/null | grep -q 'effect_input.caelestia_eq'; then
                            break
                        fi
                    done
                fi
                if pactl list short sinks 2>/dev/null | grep -q 'effect_input.caelestia_eq'; then
                    pactl set-default-sink "effect_input.caelestia_eq" 2>/dev/null || true
                    for si in $(pactl list short sink-inputs 2>/dev/null | cut -f1); do
                        pactl move-sink-input "$si" "effect_input.caelestia_eq" 2>/dev/null || true
                    done
                fi
            `;
            Quickshell.execDetached(["bash", "-c", cmd]);
        }
    }

    FileView {
        id: eqConfFile

        printErrors: false
        path: `${Paths.config}/caelestia-eq.conf`
    }

    FileView {
        id: stateFile

        printErrors: false
        path: `${Paths.config}/equalizer.json`
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (data.activePreset)
                    root.activePreset = String(data.activePreset);
                if (data.preamp !== undefined)
                    root.preamp = Number(data.preamp) || 0;
                if (data.bassBoost !== undefined)
                    root.bassBoost = Number(data.bassBoost) || 0;
                if (data.trebleBoost !== undefined)
                    root.trebleBoost = Number(data.trebleBoost) || 0;
                if (data.volumeOverdrive !== undefined)
                    root.volumeOverdrive = Boolean(data.volumeOverdrive);
                if (data.micNoiseCancel !== undefined)
                    root.micNoiseCancel = Boolean(data.micNoiseCancel);
                if (Array.isArray(data.bands) && data.bands.length === 10)
                    root.bands = data.bands.map(v => Number(v) || 0);
                if (data.enabled) {
                    root.enabled = true;
                    applyTimer.restart();
                }
            } catch (e) {}
        }
    }
}
