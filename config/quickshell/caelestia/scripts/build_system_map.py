#!/usr/bin/env python3
"""
Generates a compact, static-prefix AGENTS.md in $HOME so `agy` CLI sessions
pre-load exact local system, hardware, Caelestia IPC, and GUI automation facts
automatically without wasting turns or breaking prompt KV-caching.
"""

import os
import shutil
import subprocess
from pathlib import Path


def run_cmd(cmd: list[str], timeout: int = 3) -> str:
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return res.stdout.strip() if res.returncode == 0 else ""
    except Exception:
        return ""


def detect_os() -> str:
    try:
        for line in Path("/etc/os-release").read_text(encoding="utf-8").splitlines():
            if line.startswith("PRETTY_NAME="):
                return line.split("=", 1)[1].strip().strip('"')
    except Exception:
        pass
    return "Arch Linux"


def detect_apps() -> dict[str, list[str]]:
    categories = {
        "browsers": ["firefox", "chromium", "google-chrome-stable", "brave", "vivaldi"],
        "terminals": ["foot", "kitty", "alacritty", "wezterm"],
        "editors": ["codium", "code", "kate", "nvim", "nano"],
        "office_data": ["libreoffice", "onlyoffice-desktopeditors", "mousepad", "xed", "python3"],
        "media_cli": ["playerctl", "wpctl", "pactl", "mpv", "vlc"],
        "desktop_tools": ["caelestia-desktop", "grim", "ydotool", "wl-copy", "tesseract", "hyprctl"],
    }
    found = {}
    for k, bins in categories.items():
        found[k] = [b for b in bins if shutil.which(b)]
    return found


def detect_modes() -> str:
    raw = run_cmd(["caelestia", "shell", "modes", "list"])
    if raw:
        return ", ".join(line.strip() for line in raw.splitlines() if line.strip())
    return "standard:Balanced, gaming:Gaming & Turbo, work:Work & Focus, coding:Developer, cinema:Cinema & Media, sleep:Night & Battery Saver"


def main():
    home = Path.home()
    out_path = home / "AGENTS.md"

    os_name = detect_os()
    apps = detect_apps()
    modes_str = detect_modes()
    monitors = run_cmd(["hyprctl", "monitors", "-j"])
    res_info = "1920x1080"
    if monitors:
        try:
            import json
            m0 = json.loads(monitors)[0]
            res_info = f"{m0.get('width', 1920)}x{m0.get('height', 1080)}@{round(m0.get('refreshRate', 60))}Hz"
        except Exception:
            pass

    content = f"""# Local System & Desktop Automation Map (Preloaded Context)

## 1. Host Environment
- **OS / WM:** {os_name} • Hyprland Wayland (Lua dispatcher wrapper `hl.dsp.*`) • Screen `{res_info}`
- **Shell:** Quickshell Caelestia Shell (`~/.config/quickshell/caelestia/`)
- **Config Paths:** `~/.config/caelestia/` (`extra.json`, `equalizer.json`, `optimizer.json`, `ai_automation.json`, `shell.json`), `~/.config/hypr/`
- **GitHub Dotfiles Repo:** `~/Caelestia-NCH2024/` (keep `~/.config/quickshell/caelestia/` and `~/Caelestia-NCH2024/config/quickshell/caelestia/` synced when modifying UI)
- **Installed Apps & Tools:**
  - Browsers: {', '.join(apps['browsers']) or 'none'}
  - Editors / Office / Data: {', '.join(apps['editors'] + apps['office_data']) or 'python3'}
  - Media / Audio CLI: {', '.join(apps['media_cli']) or 'wpctl'}
  - GUI Automation: {', '.join(apps['desktop_tools'])}

## 2. Instant System Control Cheatsheet (Zero Exploration Needed)
- **System Modes:** `{modes_str}`
  - Switch mode immediately (no file hunting needed): `caelestia shell modes activate <id>` (e.g. `cinema`, `gaming`, `work`, `coding`, `standard`, `sleep`)
  - Cycle / Gaming toggle: `caelestia shell modes cycle` | `caelestia shell modes toggleGaming`
  - Verify current mode: `grep activeModeId ~/.config/caelestia/extra.json` & `powerprofilesctl get`
- **Nexus Settings Pages:** `caelestia shell nexus openPage <0..15>` (`0`: Modes, `1`: Device Care, `5`: Equalizer, `7`: Updates, `13`: Shortcuts, `14`: AI Automation)
- **Media / Audio / Display / Lock:** `playerctl status`, `playerctl metadata --format '{{{{playerName}}}}: {{{{title}}}} [{{{{status}}}}]'`, `wpctl set-volume @DEFAULT_AUDIO_SINK@ 80%`, `brightnessctl set 100%`, `caelestia shell lock lock`
- **Telemetry / CPU:** `caelestia-telemetry` (safe thermal/fan/GPU readout), `scxctl get`

## 3. Real-Time Multi-Cursor Computer-Use Protocol (`caelestia-desktop`)
- Every `caelestia-desktop` command supports `--agent <Tag>` (e.g., `--agent Browser`, `--agent Control`, `--agent Editor`) to render distinct color-coded live 120Hz pointers & click ripples on screen simultaneously (physical `ydotool` pointer access is thread-safe via `flock`).
- **Fast Text Clicker (Zero Vision Wait):**
  - `caelestia-desktop find "<text>" [--window firefox|quickshell]` -> sub-second `tesseract` pixel `(x, y)` coordinates of visible UI text/buttons!
  - `caelestia-desktop click-text "<text>" [--window <app>] [--agent <Tag>]` -> finds button text on screen, glides `<Tag>` cursor smoothly to it, and clicks with ripple in ONE command!
- **Standard GUI Actions:**
  - Window list / focus / launch: `caelestia-desktop windows`, `caelestia-desktop launch firefox "https://www.youtube.com" --agent Browser`, `caelestia-desktop focus firefox --agent Browser`
  - Grid screenshot + 1px click (when element has no text label, like thumbnails/icons): `caelestia-desktop screen --grid --out /tmp/ai_screen.png --agent Browser` -> `view_file` -> `caelestia-desktop click <x> <y> --agent Browser`
  - UTF-8 / Vietnamese input: `caelestia-desktop type "<text>" --enter --agent Browser` | Keys: `caelestia-desktop key ctrl+l --agent Browser` | Scroll: `caelestia-desktop scroll -5 --x <x> --y <y> --agent Browser`
- **Multi-Surface Parallel Demo:** When operating two distinct apps/panels (e.g. Firefox + Nexus/Quick Settings/Editor), assign `--agent Browser` for browser clicks and `--agent Control` for system panels (`caelestia shell nexus openPage 0` -> `click-text "Cinema" --window quickshell --agent Control`).

## 4. Coding & Verification Standard
- Never claim checks pass without running them (`qmllint`, `python3 -m py_compile`, `bash -n`).
- For UI/shell edits: keep existing comments/tokens (`Tokens`, `Colours`, `StyledRect`), sync `~/.config/quickshell/caelestia/` with `~/Caelestia-NCH2024/config/quickshell/caelestia/` if editing repo, and verify cleanly.
"""
    out_path.write_text(content, encoding="utf-8")
    print(f"Wrote {out_path} ({len(content)} bytes)")


if __name__ == "__main__":
    main()
