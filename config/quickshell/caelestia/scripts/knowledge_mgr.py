#!/usr/bin/env python3
"""
Caelestia Self-Learning Knowledge Base (`knowledge_mgr.py`)
Records verified operational patterns, timings, and pitfalls after every AI task,
keeps only top high-utility recipes (<= 20 entries), and injects them into ~/AGENTS.md.
"""

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

KB_PATH = Path.home() / ".local" / "share" / "caelestia" / "ai" / "knowledge.json"
REPO_SEED_PATH = Path.home() / ".config" / "caelestia" / "ai_knowledge_seed.json"
MAX_RECIPES = 20

SEED_RECIPES = [
    {
        "id": "yt_audio_verify",
        "topic": "Verify YouTube playback in Firefox",
        "lesson": "Use `caelestia-desktop yt-play` (skips header `--min-y 185` & checks `pactl list sink-inputs` `Corked: no`); never rely on `playerctl` for Firefox.",
        "success_count": 3,
        "last_used": 0,
    },
    {
        "id": "flatpak_lo_paths",
        "topic": "LibreOffice Flatpak file access & Word styling",
        "lesson": "Save `.docx` in `~/Documents/` (Flatpak cannot read `/tmp`); embed images/tables via `caelestia-desktop write-docx --image` or `office-paste --image`.",
        "success_count": 2,
        "last_used": 0,
    },
    {
        "id": "nightlight_direct",
        "topic": "Toggle Night Light without changing power mode",
        "lesson": "Use `caelestia shell modes setNightLight true 3500` directly (<0.1s) instead of switching into full `sleep` mode unless user asked for battery saver.",
        "success_count": 2,
        "last_used": 0,
    },
    {
        "id": "curated_depth_and_lang",
        "topic": "Rich Word curation & language accuracy",
        "lesson": "Avoid thin JS/SPA stub pages (<1200 chars); auto-enrich from hit #2, fetch keyword-verified artwork (>=360px), and translate Word docs to Vietnamese when prompt is Vietnamese even if chatLanguage=auto.",
        "success_count": 2,
        "last_used": 0,
    },
]


def load_kb() -> dict:
    try:
        if KB_PATH.exists():
            data = json.loads(KB_PATH.read_text(encoding="utf-8"))
            if isinstance(data, dict) and "recipes" in data:
                return data
    except Exception:
        pass
    seed = list(SEED_RECIPES)
    try:
        if REPO_SEED_PATH.exists():
            sd = json.loads(REPO_SEED_PATH.read_text(encoding="utf-8"))
            if isinstance(sd, dict) and isinstance(sd.get("recipes"), list) and sd["recipes"]:
                seed = [
                    {
                        "id": str(r.get("id") or ""),
                        "topic": str(r.get("topic") or ""),
                        "lesson": str(r.get("lesson") or ""),
                        "success_count": int(r.get("success_count", 2)),
                        "last_used": int(r.get("last_used", 0)),
                    }
                    for r in sd["recipes"] if r.get("topic") and r.get("lesson")
                ][:MAX_RECIPES] or seed
    except Exception:
        pass
    return {
        "recipes": seed,
        "stats": {"total_runs": 0, "success_runs": 0, "avg_sec": 0.0, "last_updated": 0},
    }


def save_kb(data: dict):
    KB_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = KB_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(tmp, KB_PATH)


