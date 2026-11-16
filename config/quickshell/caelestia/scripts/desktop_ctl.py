#!/usr/bin/env python3
"""
Caelestia Desktop Control Utility (`caelestia-desktop`)
Multi-cursor, thread-safe Wayland/Hyprland GUI automation bridge for AI agents:
- Physical pointer/keyboard serialization (`flock`) so multiple parallel agents never collide
- Named multi-cursor visual HUD events (`--agent Browser`, `--agent Control`, etc.) at 120Hz
- Closed-loop 1px calibrated smooth cursor gliding (`ydotool` + `hyprctl cursorpos`)
- Sub-second UI text locator (`find` / `click-text`) via `tesseract` + window cropping
- Full UTF-8 / Vietnamese typing via clipboard paste (`wl-copy` + `Ctrl+V`)
"""

import argparse
from contextlib import contextmanager
import fcntl
import json
import os
import subprocess
import sys
import time
import unicodedata
from urllib.parse import quote_plus
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps

LOCK_PATH = "/tmp/caelestia_pointer.lock"

KEYCODES = {
    "esc": 1, "escape": 1,
    "1": 2, "2": 3, "3": 4, "4": 5, "5": 6, "6": 7, "7": 8, "8": 9, "9": 10, "0": 11,
    "minus": 12, "equal": 13, "backspace": 14, "tab": 15,
    "q": 16, "w": 17, "e": 18, "r": 19, "t": 20, "y": 21, "u": 22, "i": 23, "o": 24, "p": 25,
    "leftbrace": 26, "rightbrace": 27, "enter": 28, "return": 28,
    "ctrl": 29, "lctrl": 29,
    "a": 30, "s": 31, "d": 32, "f": 33, "g": 34, "h": 35, "j": 36, "k": 37, "l": 38,
    "semicolon": 39, "apostrophe": 40, "grave": 41,
    "shift": 42, "lshift": 42, "backslash": 43,
    "z": 44, "x": 45, "c": 46, "v": 47, "b": 48, "n": 49, "m": 50,
    "comma": 51, "dot": 52, "period": 52, "slash": 53,
    "rshift": 54, "alt": 56, "lalt": 56, "space": 57, "capslock": 58,
    "f1": 59, "f2": 60, "f3": 61, "f4": 62, "f5": 63, "f6": 64,
    "f7": 65, "f8": 66, "f9": 67, "f10": 68, "f11": 87, "f12": 88,
    "home": 102, "up": 103, "pageup": 104, "left": 105, "right": 106,
    "end": 107, "down": 108, "pagedown": 109, "insert": 110, "delete": 111,
    "super": 125, "meta": 125, "win": 125,
}

BUTTON_CODES = {
    "left": "0xC0",
    "right": "0xC1",
    "middle": "0xC2",
}


def run(cmd: list[str], input_text: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, input=input_text, capture_output=True, text=True)


def wl_copy_safe(text: str):
    """Set Wayland clipboard without letting background wl-copy daemon inherit stdout/stderr pipes."""
    subprocess.run(
        ["wl-copy", "--", text],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        check=False,
    )


@contextmanager
def pointer_lock():
    """Serialize physical ydotool mouse/keyboard calls across parallel AI agents."""
    f = open(LOCK_PATH, "w")
    try:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(f, fcntl.LOCK_UN)
        f.close()


def ensure_ydotool():
    chk = run(["systemctl", "--user", "is-active", "ydotool"])
    if chk.returncode != 0:
        run(["systemctl", "--user", "enable", "--now", "ydotool"])
        time.sleep(0.2)


def get_monitor_info() -> tuple[int, int, float]:
    res = run(["hyprctl", "monitors", "-j"])
    try:
        mons = json.loads(res.stdout)
        for m in mons:
            if m.get("focused"):
                return int(m["width"]), int(m["height"]), float(m.get("scale", 1.0))
        if mons:
            return int(mons[0]["width"]), int(mons[0]["height"]), float(mons[0].get("scale", 1.0))
    except Exception:
        pass
    return 1920, 1080, 1.0


def get_cursor_pos() -> tuple[int, int]:
    res = run(["hyprctl", "cursorpos"])
    try:
        parts = res.stdout.strip().split(",")
        return int(parts[0].strip()), int(parts[1].strip())
    except Exception:
        return -1, -1


