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
        "office_gui": ["lowriter", "libreoffice", "onlyoffice-desktopeditors", "wps"],
        "office_data": ["pandoc", "python3"],
        "media_cli": ["playerctl", "wpctl", "pactl", "mpv", "vlc"],
        "desktop_tools": ["caelestia-desktop", "grim", "ydotool", "wl-copy", "tesseract", "hyprctl"],
    }
    found = {}
    for k, bins in categories.items():
        found[k] = [b for b in bins if shutil.which(b)]
    if shutil.which("flatpak"):
        fp = subprocess.run(["flatpak", "info", "org.libreoffice.LibreOffice"], capture_output=True)
        if fp.returncode == 0:
            found["office_gui"].append("org.libreoffice.LibreOffice (Flatpak)")
    if (Path.home() / ".local/bin/linoffice/linoffice.sh").exists():
        found["office_gui"].append("LinOffice MS Word (~/.local/bin/linoffice/linoffice.sh)")
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
  - Editors / Office CLI: {', '.join(apps['editors'] + apps['office_data']) or 'python3'}
  - Office GUI Apps (Word/Writer): {', '.join(apps['office_gui']) or 'NONE installed yet (compatible fallback: kate/code + save .docx via office-paste --docx)'}
  - Media / Audio CLI: {', '.join(apps['media_cli']) or 'wpctl'}
  - GUI Automation: {', '.join(apps['desktop_tools'])}

## 2. Instant System Control Cheatsheet (Zero Exploration Needed)
- **System Modes:** `{modes_str}`
  - Switch mode immediately (no file hunting needed): `caelestia shell modes activate <id>` (e.g. `cinema`, `gaming`, `work`, `coding`, `standard`, `sleep`)
  - Cycle / Gaming toggle: `caelestia shell modes cycle` | `caelestia shell modes toggleGaming`
  - Verify current mode: `grep activeModeId ~/.config/caelestia/extra.json` & `powerprofilesctl get`
- **Nexus Settings Pages:** `caelestia shell nexus openPage <0..15>` (`0`: AI Automation, `1`: Modes, `2`: Device Care, `6`: Equalizer, `8`: Updates, `14`: Shortcuts)
- **Night Light & Display:** `caelestia shell modes setNightLight <true|false> <temp>` (instant `<0.1s` IPC, e.g. `caelestia shell modes setNightLight true 3500`), `brightnessctl set 100%`
- **Media / Audio / Lock:** `pactl list sink-inputs` (Firefox YouTube playback -> check `Corked: no`), `playerctl status` (native players), `wpctl set-volume @DEFAULT_AUDIO_SINK@ 80%`, `caelestia shell lock lock`
- **Voice Assistant ("Mi Mi / Hey Mi Mi / Hello Mi Mi"):** `caelestia-voice` (`train`, `daemon`, `listen-once`, `speak`, `status`, `clear-profile`)
- **Telemetry / CPU:** `caelestia-telemetry` (safe thermal/fan/GPU readout), `scxctl get`

## 3. Real-Time Multi-Cursor Computer-Use Protocol (`caelestia-desktop`)
- **Core Operating Principle:**
  - **User-Facing Apps (Web browsing/articles, Copy/Paste, LibreOffice/Word/Editors, YouTube/Media): OPERATE VISUALLY LIKE A HUMAN** with live cursors (`--agent Browser`, `--agent Editor`). Do NOT silently bypass visible browsing/copying with headless API scraping unless the GUI step is blocked/CAPTCHA-gated!
  - **System Controls (Modes, Night Light, Brightness, Volume, Audio Verify, Lock Screen): USE FAST CLI/IPC** (`caelestia shell modes activate`, `caelestia shell modes setNightLight`, `brightnessctl`, `wpctl`, `pactl`) for instant `<0.2s` execution.
- **Human-Like App Helpers (Visual, 1-Command Each):**
  - Search Web -> Click Article -> Scroll -> `Ctrl+A`/`Ctrl+C` (+ optional hero image): `caelestia-desktop web-copy "<query>" [--engine ddg|google] [--save-image /tmp/ai_article_img.jpg] --agent Browser`
  - Open Highest-Priority Compatible Office/Editor (`lowriter`/`libreoffice` > `onlyoffice` > `wps` > `abiword` > `kate`) -> `Ctrl+V` Paste -> Save `.docx` (supports Markdown tables + `--image`): `caelestia-desktop office-paste --docx ~/Documents/<file>.docx --title "<Title>" [--image /tmp/ai_article_img.jpg] --agent Editor`
  - YouTube Search + Play + Audio Check (`--min-y 185` skips search bar): `caelestia-desktop yt-play "<song/video query>" --agent Browser`
  - Headless `.docx` Generator (fallback only): `caelestia-desktop write-docx ~/Documents/<file>.docx --title "<Title>" --file /tmp/body.txt [--image /tmp/ai_article_img.jpg]`
- **Fast Text Clicker (`~0.8s`, Zero Vision Wait):**
  - `caelestia-desktop click-text "<text>" [--window firefox|quickshell|libreoffice] [--min-y 185] [--wait 5] [--agent <Tag>]` -> accent-insensitive OCR + smooth glide + click in ONE command!
  - `caelestia-desktop find "<text>" [--window <app>] [--min-y 185] [--wait 3]` -> returns exact pixel `(x, y)` coordinates.
- **Fallback GUI Actions (when element has no text label, like thumbnails/icons):**
  - Fast grid screenshot + 1px click: `caelestia-desktop screen --grid --fast --out /tmp/ai_screen.jpg --agent Browser` -> `view_file` -> `caelestia-desktop click <x> <y> --agent Browser`
  - Window / Type / Keys / Scroll: `caelestia-desktop windows`, `launch`, `focus`, `type "<text>" --enter`, `key ctrl+l`, `scroll -5 --x <x> --y <y>`.
- **Multi-Surface Parallel & Safety:** NEVER run `caelestia shell lock lock` inside an LLM worker/single step — lock barriers run strictly after verified completion.

## 4. Coding & Verification Standard
- Never claim checks pass without running them (`qmllint`, `python3 -m py_compile`, `bash -n`).
- For UI/shell edits: keep existing comments/tokens (`Tokens`, `Colours`, `StyledRect`), sync `~/.config/quickshell/caelestia/` with `~/Caelestia-NCH2024/config/quickshell/caelestia/` if editing repo, and verify cleanly.
"""
    try:
        import importlib.util
        km_path = Path(__file__).resolve().parent / "knowledge_mgr.py"
        if km_path.exists():
            spec = importlib.util.spec_from_file_location("knowledge_mgr", km_path)
            if spec and spec.loader:
                km = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(km)
                kb_section = km.format_markdown_section()
                if kb_section:
                    content += "\n" + kb_section + "\n"
    except Exception:
        pass
    out_path.write_text(content, encoding="utf-8")
    print(f"Wrote {out_path} ({len(content)} bytes)")


if __name__ == "__main__":
    main()
