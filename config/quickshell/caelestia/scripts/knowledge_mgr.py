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
]


def load_kb() -> dict:
    try:
        if KB_PATH.exists():
            data = json.loads(KB_PATH.read_text(encoding="utf-8"))
            if isinstance(data, dict) and "recipes" in data:
                return data
    except Exception:
        pass
    return {
        "recipes": list(SEED_RECIPES),
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

    low = (user_task + " " + (summary or "")).lower()
    if ok:
        if "youtube" in low and ("yt-play" in low or "corked: no" in low):
            upsert_recipe(data, "Verify YouTube playback in Firefox", SEED_RECIPES[0]["lesson"], "yt_audio_verify")
        if ("word" in low or ".docx" in low or "libreoffice" in low) and "documents/" in low:
            upsert_recipe(data, "LibreOffice Flatpak file access & Word styling", SEED_RECIPES[1]["lesson"], "flatpak_lo_paths")
        if "night light" in low and "setnightlight" in low:
            upsert_recipe(data, "Toggle Night Light without changing power mode", SEED_RECIPES[2]["lesson"], "nightlight_direct")

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
    for r in recipes[:14]:
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


if __name__ == "__main__":
    main()