def notify_hud(x: int, y: int, action: str, label: str = "", clicked: bool = False, agent: str = "Meow AI"):
    """Fire-and-forget 120Hz visual AI ghost cursor update (supports multiple named cursors)."""
    try:
        subprocess.Popen(
            [
                "qs", "-c", "caelestia", "ipc", "call", "ai", "cursorEvent",
                str(int(x)), str(int(y)), str(action), str(label), "1" if clicked else "0", str(agent or "Meow AI"),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception:
        pass


def calibrated_move(tx: int, ty: int, action_label: str = "Moving", agent: str = "Meow AI"):
    """Smooth human-like eased move + closed-loop pointer calibration within a few pixels."""
    ensure_ydotool()
    w, h, _ = get_monitor_info()
    tx = max(0, min(w - 1, int(tx)))
    ty = max(0, min(h - 1, int(ty)))

    sx, sy = get_cursor_pos()
    if sx < 0 or sy < 0:
        sx, sy = w // 2, h // 2

    notify_hud(tx, ty, "move", action_label, False, agent)

    dist = ((tx - sx) ** 2 + (ty - sy) ** 2) ** 0.5
    steps = max(5, min(16, int(dist / 80))) if dist > 20 else 1
    scale_x, scale_y = 0.5, 0.5
    for step in range(1, steps + 1):
        u = step / steps
        eased = 1.0 - (1.0 - u) ** 3
        ix = round(sx + (tx - sx) * eased)
        iy = round(sy + (ty - sy) * eased)
        run(["ydotool", "mousemove", "--absolute", "-x", str(round(ix * scale_x)), "-y", str(round(iy * scale_y))])
        if step < steps:
            time.sleep(0.012)

    time.sleep(0.04)
    ax, ay = get_cursor_pos()
    if ax < 0 or (abs(ax - tx) <= 4 and abs(ay - ty) <= 4):
        return ax, ay

    if ax > 20 and tx > 20:
        scale_x = scale_x * (tx / ax)
    if ay > 20 and ty > 20:
        scale_y = scale_y * (ty / ay)
    run(["ydotool", "mousemove", "--absolute", "-x", str(round(tx * scale_x)), "-y", str(round(ty * scale_y))])
    time.sleep(0.04)
    return get_cursor_pos()


def press_combo(combo: str):
    ensure_ydotool()
    parts = [p.strip().lower() for p in combo.replace("-", "+").split("+") if p.strip()]
    codes = []
    for p in parts:
        if p not in KEYCODES:
            raise ValueError(f"Unknown key '{p}'. Supported: {sorted(KEYCODES.keys())}")
        codes.append(KEYCODES[p])
    seq = [f"{c}:1" for c in codes] + [f"{c}:0" for c in reversed(codes)]
    run(["ydotool", "key", *seq])


def strip_accents(text: str) -> str:
    """Normalize Vietnamese/Unicode text to lowercase ASCII for fast accent-insensitive matching."""
    text = text.replace("đ", "d").replace("Đ", "D")
    nfkd = unicodedata.normalize("NFD", text)
    return "".join(ch for ch in nfkd if unicodedata.category(ch) != "Mn").lower()


def draw_grid(img_path: str, fast: bool = False):
    im = Image.open(img_path).convert("RGBA")
    overlay = Image.new("RGBA", im.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    w, h = im.size
    font = ImageFont.load_default()

    for x in range(0, w, 100):
        is_major = (x % 200 == 0)
        color = (0, 255, 255, 130) if is_major else (0, 255, 255, 50)
        draw.line([(x, 0), (x, h)], fill=color, width=1)
        if is_major and x > 0:
            draw.rectangle([x + 2, 2, x + 36, 16], fill=(0, 0, 0, 175))
            draw.text((x + 4, 3), str(x), fill=(0, 255, 255, 255), font=font)

    for y in range(0, h, 100):
        is_major = (y % 200 == 0)
        color = (255, 210, 0, 130) if is_major else (255, 210, 0, 50)
        draw.line([(0, y), (w, y)], fill=color, width=1)
        if is_major and y > 0:
            draw.rectangle([2, y + 2, 36, y + 16], fill=(0, 0, 0, 175))
            draw.text((4, y + 3), str(y), fill=(255, 210, 0, 255), font=font)

    out = Image.alpha_composite(im, overlay).convert("RGB")
    ext = Path(img_path).suffix.lower()
    if fast or ext in (".jpg", ".jpeg"):
        if w > 1280:
            nh = round(h * (1280 / w))
            out = out.resize((1280, nh), Image.Resampling.BILINEAR)
        if ext in (".jpg", ".jpeg"):
            out.save(img_path, "JPEG", quality=82, optimize=True)
            return
    out.save(img_path)


def find_client(target: str) -> dict | None:
    res = run(["hyprctl", "clients", "-j"])
    try:
        clients = json.loads(res.stdout)
    except Exception:
        return None
    low = target.lower()
    for c in clients:
        if c.get("address", "").lower() == low:
            return c
    for c in clients:
        if low in c.get("class", "").lower() or low in c.get("title", "").lower():
            return c
    return None


def hypr_focus(target: str) -> bool:
    match = find_client(target)
    if not match:
        return False
    addr = match["address"]
    r = run(["hyprctl", "dispatch", f'hl.dsp.focus({{ window = "address:{addr}" }})'])
    if r.returncode != 0:
        r = run(["hyprctl", "dispatch", "focuswindow", f"address:{addr}"])
    return r.returncode == 0


def _ocr_scan_once(query: str, window_filter: str | None = None, lang: str = "auto", min_y: int = 0) -> list[dict]:
    """Capture screen/window, preprocess (0.65x grayscale BMP, auto-invert dark UI) -> sub-second TSV OCR."""
    ox, oy = 0, 0
    region_arg = None
    if window_filter:
        c = find_client(window_filter)
        if c and c.get("at") and c.get("size"):
            ox, oy = int(c["at"][0]), int(c["at"][1])
            w, h = int(c["size"][0]), int(c["size"][1])
            if w > 20 and h > 20:
                region_arg = f"{ox},{oy} {w}x{h}"

    pid = os.getpid()
    raw_png = f"/tmp/ai_find_{pid}.png"
    prep_bmp = f"/tmp/ai_find_{pid}.bmp"
    gcmd = ["grim"]
    if region_arg:
        gcmd.extend(["-g", region_arg])
    gcmd.append(raw_png)
    if run(gcmd).returncode != 0:
        return []

    scale = 0.65
    try:
        im = Image.open(raw_png).convert("L")
        # Invert dark themes to dark-text-on-light for dramatically faster, sharper OCR
        hist = im.histogram()
        total_px = sum(hist) or 1
        mean_lum = sum(i * c for i, c in enumerate(hist)) / total_px
        if mean_lum < 125:
            im = ImageOps.invert(im)
        if im.width >= 900:
            nw = max(320, round(im.width * scale))
            nh = max(200, round(im.height * scale))
            im = im.resize((nw, nh), Image.Resampling.BILINEAR)
        else:
            scale = 1.0
        im.save(prep_bmp)
        src_img = prep_bmp
    except Exception:
        scale = 1.0
        src_img = raw_png

    use_lang = "eng" if lang in ("auto", "", None) else lang
    tsv = run(["tesseract", src_img, "stdout", "-l", use_lang, "--psm", "11", "tsv"]).stdout
    for p in (raw_png, prep_bmp):
        try:
            if os.path.exists(p):
                os.remove(p)
        except Exception:
            pass

    inv_scale = 1.0 / scale
    words = []
    lines_map = {}
    for row in tsv.splitlines()[1:]:
        cols = row.split("\t")
        if len(cols) != 12:
            continue
        txt = cols[11].strip()
        try:
            conf = float(cols[10])
            left, top, width, height = int(cols[6]), int(cols[7]), int(cols[8]), int(cols[9])
        except Exception:
            continue
        if not txt or conf < 20 or width <= 0 or height <= 0:
            continue
        r_left = round(left * inv_scale)
        r_top = round(top * inv_scale)
        r_w = round(width * inv_scale)
        r_h = round(height * inv_scale)
        cx = ox + r_left + r_w // 2
        cy = oy + r_top + r_h // 2
        norm_txt = strip_accents(txt)
        item = {
            "text": txt,
            "norm": norm_txt,
            "x": cx,
            "y": cy,
            "left": ox + r_left,
            "right": ox + r_left + r_w,
            "top": oy + r_top,
            "bottom": oy + r_top + r_h,
        }
        words.append(item)
        line_key = (cols[1], cols[2], cols[3], cols[4])
        lines_map.setdefault(line_key, []).append(item)

    qnorm = strip_accents(query).strip()
    qtokens = [tok for tok in qnorm.split() if tok]
    hits = []
    for _, wlist in lines_map.items():
        wlist.sort(key=lambda d: d["left"])
        joined = " ".join(w["text"] for w in wlist)
        jnorm = strip_accents(joined)
        if qnorm and (qnorm in jnorm or (len(qtokens) >= 2 and all(tok in jnorm for tok in qtokens))):
            matched = [w for w in wlist if any(tok in w["norm"] for tok in qtokens)] or wlist
            avg_x = sum(w["x"] for w in matched) // len(matched)
            avg_y = sum(w["y"] for w in matched) // len(matched)
            hits.append({"text": joined, "x": avg_x, "y": avg_y, "score": 3 if qnorm in jnorm else 2})

    if not hits and qtokens:
        for w in words:
            if qnorm in w["norm"] or (len(qtokens) == 1 and qtokens[0] in w["norm"]):
                hits.append({"text": w["text"], "x": w["x"], "y": w["y"], "score": 1})

    hits.sort(key=lambda d: (-d["score"], d["y"], d["x"]))
    if min_y > 0:
        hits = [h for h in hits if h["y"] >= min_y]
    return hits


def ocr_find_matches(query: str, window_filter: str | None = None, lang: str = "auto", wait_sec: float = 0.0, min_y: int = 0) -> list[dict]:
    deadline = time.time() + max(0.0, float(wait_sec or 0.0))
    while True:
        hits = _ocr_scan_once(query, window_filter, lang, min_y=min_y)
        if hits or time.time() >= deadline:
            return hits
        time.sleep(0.35)


def cmd_screen(args):
    out = args.out or "/tmp/ai_screen.png"
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    if args.region:
        res = run(["grim", "-g", args.region, out])
    else:
        res = run(["grim", out])
    if res.returncode != 0:
        print(json.dumps({"ok": False, "error": res.stderr.strip()}))
        sys.exit(1)
    if args.grid:
        draw_grid(out, fast=args.fast)
    w, h, scale = get_monitor_info()
    cx, cy = get_cursor_pos()
    notify_hud(cx if cx >= 0 else w // 2, cy if cy >= 0 else h // 2, "scan", "Quan sát màn hình", False, args.agent)
    print(json.dumps({
        "ok": True,
        "path": out,
        "screen": {"width": w, "height": h, "scale": scale},
        "cursor": {"x": cx, "y": cy},
        "grid": bool(args.grid),
    }))


def cmd_windows(args):
    res = run(["hyprctl", "clients", "-j"])
    try:
        clients = json.loads(res.stdout)
    except Exception:
        clients = []
    out = [
        {
            "address": c.get("address"),
            "title": c.get("title"),
            "class": c.get("class"),
            "workspace": c.get("workspace", {}).get("id"),
            "at": c.get("at"),
            "size": c.get("size"),
            "focused": c.get("focusHistoryID") == 0,
            "floating": c.get("floating"),
        }
        for c in clients
    ]
    print(json.dumps(out, ensure_ascii=False, indent=2))


def cmd_focus(args):
    with pointer_lock():
        ok = hypr_focus(args.target)
        if ok:
            res = run(["hyprctl", "activewindow", "-j"])
            try:
                aw = json.loads(res.stdout)
                ax = int(aw["at"][0] + aw["size"][0] / 2)
                ay = int(aw["at"][1] + aw["size"][1] / 2)
                notify_hud(ax, ay, "focus", f"Focus {args.target}", False, args.agent)
            except Exception:
                pass
    print(json.dumps({"ok": ok, "target": args.target}))
    if not ok:
        sys.exit(1)


def cmd_launch(args):
    cmd = args.cmd
    w, h, _ = get_monitor_info()
    app_name = Path(cmd[0]).name if cmd else "app"
    notify_hud(w // 2, h // 2, "launch", f"Mở {app_name}", False, args.agent)
    subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    print(json.dumps({"ok": True, "launched": cmd}))


def cmd_move(args):
    with pointer_lock():
        ax, ay = calibrated_move(args.x, args.y, f"Di chuyển ({args.x}, {args.y})", args.agent)
    print(json.dumps({"ok": True, "target": [args.x, args.y], "actual": [ax, ay]}))


def cmd_click(args):
    lbl = "Double Click" if args.double else ("Right Click" if args.button == "right" else "Click")
    with pointer_lock():
        ax, ay = calibrated_move(args.x, args.y, lbl, args.agent)
        notify_hud(ax if ax >= 0 else args.x, ay if ay >= 0 else args.y, "click", lbl, True, args.agent)
        code = BUTTON_CODES[args.button]
        if args.double:
            run(["ydotool", "click", "--repeat", "2", "--next-delay", "60", code])
        else:
            run(["ydotool", "click", code])
    print(json.dumps({"ok": True, "button": args.button, "double": args.double, "at": [ax, ay]}))


def cmd_scroll(args):
    with pointer_lock():
        if args.x is not None and args.y is not None:
            calibrated_move(args.x, args.y, "Cuộn trang", args.agent)
        else:
            cx, cy = get_cursor_pos()
            notify_hud(cx, cy, "scroll", "Cuộn trang", False, args.agent)
        run(["ydotool", "mousemove", "-w", "-x", "0", "-y", str(args.delta)])
    print(json.dumps({"ok": True, "delta": args.delta}))


def cmd_type(args):
    with pointer_lock():
        ensure_ydotool()
        cx, cy = get_cursor_pos()
        preview = args.text[:24] + ("..." if len(args.text) > 24 else "")
        notify_hud(cx, cy, "type", f"Nhập: {preview}", False, args.agent)
        text = args.text
        is_ascii = all(32 <= ord(ch) <= 126 for ch in text)
        if is_ascii and len(text) <= 80 and not args.paste:
            run(["ydotool", "type", "--key-delay", "8", text])
            method = "ydotool"
        else:
            wl_copy_safe(text)
            time.sleep(0.08)
            press_combo("ctrl+v")
            method = "clipboard_paste"
        if args.enter:
            time.sleep(0.05)
            press_combo("enter")
    print(json.dumps({"ok": True, "method": method, "length": len(text)}))


def cmd_key(args):
    with pointer_lock():
        cx, cy = get_cursor_pos()
        notify_hud(cx, cy, "key", f"Phím: {args.combo}", False, args.agent)
        press_combo(args.combo)
    print(json.dumps({"ok": True, "combo": args.combo}))


def cmd_find(args):
    if args.window:
        with pointer_lock():
            hypr_focus(args.window)
            time.sleep(0.12)
            hits = ocr_find_matches(args.query, args.window, args.lang, args.wait, min_y=args.min_y)
    else:
        hits = ocr_find_matches(args.query, args.window, args.lang, args.wait, min_y=args.min_y)
    print(json.dumps({"found": len(hits) > 0, "count": len(hits), "matches": hits[:10]}, ensure_ascii=False))
    if not hits:
        sys.exit(1)


def cmd_click_text(args):
    with pointer_lock():
        if args.window:
            hypr_focus(args.window)
            time.sleep(0.12)
        hits = ocr_find_matches(args.query, args.window, args.lang, args.wait, min_y=args.min_y)
        if not hits:
            print(json.dumps({"ok": False, "error": f"Text '{args.query}' not found on screen"}))
            sys.exit(1)
        idx = min(max(0, args.index), len(hits) - 1)
        target = hits[idx]
        lbl = f"Click '{args.query[:20]}'"
        ax, ay = calibrated_move(target["x"], target["y"], lbl, args.agent)
        notify_hud(ax if ax >= 0 else target["x"], ay if ay >= 0 else target["y"], "click", lbl, True, args.agent)
        run(["ydotool", "click", BUTTON_CODES[args.button]])
    print(json.dumps({"ok": True, "matched": target["text"], "at": [ax, ay]}))


def _firefox_title() -> str:
    c = find_client("firefox")
    return str(c.get("title", "")) if c else ""


def _firefox_audio_corked() -> tuple[bool, bool]:
    out = run(["pactl", "list", "sink-inputs"]).stdout
    has_ff = False
    playing = False
    for blk in out.split("Sink Input #"):
        lb = blk.lower()
        if "firefox" in lb:
            has_ff = True
            if "corked: no" in lb:
                playing = True
                break
    return has_ff, playing


def cmd_yt_play(args):
    """Visually open YouTube search, OCR-click result below header (min_y=185), wait safely for autoplay, and verify audio."""
    query = args.query.strip()
    url = f"https://www.youtube.com/results?search_query={quote_plus(query)}"
    w, h, _ = get_monitor_info()
    notify_hud(w // 2, h // 2, "launch", f"YouTube: {query[:20]}", False, args.agent)
    subprocess.Popen(["firefox", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    # Wait cleanly until Firefox shows YouTube search tab before locking search_title
    t_wait = time.time() + 2.8
    while time.time() < t_wait:
        cur = _firefox_title().lower()
        if "youtube" in cur:
            break
        time.sleep(0.25)
    time.sleep(0.5)

    words = query.split()
    candidates = []
    if len(words) >= 3:
        candidates.append(" ".join(words[:4]))
    candidates.append(query)
    if len(words) >= 2:
        candidates.append(" ".join(words[-2:]))

    clicked_match = None
    search_title = ""
    with pointer_lock():
        hypr_focus("firefox")
        time.sleep(0.18)
        search_title = _firefox_title()
        hits = []
        deadline = time.time() + 6.0
        while time.time() < deadline and not hits:
            for cand in candidates:
                hits = _ocr_scan_once(cand, "firefox", "auto", min_y=185)
                if hits:
                    break
            if not hits:
                time.sleep(0.4)
        if not hits:
            print(json.dumps({"ok": False, "error": f"No YouTube result text matched '{query}' below header"}))
            sys.exit(1)
        target = hits[0]
        clicked_match = target["text"]
        lbl = f"Play '{query[:18]}'"
        ax, ay = calibrated_move(target["x"], target["y"], lbl, args.agent)
        notify_hud(ax if ax >= 0 else target["x"], ay if ay >= 0 else target["y"], "click", lbl, True, args.agent)
        run(["ydotool", "click", BUTTON_CODES["left"]])

    # Wait up to 4.5s for YouTube autoplay to buffer cleanly BEFORE touching 'k' (no accidental pause!)
    cur_title = search_title
    is_playing = False
    deadline = time.time() + 4.5
    while time.time() < deadline:
        cur_title = _firefox_title()
        _, is_playing = _firefox_audio_corked()
        if is_playing:
            time.sleep(0.5)
            _, is_playing = _firefox_audio_corked()
            if is_playing:
                break
        time.sleep(0.4)

    watched = bool(cur_title and cur_title != search_title and "youtube" in cur_title.lower())
    if not is_playing and watched:
        with pointer_lock():
            hypr_focus("firefox")
            time.sleep(0.08)
            notify_hud(ax, ay, "key", "Play (k)", False, args.agent)
            press_combo("k")
        deadline2 = time.time() + 2.5
        while time.time() < deadline2:
            _, is_playing = _firefox_audio_corked()
            if is_playing:
                break
            time.sleep(0.4)

    out_obj = {
        "ok": bool(is_playing),
        "playing": bool(is_playing),
        "matched": clicked_match,
        "title": _firefox_title(),
    }
    print(json.dumps(out_obj, ensure_ascii=False))
    if not is_playing:
        sys.exit(1)


def detect_office_app() -> tuple[str | None, list[str] | None, bool]:
    """Return (binary_name, launch_cmd, is_word_processor) prioritized for OS-compatible Word/Office apps."""
    import shutil
    candidates = [
        ("lowriter", ["lowriter", "--nologo", "--norestore"], True),
        ("libreoffice", ["libreoffice", "--writer", "--nologo", "--norestore"], True),
        ("onlyoffice-desktopeditors", ["onlyoffice-desktopeditors"], True),
        ("wps", ["wps"], True),
        ("abiword", ["abiword"], True),
        ("kate", ["kate", "--new"], False),
        ("code", ["code", "--new-window"], False),
    ]
    for name, cmd, is_wp in candidates:
        if shutil.which(name):
            return name, cmd, is_wp
    return None, None, False


def _build_docx_file(out_path: Path, title: str, body_text: str) -> int:
    """Create a cleanly styled Word .docx document (typography, accent headings, bullets, spacing) with pure stdlib."""
    import re
    import zipfile
    from xml.sax.saxutils import escape

    out_path.parent.mkdir(parents=True, exist_ok=True)
    paras = []
    if title:
        paras.append(
            '<w:p><w:pPr><w:spacing w:before="0" w:after="120"/>'
            '<w:pBdr><w:bottom w:val="single" w:sz="12" w:space="6" w:color="1D4ED8"/></w:pBdr></w:pPr>'
            '<w:r><w:rPr><w:rFonts w:ascii="Noto Sans" w:hAnsi="Noto Sans"/><w:b/><w:color w:val="1E3A8A"/><w:sz w:val="38"/></w:rPr>'
            f'<w:t xml:space="preserve">{escape(title)}</w:t></w:r></w:p>'
        )

    def render_inline_runs(text_line: str, base_sz: int = 22, base_col: str = "1F2937") -> str:
        # Support simple **bold** inline spans cleanly
        tokens = re.split(r"(\*\*[^*]+\*\*)", text_line)
        runs = []
        for tok in tokens:
            if not tok:
                continue
            is_b = tok.startswith("**") and tok.endswith("**") and len(tok) > 4
            val = tok[2:-2] if is_b else tok
            b_xml = "<w:b/>" if is_b else ""
            runs.append(
                f'<w:r><w:rPr><w:rFonts w:ascii="Noto Sans" w:hAnsi="Noto Sans"/>{b_xml}'
                f'<w:color w:val="{base_col}"/><w:sz w:val="{base_sz}"/></w:rPr>'
                f'<w:t xml:space="preserve">{escape(val)}</w:t></w:r>'
            )
        return "".join(runs)

    for line in (body_text or "").splitlines():
        s = line.strip()
        if not s:
            paras.append('<w:p><w:pPr><w:spacing w:after="60"/></w:pPr></w:p>')
            continue
        if s.startswith("### "):
            clean = s[4:].strip()
            paras.append(
                '<w:p><w:pPr><w:spacing w:before="140" w:after="60"/></w:pPr>'
                + render_inline_runs(f"**{clean}**", base_sz=24, base_col="0F172A")
                + "</w:p>"
            )
        elif s.startswith("## "):
            clean = s[3:].strip()
            paras.append(
                '<w:p><w:pPr><w:spacing w:before="200" w:after="80"/></w:pPr>'
                + render_inline_runs(f"**{clean}**", base_sz=28, base_col="1E40AF")
                + "</w:p>"
            )
        elif s.startswith("# "):
            clean = s[2:].strip()
            if title and clean.lower() == title.strip().lower():
                continue
            paras.append(
                '<w:p><w:pPr><w:spacing w:before="220" w:after="100"/></w:pPr>'
                + render_inline_runs(f"**{clean}**", base_sz=32, base_col="1E3A8A")
                + "</w:p>"
            )
        elif re.match(r"^(?:[-*•]|\d+[.)])\s+", s):
            bullet_body = re.sub(r"^(?:[-*•]|\d+[.)])\s+", "", s)
            paras.append(
                '<w:p><w:pPr><w:spacing w:after="80" w:line="276" w:lineRule="auto"/>'
                '<w:ind w:left="360" w:hanging="180"/></w:pPr>'
                '<w:r><w:rPr><w:rFonts w:ascii="Noto Sans" w:hAnsi="Noto Sans"/><w:b/><w:color w:val="2563EB"/><w:sz w:val="22"/></w:rPr>'
                '<w:t xml:space="preserve">• </w:t></w:r>'
                + render_inline_runs(bullet_body, base_sz=22, base_col="1F2937")
                + "</w:p>"
            )
        else:
            paras.append(
                '<w:p><w:pPr><w:spacing w:after="110" w:line="276" w:lineRule="auto"/></w:pPr>'
                + render_inline_runs(s, base_sz=22, base_col="1F2937")
                + "</w:p>"
            )

    doc_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        f'<w:body>{"".join(paras)}'
        '<w:sectPr><w:pgMar w:top="1140" w:right="1140" w:bottom="1140" w:left="1140"/></w:sectPr>'
        '</w:body></w:document>'
    )
    ct_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-officedocument.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>'
    )
    rels_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>'
    )
    with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("[Content_Types].xml", ct_xml)
        zf.writestr("_rels/.rels", rels_xml)
        zf.writestr("word/document.xml", doc_xml)
    return out_path.stat().st_size


def cmd_write_docx(args):
    """Create a valid clean Word .docx file using only Python stdlib zipfile + XML (0 external deps)."""
    out_path = Path(args.path).expanduser()
    body_text = args.text or ""
    if args.file:
        body_text = Path(args.file).expanduser().read_text(encoding="utf-8")
    size = _build_docx_file(out_path, args.title or "", body_text)
    app_name, cmd, is_wp = detect_office_app()
    office_bin = app_name if is_wp else None
    if args.open and office_bin and cmd:
        subprocess.Popen([*cmd, str(out_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    print(json.dumps({"ok": True, "path": str(out_path), "bytes": size, "office_app": office_bin}, ensure_ascii=False))


def cmd_web_copy(args):
    """Browse like a human: launch Firefox search, click a real article, scroll down visibly, and copy clean text via Ctrl+A/Ctrl+C."""
    query = args.query.strip()
    search_url = (
        f"https://www.google.com/search?q={quote_plus(query)}"
        if args.engine == "google"
        else f"https://duckduckgo.com/?q={quote_plus(query)}&ia=web"
    )
    w, h, _ = get_monitor_info()
    notify_hud(w // 2, h // 2, "launch", f"Tìm: {query[:20]}", False, args.agent)
    subprocess.Popen(["firefox", search_url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    time.sleep(2.0)

    q_words = [tok for tok in strip_accents(query).split() if len(tok) >= 2]
    candidates = []
    if len(q_words) >= 3:
        candidates.append(" ".join(q_words[:3]))
    if len(q_words) >= 2:
        candidates.append(" ".join(q_words[:2]))
    candidates.extend(q_words[:2])

    clicked_title = ""
    with pointer_lock():
        hypr_focus("firefox")
        time.sleep(0.2)
        search_title = _firefox_title()
        hits = []
        deadline = time.time() + 6.0
        while time.time() < deadline and not hits:
            # Scan whole Firefox window first for CAPTCHA guard (never bypass!)
            chk = _ocr_scan_once("unusual traffic", "firefox", "auto") or _ocr_scan_once("verify you are human", "firefox", "auto")
            if chk:
                print(json.dumps({"ok": False, "blocked": "captcha", "error": "Anti-bot / CAPTCHA verification detected"}))
                sys.exit(2)
            ui_junk = ("generate answer", "duckassist", "news for", "images for", "videos for", "people also", "more results", "search instead", "feedback")
            for cand in candidates:
                raw_hits = _ocr_scan_once(cand, "firefox", "auto", min_y=230)
                non_ui = [
                    item for item in raw_hits
                    if len(item["text"].strip()) >= 18 and not any(j in item["text"].lower() for j in ui_junk)
                ]
                # Prefer article result headlines lower down (below instant answer box) when available
                below_ia = [item for item in non_ui if item["y"] >= 310]
                hits = below_ia or non_ui or raw_hits
                if hits:
                    break
            if not hits:
                time.sleep(0.45)

        if not hits:
            print(json.dumps({"ok": False, "error": f"No article link found visually for '{query}'"}))
            sys.exit(1)

        target = hits[0]
        clicked_title = target["text"]
        ax, ay = calibrated_move(target["x"], target["y"], "Mở bài viết", args.agent)
        notify_hud(ax, ay, "click", "Click bài viết", True, args.agent)
        run(["ydotool", "click", BUTTON_CODES["left"]])

    # Wait cleanly for article page load; if still on search page, try fallback hit[1] cleanly
    time.sleep(2.2)
    if _firefox_title() == search_title and len(hits) > 1:
        with pointer_lock():
            hypr_focus("firefox")
            time.sleep(0.1)
            target = hits[1]
            clicked_title = target["text"]
            ax, ay = calibrated_move(target["x"], target["y"], "Mở bài viết #2", args.agent)
            notify_hud(ax, ay, "click", "Click bài viết", True, args.agent)
            run(["ydotool", "click", BUTTON_CODES["left"]])
        time.sleep(2.2)
    with pointer_lock():
        hypr_focus("firefox")
        time.sleep(0.15)
        fc = find_client("firefox")
        cx = int(fc["at"][0] + fc["size"][0] / 2) if fc else w // 2
        cy = int(fc["at"][1] + fc["size"][1] / 2) if fc else h // 2
        calibrated_move(cx, cy, "Chuyển chế độ đọc sạch", args.agent)
        # Try Firefox Reader View (Ctrl+Alt+R); harmless no-op on pages that don't support it
        press_combo("ctrl+alt+r")
        time.sleep(0.8)
        for _ in range(max(1, args.scrolls)):
            notify_hud(cx, cy, "scroll", "Cuộn trang đọc bài", False, args.agent)
            run(["ydotool", "mousemove", "-w", "-x", "0", "-y", "-5"])
            time.sleep(0.4)

        notify_hud(cx, cy, "click", "Chọn nội dung (Ctrl+A)", True, args.agent)
        run(["ydotool", "click", BUTTON_CODES["left"]])
        time.sleep(0.08)
        press_combo("ctrl+a")
        time.sleep(0.15)
        notify_hud(cx, cy, "key", "Sao chép (Ctrl+C)", False, args.agent)
        press_combo("ctrl+c")
        time.sleep(0.25)

    clip = run(["wl-paste", "--no-newline"]).stdout
    noise_pats = (
        "skip to content", "skip to main", "cookie", "accept all", "privacy policy",
        "terms of service", "sign in", "log in", "subscribe", "global navigation",
        "choose your location", "close location", "read more", "share this", "alt=\"\"",
        "advertisement", "all rights reserved",
    )
    lines = []
    seen = set()
    for ln in clip.splitlines():
        st = ln.strip()
        low_l = st.lower()
        if len(st) < 25 and not st.endswith(":"):
            # Drop short UI/nav button crumbs while keeping real short headings ending cleanly
            continue
        if any(np in low_l for np in noise_pats):
            continue
        if st in seen:
            continue
        seen.add(st)
        lines.append(st)
    clean_clip = "\n".join(lines[:140])
    if not clean_clip.strip():
        clean_clip = "\n".join(ln.strip() for ln in clip.splitlines() if len(ln.strip()) >= 8)[:6000]
    if clean_clip:
        wl_copy_safe(clean_clip)
        Path("/tmp/ai_web_copied.txt").write_text(
            f"PAGE_TITLE: {_firefox_title()}\nMATCHED_LINK: {clicked_title}\n\n{clean_clip}",
            encoding="utf-8",
        )

    if len(clean_clip.strip()) < 80:
        print(json.dumps({"ok": False, "error": "Clipboard text too short after copy", "chars": len(clean_clip)}))
        sys.exit(1)

    print(json.dumps({
        "ok": True,
        "matched_link": clicked_title,
        "page_title": _firefox_title(),
        "changed_page": _firefox_title() != search_title,
        "chars": len(clean_clip),
        "raw_file": "/tmp/ai_web_copied.txt",
        "preview": clean_clip[:220],
    }, ensure_ascii=False))


def cmd_office_paste(args):
    """Open highest-priority compatible Office/Editor app on OS, visually paste clipboard via Ctrl+V, and optionally save .docx."""
    clip = run(["wl-paste", "--no-newline"]).stdout
    if args.source_file:
        clip = Path(args.source_file).expanduser().read_text(encoding="utf-8")
        wl_copy_safe(clip)
    if not clip.strip():
        print(json.dumps({"ok": False, "error": "Clipboard is empty; nothing to paste"}))
        sys.exit(1)

    app_name, cmd, is_wp = detect_office_app()
    saved_docx = None
    if args.docx:
        out_p = Path(args.docx).expanduser()
        _build_docx_file(out_p, args.title or out_p.stem.replace("_", " "), clip)
        saved_docx = str(out_p)

    if not app_name or not cmd:
        print(json.dumps({"ok": bool(saved_docx), "office_installed": False, "app": None, "docx": saved_docx}))
        return

    w, h, _ = get_monitor_info()
    notify_hud(w // 2, h // 2, "launch", f"Mở {app_name}", False, args.agent)
    launch_cmd = list(cmd)
    # If real Word processor (LibreOffice/OnlyOffice) AND docx was built, open that .docx directly or open blank & Ctrl+V
    if is_wp and saved_docx:
        launch_cmd.append(saved_docx)
    subprocess.Popen(launch_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)

    # Wait for the real document editor window (skip splash screens / Welcome dialogs!)
    win = None
    match_token = "libreoffice-writer" if ("libreoffice" in app_name or app_name == "lowriter") else app_name
    deadline = time.time() + 8.0
    while time.time() < deadline:
        res_c = run(["hyprctl", "clients", "-j"])
        try:
            clients = json.loads(res_c.stdout)
            for c in clients:
                cls = str(c.get("class", "")).lower()
                ttl = str(c.get("title", "")).lower()
                sz = c.get("size") or [0, 0]
                if sz[0] >= 750 and "welcome" not in ttl and (match_token in cls or match_token.split("-")[0] in ttl):
                    win = c
                    break
        except Exception:
            pass
        if win:
            break
        time.sleep(0.35)

    pasted = False
    if win:
        with pointer_lock():
            hypr_focus(win["address"])
            time.sleep(0.35)
            cx = int(win["at"][0] + win["size"][0] / 2)
            cy = int(win["at"][1] + win["size"][1] / 2)
            ax, ay = calibrated_move(cx, cy, f"Mở & soạn thảo ({app_name})", args.agent)
            notify_hud(ax, ay, "click", "Chọn trang văn bản", True, args.agent)
            run(["ydotool", "click", BUTTON_CODES["left"]])
            time.sleep(0.15)
            if is_wp and saved_docx:
                # Scroll gently to show styled LibreOffice Writer pages visibly
                notify_hud(ax, ay, "scroll", "Xem bố cục Word", False, args.agent)
                run(["ydotool", "mousemove", "-w", "-x", "0", "-y", "-2"])
            else:
                wl_copy_safe(clip)
                time.sleep(0.08)
                notify_hud(ax, ay, "key", "Dán nội dung (Ctrl+V)", False, args.agent)
                press_combo("ctrl+v")
            pasted = True

    print(json.dumps({
        "ok": pasted or bool(saved_docx),
        "app": app_name,
        "is_word_processor": is_wp,
        "pasted": pasted,
        "docx": saved_docx,
    }, ensure_ascii=False))


def cmd_ocr(args):
    tmp = "/tmp/ai_ocr_cap.png"
    cmd = ["grim"]
    if args.region:
        cmd.extend(["-g", args.region])
    cmd.append(tmp)
    run(cmd)
    res = run(["tesseract", tmp, "stdout", "-l", args.lang, "--psm", "6"])
    print(res.stdout.strip())


def main():
    p = argparse.ArgumentParser(description="Caelestia Desktop Control Helper")
    p.add_argument("--agent", default="Meow AI", help="Named visual cursor agent label")
    sub = p.add_subparsers(dest="sub", required=True)

    def add_agent_arg(sp_obj):
        sp_obj.add_argument("--agent", default=None, help="Override visual cursor agent label")

    sp = sub.add_parser("screen", help="Capture screen (optionally with pixel coordinate grid)")
    sp.add_argument("--grid", action="store_true")
    sp.add_argument("--fast", action="store_true", help="Downscale grid screenshot cleanly for faster AI vision decode")
    sp.add_argument("--region", help="Optional region 'x,y wxh'")
    sp.add_argument("--out", default="/tmp/ai_screen.png")
    add_agent_arg(sp)
    sp.set_defaults(func=cmd_screen)

    wp = sub.add_parser("windows", help="List Hyprland windows & geometry")
    add_agent_arg(wp)
    wp.set_defaults(func=cmd_windows)

    fp = sub.add_parser("focus", help="Focus window by title substring, class, or address")
    fp.add_argument("target")
    add_agent_arg(fp)
    fp.set_defaults(func=cmd_focus)

    lp = sub.add_parser("launch", help="Launch GUI application in background")
    lp.add_argument("cmd", nargs=argparse.REMAINDER)
    add_agent_arg(lp)
    lp.set_defaults(func=cmd_launch)

    mp = sub.add_parser("move", help="Move cursor accurately to screen (x, y)")
    mp.add_argument("x", type=int)
    mp.add_argument("y", type=int)
    add_agent_arg(mp)
    mp.set_defaults(func=cmd_move)

    cp = sub.add_parser("click", help="Click accurately at screen (x, y)")
    cp.add_argument("x", type=int)
    cp.add_argument("y", type=int)
    cp.add_argument("--button", choices=["left", "right", "middle"], default="left")
    cp.add_argument("--double", action="store_true")
    add_agent_arg(cp)
    cp.set_defaults(func=cmd_click)

    scp = sub.add_parser("scroll", help="Scroll mouse wheel")
    scp.add_argument("delta", type=int, help="Negative=down, Positive=up")
    scp.add_argument("--x", type=int)
    scp.add_argument("--y", type=int)
    add_agent_arg(scp)
    scp.set_defaults(func=cmd_scroll)

    tp = sub.add_parser("type", help="Type text (supports Vietnamese/Unicode automatically via Ctrl+V)")
    tp.add_argument("text")
    tp.add_argument("--enter", action="store_true")
    tp.add_argument("--paste", action="store_true")
    add_agent_arg(tp)
    tp.set_defaults(func=cmd_type)

    kp = sub.add_parser("key", help="Press key combo e.g. ctrl+l, ctrl+t, alt+tab, enter")
    kp.add_argument("combo")
    add_agent_arg(kp)
    kp.set_defaults(func=cmd_key)

    fnd = sub.add_parser("find", help="Find on-screen UI text and return exact (x, y) pixel centers")
    fnd.add_argument("query")
    fnd.add_argument("--window", default=None, help="Limit OCR to window class/title substring")
    fnd.add_argument("--lang", default="auto")
    fnd.add_argument("--wait", type=float, default=0.0, help="Wait/poll seconds until matching text appears")
    fnd.add_argument("--min-y", type=int, default=0, help="Skip hits above this Y coordinate (e.g. skip browser search bar)")
    add_agent_arg(fnd)
    fnd.set_defaults(func=cmd_find)

    ct = sub.add_parser("click-text", help="Locate text on screen and immediately glide cursor + click it")
    ct.add_argument("query")
    ct.add_argument("--window", default=None, help="Limit OCR to window class/title substring")
    ct.add_argument("--lang", default="auto")
    ct.add_argument("--wait", type=float, default=0.0, help="Wait/poll seconds until matching text appears")
    ct.add_argument("--min-y", type=int, default=0, help="Skip hits above this Y coordinate (e.g. skip browser search bar)")
    ct.add_argument("--index", type=int, default=0)
    ct.add_argument("--button", choices=["left", "right", "middle"], default="left")
    add_agent_arg(ct)
    ct.set_defaults(func=cmd_click_text)

    ytp = sub.add_parser("yt-play", help="Open YouTube search in Firefox, click video below header, wait for autoplay, and verify audio")
    ytp.add_argument("query")
    add_agent_arg(ytp)
    ytp.set_defaults(func=cmd_yt_play)

    wdx = sub.add_parser("write-docx", help="Create a valid Word .docx document instantaneously with zero dependencies")
    wdx.add_argument("path")
    wdx.add_argument("--title", default="")
    wdx.add_argument("--text", default="")
    wdx.add_argument("--file", default="")
    wdx.add_argument("--open", action="store_true")
    wdx.set_defaults(func=cmd_write_docx)

    wcp = sub.add_parser("web-copy", help="Browse visually in Firefox, click article link, scroll down, and copy text via Ctrl+A/Ctrl+C")
    wcp.add_argument("query")
    wcp.add_argument("--engine", choices=["ddg", "google"], default="ddg")
    wcp.add_argument("--scrolls", type=int, default=2)
    add_agent_arg(wcp)
    wcp.set_defaults(func=cmd_web_copy)

    ofp = sub.add_parser("office-paste", help="Open compatible Office/Editor app on OS, visually paste clipboard via Ctrl+V, and optionally save .docx")
    ofp.add_argument("--docx", default="", help="Optional .docx output path under ~/Documents/")
    ofp.add_argument("--title", default="")
    ofp.add_argument("--source-file", default="")
    add_agent_arg(ofp)
    ofp.set_defaults(func=cmd_office_paste)

    op = sub.add_parser("ocr", help="Run tesseract OCR on current screen or region")
    op.add_argument("--region")
    op.add_argument("--lang", default="eng+vie")
    add_agent_arg(op)
    op.set_defaults(func=cmd_ocr)

    args = p.parse_args()
    if getattr(args, "agent", None) is None:
        args.agent = "Meow AI"
    args.func(args)


if __name__ == "__main__":
    main()