def refresh_agents_md():
    script = Path.home() / ".config" / "quickshell" / "caelestia" / "scripts" / "build_system_map.py"
    if script.exists():
        subprocess.run(["python3", str(script)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def upsert_recipe(data: dict, topic: str, lesson: str, rid: str | None = None):
    topic = topic.strip()[:90]
    lesson = re.sub(r"\s+", " ", lesson.strip())[:190]
    if not topic or not lesson:
        return
    slug = rid or re.sub(r"[^a-z0-9]+", "_", topic.lower()).strip("_")[:48]
    now = int(time.time())
    recipes = data.setdefault("recipes", [])
    for rec in recipes:
        if rec.get("id") == slug or rec.get("topic", "").lower() == topic.lower():
            rec["lesson"] = lesson
            rec["success_count"] = int(rec.get("success_count", 1)) + 1
            rec["last_used"] = now
            return
    recipes.append({
        "id": slug,
        "topic": topic,
        "lesson": lesson,
        "success_count": 1,
        "last_used": now,
    })
    # Keep top MAX_RECIPES sorted by utility (success_count & recency)
    recipes.sort(key=lambda r: (int(r.get("success_count", 1)), int(r.get("last_used", 0))), reverse=True)
    data["recipes"] = recipes[:MAX_RECIPES]


def record_run(user_task: str, elapsed_sec: float, ok: bool, summary: str, trace_notes: list[str] | None = None, learned_items: list[dict] | None = None):
    data = load_kb()
    st = data.setdefault("stats", {"total_runs": 0, "success_runs": 0, "avg_sec": 0.0, "last_updated": 0})
    n = int(st.get("total_runs", 0))
    prev_avg = float(st.get("avg_sec", 0.0))
    st["total_runs"] = n + 1
    if ok:
        st["success_runs"] = int(st.get("success_runs", 0)) + 1
    st["avg_sec"] = round(((prev_avg * n) + max(0.0, float(elapsed_sec))) / (n + 1), 2)
    st["last_updated"] = int(time.time())

    low = (user_task + " " + (summary or "") + " " + " ".join(trace_notes or [])).lower()
    if ok:
        if "youtube" in low and ("yt-play" in low or "corked: no" in low):
            upsert_recipe(data, "Verify YouTube playback in Firefox", SEED_RECIPES[0]["lesson"], "yt_audio_verify")
        if ("word" in low or ".docx" in low or "libreoffice" in low) and "documents/" in low:
            upsert_recipe(data, "LibreOffice Flatpak file access & Word styling", SEED_RECIPES[1]["lesson"], "flatpak_lo_paths")
        if "night light" in low and "setnightlight" in low:
            upsert_recipe(data, "Toggle Night Light without changing power mode", SEED_RECIPES[2]["lesson"], "nightlight_direct")
        if re.search(r"\b(đóng|ngừng|dừng|tắt|close-app|stop-media)\b", low) and re.search(r"\b(ứng dụng|cửa sổ|video|youtube|firefox|kate|vlc|libreoffice|okular|gwenview|code)\b", low):
            upsert_recipe(
                data,
                "Clean app window close & media stop",
                "Use `caelestia-desktop stop-media --close-tab` and `caelestia-desktop close-app <target> [--force]` (kills exact GUI PID or `flatpak kill`, NEVER `pkill -f`); verify `hyprctl clients -j`.",
                "close_apps_stop_media",
            )
        if re.search(r"(fetch-images|--images|chèn.*ảnh|tải.*ảnh|kèm.*ảnh)", low):
            upsert_recipe(
                data,
                "Fast 1-call verified topic images & .docx",
                "Use `caelestia-desktop fetch-images \"<query>\" --count N --out /tmp/ai_img.jpg` (~2s) + `write-docx --images ...` instead of manual scraping loops.",
                "fast_ddg_fetch_images",
            )
        if re.search(r"\b(kate|vs code|code|dolphin|okular|gwenview|vlc|btop|kcalc|konsole|meld|thunar)\b", low):
            upsert_recipe(
                data,
                "Multi-app desktop workflow & verification",
                "Launch installed apps (`kate`, `code`, `dolphin`, `vlc`, `okular`, `gwenview`, `kcalc`, `btop`) via `caelestia-desktop launch` & confirm open/closed via `hyprctl clients -j`.",
                "multi_app_orchestration",
            )
        if re.search(r"(rồi dùng|dùng tên|dùng kết quả|rút ra|tính xem|so sánh.*với)", low):
            upsert_recipe(
                data,
                "Chained multi-hop search without SERP trap",
                "For dependent A->B->C queries or multi-app tasks, skip curated Round-1 `web-copy` and chain `search_web` + `write-docx --images` directly in `run_single_fast`.",
                "chained_search_no_serp",
            )
        if re.search(r"\b(telemetry|nhiệt độ|scx|cửa sổ đang mở)\b", low):
            upsert_recipe(
                data,
                "Batched local telemetry & state inspection",
                "Batch `caelestia-telemetry`, `scxctl get`, `hyprctl clients -j`, `wpctl`, and `brightnessctl` into a single `run_command` call (<0.2s) instead of separate turns.",
                "batch_telemetry_fast",
            )
        if re.search(r"\b(launch|ensure-workspace|workspace|kate|code|dolphin|vlc|okular|gwenview|kcalc|btop|libreoffice|firefox)\b", low):
            upsert_recipe(
                data,
                "Hyprland workspace free-space guard before app launch",
                "Keep the main terminal workspace at 1 window alone and max 2 tiled windows per workspace (`>=820x480`); always launch GUI apps via `caelestia-desktop launch <cmd>`.",
                "workspace_readability_guard",
            )
    else:
        if "privacy" in low or "msn" in low or "cookie" in low or "duckduckgo" in low or "serp" in low:
            upsert_recipe(
                data,
                "Bypass privacy-walled portals & SERP traps",
                "Reject MSN/privacy modals and DuckDuckGo SERP self-copies (`duckduckgo.com/?`); advance to real sites (`gsmarena`, `sammobile`, `9to5google`) or escalate to Round-2 `search_web`.",
                "avoid_privacy_walls",
            )
        if ("youtube" in low or "yt_fail" in low or "chưa xác nhận phát" in low) and ("corked" in low or "yt_fail" in low or "chưa xác nhận phát" in low):
            upsert_recipe(
                data,
                "YouTube search chip & Shorts skip rule",
                "Scan YouTube results with min_y>=245 & title length>=18 chars to skip Shorts/chips; retry hits[1] cleanly before Round-2 fallback.",
                "yt_skip_chips_shorts",
            )
        if "image" in low and ("missing" in low or "thiếu ảnh" in low):
            upsert_recipe(
                data,
                "Guaranteed multi-image & YouTube capture for Word",
                "Use `web-copy --image-count N` + keyword-filtered DDG `i.js` fallback and `yt-play --screenshot` + `write-docx --images` when multiple images are requested.",
                "multi_image_docx",
            )

    for item in (learned_items or []):
        if isinstance(item, dict) and item.get("topic") and item.get("lesson"):
            upsert_recipe(data, str(item["topic"]), str(item["lesson"]))

    save_kb(data)
    refresh_agents_md()


def format_markdown_section() -> str:
    data = load_kb()
    recipes = data.get("recipes") or []
    st = data.get("stats") or {}
    lines = [
        f"## 5. Self-Learned Machine Recipes ({len(recipes)} rules • {st.get('total_runs', 0)} runs, avg {st.get('avg_sec', 0)}s)"
    ]
    for r in recipes[:16]:
        lines.append(f"- **{r['topic']}**: {r['lesson']}")
    return "\n".join(lines)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "summary"
    if cmd == "summary":
        data = load_kb()
        st = data.get("stats", {})
        print(json.dumps({
            "count": len(data.get("recipes", [])),
            "total_runs": st.get("total_runs", 0),
            "success_runs": st.get("success_runs", 0),
            "avg_sec": st.get("avg_sec", 0.0),
            "recipes": data.get("recipes", []),
        }, ensure_ascii=False))
    elif cmd == "clear":
        data = {"recipes": list(SEED_RECIPES), "stats": {"total_runs": 0, "success_runs": 0, "avg_sec": 0.0, "last_updated": int(time.time())}}
        save_kb(data)
        refresh_agents_md()
        print(json.dumps({"ok": True, "count": len(SEED_RECIPES)}))
    elif cmd == "markdown":
        print(format_markdown_section())
    elif cmd == "export-seed":
        data = load_kb()
        out_p = Path(sys.argv[2]) if len(sys.argv) > 2 else (Path.home() / "Caelestia-NCH2024" / "config" / "caelestia" / "ai_knowledge_seed.json")
        portable = [
            {"id": r["id"], "topic": r["topic"], "lesson": r["lesson"]}
            for r in (data.get("recipes") or [])[:MAX_RECIPES]
        ]
        out_p.parent.mkdir(parents=True, exist_ok=True)
        out_p.write_text(json.dumps({"recipes": portable}, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(json.dumps({"ok": True, "exported": len(portable), "path": str(out_p)}))
    elif cmd == "reflect" and len(sys.argv) >= 6:
        task_txt, dur_s, ok_s, route_s, summary_s = sys.argv[2], float(sys.argv[3]), sys.argv[4] == "1", sys.argv[5], sys.argv[6] if len(sys.argv) > 6 else ""
        record_run(task_txt, dur_s, ok_s, summary_s, trace_notes=[f"route={route_s}"])


if __name__ == "__main__":
    main()
