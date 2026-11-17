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


def ensure_spacious_workspace(target_app: str = "", min_w: int = 820, min_h: int = 480, max_windows: int = 1, agent: str = "Meow AI") -> dict:
    """Check active Hyprland workspace free space/readability; switch to a clean empty workspace if crowded."""
    try:
        aw = json.loads(run(["hyprctl", "activeworkspace", "-j"]).stdout or "{}")
        cur_ws = int(aw.get("id") or 1)
        has_fs = bool(aw.get("hasfullscreen"))
        clients = json.loads(run(["hyprctl", "clients", "-j"]).stdout or "[]")
        workspaces = json.loads(run(["hyprctl", "workspaces", "-j"]).stdout or "[]")
    except Exception:
        return {"ok": True, "workspace": 1, "switched": False, "reason": "hyprctl_unavailable"}

    tiled = [
        c for c in clients
        if int((c.get("workspace") or {}).get("id") or -1) == cur_ws
        and c.get("mapped", True)
        and not c.get("hidden", False)
        and not c.get("floating", False)
        and (c.get("size") or [0, 0])[0] >= 200
        and (c.get("size") or [0, 0])[1] >= 150
    ]

    need_t = (target_app or "").lower().strip()
    if need_t:
        same_win = [
            c for c in tiled
            if need_t in str(c.get("class") or "").lower() or need_t in str(c.get("title") or "").lower()
        ]
        if same_win and not has_fs:
            sz = same_win[0].get("size") or [0, 0]
            if sz[0] >= min_w and sz[1] >= min_h:
                return {"ok": True, "workspace": cur_ws, "switched": False, "reason": "target_already_spacious", "windows": len(tiled)}

    too_small = any(
        (c.get("size") or [0, 0])[0] < min_w or (c.get("size") or [0, 0])[1] < min_h
        for c in tiled
    )
    half_risk = (len(tiled) == 1) and ((tiled[0].get("size") or [0, 0])[0] < 1150 or (tiled[0].get("size") or [0, 0])[1] < 650)
    crowded = has_fs or (len(tiled) > max_windows) or too_small or half_risk
    if not crowded:
        return {"ok": True, "workspace": cur_ws, "switched": False, "reason": "workspace_spacious", "windows": len(tiled)}

    used_ids = {int(w.get("id") or 0) for w in workspaces if int(w.get("windows") or 0) > 0}
    used_ids.add(cur_ws)
    new_ws = next((wid for wid in range(1, 21) if wid not in used_ids), cur_ws + 1)
    run(["hyprctl", "dispatch", "workspace", str(new_ws)])
    time.sleep(0.25)
    mw, mh, _ = get_monitor_info()
    notify_hud(mw // 2, 90, "desktop_windows", f"Workspace #{new_ws} (đủ rộng)", False, agent)
    return {"ok": True, "workspace": new_ws, "prev_workspace": cur_ws, "switched": True, "reason": f"crowded({len(tiled)}_wins)", "windows": 0}


def cmd_ensure_workspace(args):
    res = ensure_spacious_workspace(
        target_app=args.app or "",
        min_w=args.min_w,
        min_h=args.min_h,
        max_windows=args.max_windows,
        agent=args.agent,
    )
    print(json.dumps(res, ensure_ascii=False))


def cmd_launch(args):
    cmd = list(args.cmd or [])
    keep_ws = False
    if "--keep-workspace" in cmd:
        keep_ws = True
        cmd = [c for c in cmd if c != "--keep-workspace"]
    app_name = Path(cmd[0]).name if cmd else "app"
    ws_info = {} if keep_ws else ensure_spacious_workspace(target_app=app_name, agent=args.agent)
    w, h, _ = get_monitor_info()
    notify_hud(w // 2, h // 2, "launch", f"Mở {app_name}", False, args.agent)
    subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    print(json.dumps({"ok": True, "launched": cmd, "workspace": ws_info}, ensure_ascii=False))


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
    ensure_spacious_workspace(target_app="firefox", agent=args.agent)
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
                raw_hits = _ocr_scan_once(cand, "firefox", "auto", min_y=245)
                long_hits = [h for h in raw_hits if len(h["text"].strip()) >= 18]
                hits = long_hits or raw_hits
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

    # Wait up to 4.5s for YouTube autoplay; if title didn't leave search page, try hit[1] cleanly
    cur_title = search_title
    is_playing = False
    deadline = time.time() + 4.5
    while time.time() < deadline:
        cur_title = _firefox_title()
        _, is_playing = _firefox_audio_corked()
        if is_playing:
            time.sleep(0.45)
            _, is_playing = _firefox_audio_corked()
            if is_playing:
                break
        time.sleep(0.4)

    if not is_playing and _firefox_title() == search_title and len(hits) > 1:
        with pointer_lock():
            hypr_focus("firefox")
            t2 = hits[1]
            clicked_match = t2["text"]
            ax, ay = calibrated_move(t2["x"], t2["y"], "Thử video #2", args.agent)
            notify_hud(ax, ay, "click", "Click video #2", True, args.agent)
            run(["ydotool", "click", BUTTON_CODES["left"]])
        deadline_r = time.time() + 4.0
        while time.time() < deadline_r:
            cur_title = _firefox_title()
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

    shot_saved = ""
    if is_playing and getattr(args, "fullscreen", False):
        with pointer_lock():
            hypr_focus("firefox")
            time.sleep(0.15)
            notify_hud(w // 2, h // 2, "key", "Toàn màn hình (f)", False, args.agent)
            press_combo("f")
        time.sleep(0.8)

    if is_playing and getattr(args, "screenshot", ""):
        shot_p = Path(args.screenshot).expanduser()
        shot_p.parent.mkdir(parents=True, exist_ok=True)
        raw_shot = str(shot_p.with_suffix(".png"))
        run(["grim", raw_shot])
        try:
            with Image.open(raw_shot) as im:
                im.convert("RGB").save(shot_p, "JPEG", quality=88)
            Path(raw_shot).unlink(missing_ok=True)
            shot_saved = str(shot_p)
        except Exception:
            shot_saved = ""

    out_obj = {
        "ok": bool(is_playing),
        "playing": bool(is_playing),
        "matched": clicked_match,
        "title": _firefox_title(),
        "screenshot": shot_saved,
    }
    print(json.dumps(out_obj, ensure_ascii=False))
    if not is_playing:
        sys.exit(1)


def detect_office_app() -> tuple[str | None, list[str] | None, bool]:
    """Return (app_name, launch_cmd, is_word_processor) including native, Flatpak LibreOffice, and LinOffice Word."""
    import shutil
    candidates = [
        ("lowriter", ["lowriter", "--nologo", "--norestore"], True),
        ("libreoffice", ["libreoffice", "--writer", "--nologo", "--norestore"], True),
        ("onlyoffice-desktopeditors", ["onlyoffice-desktopeditors"], True),
        ("wps", ["wps"], True),
        ("abiword", ["abiword"], True),
    ]
    for name, cmd, is_wp in candidates:
        if shutil.which(name):
            return name, cmd, is_wp
    # Check Flatpak LibreOffice (user or system)
    if shutil.which("flatpak"):
        fp = run(["flatpak", "info", "org.libreoffice.LibreOffice"])
        if fp.returncode == 0:
            return "libreoffice-flatpak", ["flatpak", "run", "org.libreoffice.LibreOffice", "--writer", "--nologo", "--norestore"], True
    # Check LinOffice (containerized Microsoft Word)
    linoffice_sh = Path.home() / ".local/bin/linoffice/linoffice.sh"
    if linoffice_sh.exists():
        return "linoffice-word", [str(linoffice_sh), "word"], True
    for name, cmd, is_wp in [("kate", ["kate", "--new"], False), ("code", ["code", "--new-window"], False)]:
        if shutil.which(name):
            return name, cmd, is_wp
    return None, None, False


def _build_docx_file(
    out_path: Path,
    title: str,
    body_text: str,
    image_path: str | None = None,
    image_paths: list[str] | None = None,
) -> int:
    """Create a richly styled Word .docx (Noto Sans, accent headings, Markdown tables, bullets, 1 or multiple embedded images)."""
    import re
    import zipfile
    from io import BytesIO
    from xml.sax.saxutils import escape

    out_path.parent.mkdir(parents=True, exist_ok=True)
    raw_imgs = list(image_paths or [])
    if image_path and image_path not in raw_imgs:
        raw_imgs.insert(0, image_path)

    loaded_imgs = []  # list of (rid, fname, bytes, emu_w, emu_h)
    for idx, ip in enumerate(raw_imgs[:8], start=1):
        p_img = Path(ip).expanduser()
        if not p_img.exists():
            continue
        try:
            with Image.open(p_img) as im:
                im_rgb = im.convert("RGB")
                if im_rgb.width > 960:
                    nh = max(120, round(im_rgb.height * (960 / im_rgb.width)))
                    im_rgb = im_rgb.resize((960, nh), Image.Resampling.LANCZOS)
                buf = BytesIO()
                im_rgb.save(buf, "JPEG", quality=86)
                emu_w = 5200000
                emu_h = max(1200000, round(emu_w * (im_rgb.height / max(1, im_rgb.width))))
                loaded_imgs.append((f"rIdImg{idx}", f"image{idx}.jpg", buf.getvalue(), emu_w, emu_h, idx))
        except Exception:
            continue

    def _render_img_para(rid: str, fname: str, emu_w: int, emu_h: int, doc_id: int) -> str:
        return (
            '<w:p><w:pPr><w:jc w:val="center"/><w:spacing w:before="80" w:after="140"/></w:pPr><w:r><w:drawing>'
            '<wp:inline distT="0" distB="0" distL="0" distR="0" '
            'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">'
            f'<wp:extent cx="{emu_w}" cy="{emu_h}"/>'
            f'<wp:docPr id="{doc_id}" name="{fname}"/>'
            '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
            '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
            '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
            f'<pic:nvPicPr><pic:cNvPr id="{doc_id}" name="{fname}"/><pic:cNvPicPr/></pic:nvPicPr>'
            f'<pic:blipFill><a:blip r:embed="{rid}" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/>'
            '<a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
            '<pic:spPr><a:xfrm><a:off x="0" y="0"/>'
            f'<a:ext cx="{emu_w}" cy="{emu_h}"/></a:xfrm>'
            '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
            '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>'
        )

    def render_inline_runs(text_line: str, base_sz: int = 22, base_col: str = "1F2937", force_bold: bool = False) -> str:
        tokens = re.split(r"(\*\*[^*]+\*\*)", text_line)
        runs = []
        for tok in tokens:
            if not tok:
                continue
            is_b = force_bold or (tok.startswith("**") and tok.endswith("**") and len(tok) > 4)
            val = tok[2:-2] if (tok.startswith("**") and tok.endswith("**") and len(tok) > 4) else tok
            b_xml = "<w:b/>" if is_b else ""
            runs.append(
                f'<w:r><w:rPr><w:rFonts w:ascii="Noto Sans" w:hAnsi="Noto Sans"/>{b_xml}'
                f'<w:color w:val="{base_col}"/><w:sz w:val="{base_sz}"/></w:rPr>'
                f'<w:t xml:space="preserve">{escape(val)}</w:t></w:r>'
            )
        return "".join(runs)

    blocks = []
    if title:
        blocks.append(
            '<w:p><w:pPr><w:spacing w:before="0" w:after="140"/>'
            '<w:pBdr><w:bottom w:val="single" w:sz="12" w:space="6" w:color="1D4ED8"/></w:pBdr></w:pPr>'
            + render_inline_runs(title, base_sz=38, base_col="1E3A8A", force_bold=True)
            + "</w:p>"
        )

    if loaded_imgs:
        # Place hero image right below title; place additional images cleanly across body sections or gallery
        blocks.append(_render_img_para(*loaded_imgs[0][:2], loaded_imgs[0][3], loaded_imgs[0][4], loaded_imgs[0][5]))

    raw_lines = (body_text or "").splitlines()
    i = 0
    while i < len(raw_lines):
        s = raw_lines[i].strip()
        if not s:
            blocks.append('<w:p><w:pPr><w:spacing w:after="60"/></w:pPr></w:p>')
            i += 1
            continue

        # Render Markdown table blocks (`| a | b |`) cleanly into styled Word tables
        if s.startswith("|") and "|" in s[1:]:
            t_rows = []
            while i < len(raw_lines) and raw_lines[i].strip().startswith("|"):
                row_s = raw_lines[i].strip().strip("|")
                cells = [c.strip() for c in row_s.split("|")]
                if not all(re.fullmatch(r"[-:\s]+", c or "-") for c in cells):
                    t_rows.append(cells)
                i += 1
            if t_rows:
                ncols = max(len(r) for r in t_rows)
                col_w = max(1400, 9000 // max(1, ncols))
                tbl_xml = [
                    '<w:tbl><w:tblPr><w:tblW w:w="9000" w:type="dxa"/>'
                    '<w:tblBorders>'
                    '<w:top w:val="single" w:sz="6" w:color="CBD5E1"/>'
                    '<w:left w:val="single" w:sz="6" w:color="CBD5E1"/>'
                    '<w:bottom w:val="single" w:sz="6" w:color="CBD5E1"/>'
                    '<w:right w:val="single" w:sz="6" w:color="CBD5E1"/>'
                    '<w:insideH w:val="single" w:sz="4" w:color="E2E8F0"/>'
                    '<w:insideV w:val="single" w:sz="4" w:color="E2E8F0"/>'
                    '</w:tblBorders></w:tblPr>'
                ]
                for r_idx, row in enumerate(t_rows):
                    is_hdr = (r_idx == 0)
                    bg = "1E40AF" if is_hdr else ("F8FAFC" if r_idx % 2 == 1 else "FFFFFF")
                    fg = "FFFFFF" if is_hdr else "1F2937"
                    tbl_xml.append("<w:tr>")
                    for c_idx in range(ncols):
                        val = row[c_idx] if c_idx < len(row) else ""
                        tbl_xml.append(
                            f'<w:tc><w:tcPr><w:tcW w:w="{col_w}" w:type="dxa"/>'
                            f'<w:shd w:val="clear" w:color="auto" w:fill="{bg}"/>'
                            '<w:tcMar><w:top w:w="80" w:type="dxa"/><w:bottom w:w="80" w:type="dxa"/>'
                            '<w:left w:w="120" w:type="dxa"/><w:right w:w="120" w:type="dxa"/></w:tcMar></w:tcPr>'
                            '<w:p><w:pPr><w:spacing w:before="20" w:after="20"/></w:pPr>'
                            + render_inline_runs(val, base_sz=20, base_col=fg, force_bold=is_hdr)
                            + "</w:p></w:tc>"
                        )
                    tbl_xml.append("</w:tr>")
                tbl_xml.append("</w:tbl><w:p><w:pPr><w:spacing w:after=\"100\"/></w:pPr></w:p>")
                blocks.append("".join(tbl_xml))
            continue

        i += 1
        if s.startswith("### "):
            clean = s[4:].strip()
            blocks.append(
                '<w:p><w:pPr><w:spacing w:before="140" w:after="60"/></w:pPr>'
                + render_inline_runs(clean, base_sz=24, base_col="0F172A", force_bold=True)
                + "</w:p>"
            )
        elif s.startswith("## "):
            clean = s[3:].strip()
            blocks.append(
                '<w:p><w:pPr><w:spacing w:before="200" w:after="80"/></w:pPr>'
                + render_inline_runs(clean, base_sz=28, base_col="1E40AF", force_bold=True)
                + "</w:p>"
            )
        elif s.startswith("# "):
            clean = s[2:].strip()
            if title and clean.lower() == title.strip().lower():
                continue
            blocks.append(
                '<w:p><w:pPr><w:spacing w:before="220" w:after="100"/></w:pPr>'
                + render_inline_runs(clean, base_sz=32, base_col="1E3A8A", force_bold=True)
                + "</w:p>"
            )
        elif re.match(r"^(?:[-*•]|\d+[.)])\s+", s):
            bullet_body = re.sub(r"^(?:[-*•]|\d+[.)])\s+", "", s)
            blocks.append(
                '<w:p><w:pPr><w:spacing w:after="80" w:line="276" w:lineRule="auto"/>'
                '<w:ind w:left="360" w:hanging="180"/></w:pPr>'
                '<w:r><w:rPr><w:rFonts w:ascii="Noto Sans" w:hAnsi="Noto Sans"/><w:b/><w:color w:val="2563EB"/><w:sz w:val="22"/></w:rPr>'
                '<w:t xml:space="preserve">• </w:t></w:r>'
                + render_inline_runs(bullet_body, base_sz=22, base_col="1F2937")
                + "</w:p>"
            )
        else:
            blocks.append(
                '<w:p><w:pPr><w:spacing w:after="110" w:line="276" w:lineRule="auto"/></w:pPr>'
                + render_inline_runs(s, base_sz=22, base_col="1F2937")
                + "</w:p>"
            )

    if len(loaded_imgs) > 1:
        for extra in loaded_imgs[1:]:
            blocks.append(_render_img_para(extra[0], extra[1], extra[3], extra[4], extra[5]))

    doc_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        f'<w:body>{"".join(blocks)}'
        '<w:sectPr><w:pgMar w:top="1140" w:right="1140" w:bottom="1140" w:left="1140"/></w:sectPr>'
        '</w:body></w:document>'
    )
    img_ct = '<Default Extension="jpg" ContentType="image/jpeg"/>' if loaded_imgs else ""
    ct_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-officedocument.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        f'{img_ct}'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>'
    )
    rels_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>'
    )
    rel_entries = "".join(
        f'<Relationship Id="{item[0]}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/{item[1]}"/>'
        for item in loaded_imgs
    )
    doc_rels_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        f'{rel_entries}'
        '</Relationships>'
    )
    with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("[Content_Types].xml", ct_xml)
        zf.writestr("_rels/.rels", rels_xml)
        zf.writestr("word/document.xml", doc_xml)
        if loaded_imgs:
            zf.writestr("word/_rels/document.xml.rels", doc_rels_xml)
            for item in loaded_imgs:
                zf.writestr(f"word/media/{item[1]}", item[2])
    return out_path.stat().st_size


def cmd_write_docx(args):
    """Create a valid clean Word .docx file using only Python stdlib zipfile + XML (0 external deps)."""
    out_path = Path(args.path).expanduser()
    body_text = args.text or ""
    if args.file:
        body_text = Path(args.file).expanduser().read_text(encoding="utf-8")
    imgs = [s.strip() for s in (getattr(args, "images", "") or "").split(",") if s.strip()]
    size = _build_docx_file(out_path, args.title or "", body_text, image_path=args.image or None, image_paths=imgs)
    app_name, cmd, is_wp = detect_office_app()
    office_bin = app_name if is_wp else None
    if args.open and office_bin and cmd:
        subprocess.Popen([*cmd, str(out_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    print(json.dumps({"ok": True, "path": str(out_path), "bytes": size, "office_app": office_bin}, ensure_ascii=False))


def _extract_article_image_from_html(page_url: str, html_txt: str, out_img: Path, query_hint: str = "") -> str:
    """Extract verified, relevant hero artwork/photo (>=360x200) from article HTML, rejecting tiny icons/logos."""
    import re
    import urllib.request
    from urllib.parse import urljoin

    bad_url = ("logo", "avatar", "icon", "favicon", "badge", "spinner", ".svg", "placeholder", "emoji", "1x1", "blank", "ads/", "doubleclick")
    candidates_img = []
    for pat in (
        r'<meta[^>]+(?:property|name)=["\'](?:og:image|twitter:image)["\'][^>]+content=["\']([^"\']+)["\']',
        r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+(?:property|name)=["\'](?:og:image|twitter:image)["\']',
        r'<img[^>]+(?:src|data-src)=["\']([^"\']+)["\']',
    ):
        for found in re.findall(pat, html_txt, re.I):
            low_f = found.lower()
            if found and not found.startswith("data:") and not any(b in low_f for b in bad_url):
                candidates_img.append(urljoin(page_url, found.strip()))

    for img_url in candidates_img[:10]:
        try:
            raw_img = urllib.request.urlopen(urllib.request.Request(img_url, headers={"User-Agent": "Mozilla/5.0"}), timeout=4.5).read()
            if len(raw_img) >= 14000:
                out_img.parent.mkdir(parents=True, exist_ok=True)
                out_img.write_bytes(raw_img)
                with Image.open(out_img) as im:
                    if im.width >= 360 and im.height >= 200:
                        im.convert("RGB").save(out_img, "JPEG", quality=88)
                        return str(out_img)
                out_img.unlink(missing_ok=True)
        except Exception:
            continue
    return ""


def _fetch_verified_ddg_images(query: str, base_out: Path, count: int = 1, existing: list[str] | None = None) -> list[str]:
    """Fallback: fetch up to `count` distinct landscape images matching query keywords via DuckDuckGo i.js."""
    import re
    import urllib.parse
    import urllib.request

    saved = list(existing or [])
    if len(saved) >= count:
        return saved[:count]
    q_words = [w.lower() for w in re.findall(r"[A-Za-z0-9]{2,}", query) if w.lower() not in {"game", "new", "upcoming", "official", "image", "artwork", "the", "and", "news", "specs"}]
    bad_url = ("logo.wine", "lookaside.fbsbx", "favicon", "sprite", "svg")
    try:
        search_u = "https://duckduckgo.com/?q=" + urllib.parse.quote_plus(query) + "&iax=images&ia=images"
        html_txt = urllib.request.urlopen(urllib.request.Request(search_u, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) Firefox/131.0"}), timeout=5.0).read().decode("utf-8", errors="ignore")
        m = re.search(r'vqd=["\']?([^"\'&]+)', html_txt)
        if not m:
            return saved
        vqd = m.group(1)
        api = f"https://duckduckgo.com/i.js?l=us-en&o=json&q={urllib.parse.quote_plus(query)}&vqd={vqd}&f=,,,&p=1"
        raw = urllib.request.urlopen(urllib.request.Request(api, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) Firefox/131.0", "Referer": "https://duckduckgo.com/"}), timeout=5.0).read().decode("utf-8", errors="ignore")
        results = json.loads(raw).get("results", [])
        seen_sizes = set()
        for r in results[:18]:
            if len(saved) >= count:
                break
            title_l = str(r.get("title") or "").lower()
            img_u = str(r.get("image") or "")
            thumb_u = str(r.get("thumbnail") or "")
            if int(r.get("width") or 0) < 420 or int(r.get("height") or 0) < 220:
                continue
            if any(b in img_u.lower() for b in bad_url):
                continue
            if q_words and not any(kw in title_l or kw in img_u.lower() for kw in q_words):
                continue
            idx = len(saved) + 1
            out_img = base_out if idx == 1 else base_out.with_name(f"{base_out.stem}_{idx}{base_out.suffix}")
            for try_u in (img_u, thumb_u):
                if not try_u:
                    continue
                try:
                    raw_img = urllib.request.urlopen(urllib.request.Request(try_u, headers={"User-Agent": "Mozilla/5.0"}), timeout=4.5).read()
                    if len(raw_img) >= 12000 and len(raw_img) not in seen_sizes:
                        out_img.parent.mkdir(parents=True, exist_ok=True)
                        out_img.write_bytes(raw_img)
                        with Image.open(out_img) as im:
                            if im.width >= 320 and im.height >= 180:
                                im.convert("RGB").save(out_img, "JPEG", quality=88)
                                seen_sizes.add(len(raw_img))
                                saved.append(str(out_img))
                                break
                        out_img.unlink(missing_ok=True)
                except Exception:
                    continue
    except Exception:
        pass
    return saved


def _is_privacy_or_stub(text: str, page_url: str = "", page_title: str = "") -> bool:
    low = (text or "").lower()
    url_low = (page_url or "").lower()
    ttl_low = (page_title or "").lower()
    if "duckduckgo.com/?" in url_low or "google.com/search?" in url_low or "duckduckgo" in ttl_low:
        return True
    if len(low.strip()) < 450:
        return True
    wall_markers = (
        "microsoft cares about your privacy",
        "your privacy choices",
        "accept all cookies",
        "manage your privacy preferences",
        "we and our partners process data",
        "enable javascript to view this page",
    )
    serp_markers = ("all regions", "any time", "duckassist", "duckduckgo", "search results")
    if sum(1 for s in serp_markers if s in low) >= 2 and len(low) < 3500:
        return True
    hits = sum(1 for w in wall_markers if w in low)
    return hits >= 1 and len(low) < 2200


def _clean_copied_article(clip: str) -> str:
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
    return clean_clip


def cmd_web_copy(args):
    """Browse like a human: launch Firefox search, click a real article, scroll down visibly, and copy clean text via Ctrl+A/Ctrl+C."""
    query = args.query.strip()
    ensure_spacious_workspace(target_app="firefox", agent=args.agent)
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
            spa_stubs = ("gamedropradar", "release-date tracker", "countdown", "msn.com", "msn —", "msn:")
            for cand in candidates:
                raw_hits = _ocr_scan_once(cand, "firefox", "auto", min_y=230)
                non_ui = [
                    item for item in raw_hits
                    if len(item["text"].strip()) >= 18 and not any(j in item["text"].lower() for j in ui_junk)
                ]
                # Prefer rich article headlines lower down (skip DuckAssist summary + thin SPA/privacy-wall sites)
                rich = [item for item in non_ui if not any(s in item["text"].lower() for s in spa_stubs)]
                pool = rich or non_ui or raw_hits
                below_ia = [item for item in pool if item["y"] >= 310]
                hits = below_ia or pool
                if hits:
                    break
            if not hits:
                time.sleep(0.45)

        if not hits:
            print(json.dumps({"ok": False, "error": f"No article link found visually for '{query}'"}))
            sys.exit(1)

    target_articles = max(1, min(3, int(getattr(args, "articles", 1) or 1)))
    img_count_target = max(1, min(6, int(getattr(args, "image_count", 1) or 1)))
    save_img_base = Path(args.save_image).expanduser() if getattr(args, "save_image", "") else None

    def _visit_and_extract(hit_obj: dict, idx_slot: int) -> tuple[str, str, str, str]:
        with pointer_lock():
            hypr_focus("firefox")
            time.sleep(0.12)
            ax, ay = calibrated_move(hit_obj["x"], hit_obj["y"], f"Mở bài viết #{idx_slot + 1}", args.agent)
            notify_hud(ax, ay, "click", f"Click bài #{idx_slot + 1}", True, args.agent)
            run(["ydotool", "click", BUTTON_CODES["left"]])
        time.sleep(2.1)
        ttl_now = _firefox_title()
        if "duckduckgo" in ttl_now.lower() or ttl_now == search_title:
            return "", "", ttl_now, search_url
        with pointer_lock():
            hypr_focus("firefox")
            time.sleep(0.15)
            fc = find_client("firefox")
            cx = int(fc["at"][0] + fc["size"][0] / 2) if fc else w // 2
            cy = int(fc["at"][1] + fc["size"][1] / 2) if fc else h // 2
            calibrated_move(cx, cy, "Đọc & cuộn trang", args.agent)
            for _ in range(max(1, args.scrolls)):
                notify_hud(cx, cy, "scroll", "Cuộn trang đọc bài", False, args.agent)
                run(["ydotool", "mousemove", "-w", "-x", "0", "-y", "-5"])
                time.sleep(0.35)
            notify_hud(cx, cy, "click", "Chọn nội dung (Ctrl+A)", True, args.agent)
            run(["ydotool", "click", BUTTON_CODES["left"]])
            time.sleep(0.08)
            press_combo("ctrl+a")
            time.sleep(0.15)
            notify_hud(cx, cy, "key", "Sao chép (Ctrl+C)", False, args.agent)
            press_combo("ctrl+c")
            time.sleep(0.22)
        raw_c = run(["wl-paste", "--no-newline"]).stdout
        ttl_now = _firefox_title()
        img_f = ""
        page_url = ""
        with pointer_lock():
            press_combo("ctrl+l")
            time.sleep(0.08)
            press_combo("ctrl+c")
            time.sleep(0.1)
            press_combo("escape")
        page_url = run(["wl-paste", "--no-newline"]).stdout.strip()
        if save_img_base and page_url.startswith("http") and "duckduckgo.com/?" not in page_url:
            try:
                import urllib.request
                req = urllib.request.Request(page_url, headers={"User-Agent": "Mozilla/5.0"})
                html_txt = urllib.request.urlopen(req, timeout=4.5).read().decode("utf-8", errors="ignore")
                slot_p = save_img_base if idx_slot == 0 else save_img_base.with_name(f"{save_img_base.stem}_{idx_slot + 1}{save_img_base.suffix}")
                img_f = _extract_article_image_from_html(page_url, html_txt, slot_p, query)
            except Exception:
                img_f = ""
        return _clean_copied_article(raw_c), img_f, ttl_now, page_url

    collected_parts = []
    saved_imgs = []
    first_title = ""
    clicked_titles = []
    # Deduplicate candidate hits by y-coordinate (>= 40px apart) so we actually visit different links
    unique_hits = []
    for h_cand in hits:
        if all(abs(h_cand["y"] - uh["y"]) >= 36 for uh in unique_hits):
            unique_hits.append(h_cand)

    for idx_h, h_obj in enumerate(unique_hits[:4]):
        if idx_h > 0 and _firefox_title() != search_title:
            with pointer_lock():
                hypr_focus("firefox")
                time.sleep(0.1)
                press_combo("alt+Left")
            time.sleep(1.3)
        part_txt, part_img, part_ttl, part_url = _visit_and_extract(h_obj, len(saved_imgs))
        if part_img and part_img not in saved_imgs:
            saved_imgs.append(part_img)
        if _is_privacy_or_stub(part_txt, part_url, part_ttl):
            # Privacy wall, SERP self-copy, or empty SPA stub -> reject & keep trying next article!
            continue
        if not first_title:
            first_title = part_ttl
        clicked_titles.append(h_obj["text"])
        collected_parts.append(f"--- BÀI VIẾT {len(collected_parts) + 1} ({part_ttl}) ---\n{part_txt}")
        total_chars = sum(len(x) for x in collected_parts)
        if len(collected_parts) >= target_articles and total_chars >= 1600 and (not save_img_base or len(saved_imgs) >= img_count_target):
            break

    clean_clip = "\n\n".join(collected_parts)
    if save_img_base and len(saved_imgs) < img_count_target:
        img_q = getattr(args, "image_query", "") or query
        saved_imgs = _fetch_verified_ddg_images(img_q, save_img_base, count=img_count_target, existing=saved_imgs)

    if clean_clip:
        wl_copy_safe(clean_clip)
        Path("/tmp/ai_web_copied.txt").write_text(
            f"PAGE_TITLE: {first_title or _firefox_title()}\nMATCHED_LINKS: {'; '.join(clicked_titles)}\n\n{clean_clip}",
            encoding="utf-8",
        )

    if len(clean_clip.strip()) < 150:
        print(json.dumps({"ok": False, "blocked": "privacy_or_empty", "error": "Articles blocked by privacy modal or empty after fallback", "chars": len(clean_clip)}))
        sys.exit(1)

    print(json.dumps({
        "ok": True,
        "matched_link": "; ".join(clicked_titles) or hits[0]["text"],
        "page_title": first_title or _firefox_title(),
        "articles_collected": len(collected_parts),
        "changed_page": _firefox_title() != search_title,
        "chars": len(clean_clip),
        "raw_file": "/tmp/ai_web_copied.txt",
        "image_file": saved_imgs[0] if saved_imgs else "",
        "images": saved_imgs,
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
        imgs = [s.strip() for s in (getattr(args, "images", "") or "").split(",") if s.strip()]
        _build_docx_file(out_p, args.title or out_p.stem.replace("_", " "), clip, image_path=args.image or None, image_paths=imgs)
        saved_docx = str(out_p)

    if not app_name or not cmd:
        print(json.dumps({"ok": bool(saved_docx), "office_installed": False, "app": None, "docx": saved_docx}))
        return

    w, h, _ = get_monitor_info()
    ensure_spacious_workspace(target_app=app_name, agent=args.agent)
    notify_hud(w // 2, h // 2, "launch", f"Mở {app_name}", False, args.agent)
    launch_cmd = list(cmd)
    # If real Word processor (LibreOffice/OnlyOffice) AND docx was built, open that .docx directly or open blank & Ctrl+V
    if is_wp and saved_docx:
        launch_cmd.append(saved_docx)
    subprocess.Popen(launch_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)

    # Wait for the real document editor window (skip splash screens / Welcome dialogs; allow ~14s for Flatpak cold start)
    win = None
    is_lo = ("libreoffice" in app_name or app_name == "lowriter")
    deadline = time.time() + (14.0 if "flatpak" in app_name else 8.5)
    while time.time() < deadline:
        res_c = run(["hyprctl", "clients", "-j"])
        try:
            clients = json.loads(res_c.stdout)
            for c in clients:
                cls = str(c.get("class", "")).lower()
                ttl = str(c.get("title", "")).lower()
                sz = c.get("size") or [0, 0]
                matched = (
                    ("libreoffice" in cls or "soffice" in cls or "libreoffice" in ttl)
                    if is_lo
                    else (app_name.lower() in cls or app_name.lower() in ttl)
                )
                if sz[0] >= 750 and "welcome" not in ttl and matched:
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


def _corked_streams() -> list[str]:
    out = run(["pactl", "list", "sink-inputs"]).stdout
    active = []
    for blk in out.split("Sink Input #"):
        low = blk.lower()
        if "corked: no" in low:
            m = re.search(r'application\.name\s*=\s*"([^"]+)"', blk)
            active.append(m.group(1) if m else "audio")
    return active


def cmd_close_app(args):
    """Gracefully close Hyprland window(s) matching app class/title substring."""
    target = args.target.strip().lower()
    aliases = {
        "libreoffice": ["libreoffice", "soffice"],
        "writer": ["libreoffice", "soffice"],
        "word": ["libreoffice", "soffice"],
        "vscode": ["code"],
        "vs code": ["code"],
        "calculator": ["kcalc"],
        "files": ["dolphin", "thunar"],
        "terminal": ["konsole", "kitty", "foot"],
    }
    needles = aliases.get(target, [target])
    clients = json.loads(run(["hyprctl", "clients", "-j"]).stdout or "[]")
    matched = []
    for c in clients:
        cls = str(c.get("class") or "").lower()
        ttl = str(c.get("title") or "").lower()
        if cls == "foot" and "agy" in ttl and target != "foot":
            continue
        if any(n in cls or n in ttl for n in needles):
            matched.append(c)

    if not matched:
        print(json.dumps({"ok": True, "matched": 0, "closed": [], "remaining": []}, ensure_ascii=False))
        return

    closed = []
    for c in matched:
        cx = int(c["at"][0] + c["size"][0] / 2)
        cy = int(c["at"][1] + c["size"][1] / 2)
        notify_hud(cx, cy, "close", f"Đóng {c.get('class')}", False, args.agent)
        run(["hyprctl", "dispatch", "closewindow", f"address:{c['address']}"])
        closed.append(f"{c.get('class')}: {c.get('title', '')[:40]}")

    time.sleep(1.3)
    def _still_matching():
        rem_c = json.loads(run(["hyprctl", "clients", "-j"]).stdout or "[]")
        return [
            c for c in rem_c
            if any(n in str(c.get("class") or "").lower() or n in str(c.get("title") or "").lower() for n in needles)
            and not (str(c.get("class") or "").lower() == "foot" and "agy" in str(c.get("title") or "").lower() and target != "foot")
        ]

    rem_objs = _still_matching()
    if rem_objs and args.force:
        import signal
        if any(n in ("libreoffice", "soffice") for n in needles):
            run(["flatpak", "kill", "org.libreoffice.LibreOffice"])
        for c in rem_objs:
            pid = int(c.get("pid") or 0)
            if pid > 1 and pid not in (os.getpid(), os.getppid()):
                try:
                    os.kill(pid, signal.SIGTERM)
                except OSError:
                    pass
        time.sleep(0.7)
        rem_objs = _still_matching()
    remaining = [f"{c.get('class')}: {c.get('title', '')[:40]}" for c in rem_objs]
    print(json.dumps({"ok": len(remaining) == 0, "matched": len(matched), "closed": closed, "remaining": remaining}, ensure_ascii=False))


def cmd_fetch_images(args):
    """Download N verified topic artwork images via DDG i.js in one fast call."""
    out_p = Path(args.out).expanduser()
    imgs = _fetch_verified_ddg_images(args.query, out_p, count=max(1, min(8, int(args.count or 1))))
    print(json.dumps({"ok": len(imgs) >= 1, "count": len(imgs), "images": imgs}, ensure_ascii=False))


def cmd_stop_media(args):
    """Stop active video/music playback across MPRIS players and Firefox YouTube tabs, verified via PipeWire."""
    before = _corked_streams()
    run(["playerctl", "-a", "pause"])
    run(["playerctl", "-a", "stop"])
    time.sleep(0.4)
    if _corked_streams() or args.close_tab:
        if find_client("firefox") and any("firefox" in s.lower() for s in (before or _corked_streams())):
            with pointer_lock():
                hypr_focus("firefox")
                time.sleep(0.15)
                if args.close_tab:
                    notify_hud(960, 80, "close", "Đóng tab YouTube", False, args.agent)
                    press_combo("ctrl+w")
                else:
                    notify_hud(960, 540, "pause", "Dừng video YouTube", False, args.agent)
                    press_combo("k")
            time.sleep(0.55)
    after = _corked_streams()
    if after and any("vlc" in s.lower() or "mpv" in s.lower() for s in after):
        run(["pkill", "-x", "vlc"])
        run(["pkill", "-x", "mpv"])
        time.sleep(0.3)
        after = _corked_streams()
    print(json.dumps({"ok": len(after) == 0, "corked_before": before, "corked_after": after}, ensure_ascii=False))


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
    ytp.add_argument("--fullscreen", action="store_true", help="Press 'f' for full video after verified playback")
    ytp.add_argument("--screenshot", default="", help="Optional JPEG path to capture screenshot of playing video")
    add_agent_arg(ytp)
    ytp.set_defaults(func=cmd_yt_play)

    wdx = sub.add_parser("write-docx", help="Create a valid Word .docx document instantaneously with zero dependencies")
    wdx.add_argument("path")
    wdx.add_argument("--title", default="")
    wdx.add_argument("--text", default="")
    wdx.add_argument("--file", default="")
    wdx.add_argument("--image", default="", help="Optional hero image path to embed neatly below title")
    wdx.add_argument("--images", default="", help="Comma-separated image paths to embed")
    wdx.add_argument("--open", action="store_true")
    wdx.set_defaults(func=cmd_write_docx)

    wcp = sub.add_parser("web-copy", help="Browse visually in Firefox, click article link, scroll down, and copy text via Ctrl+A/Ctrl+C")
    wcp.add_argument("query")
    wcp.add_argument("--engine", choices=["ddg", "google"], default="ddg")
    wcp.add_argument("--scrolls", type=int, default=2)
    wcp.add_argument("--articles", type=int, default=1, help="Number of articles to read/merge cleanly (1..3)")
    wcp.add_argument("--save-image", default="", help="Optional path to save featured article og:image")
    wcp.add_argument("--image-count", type=int, default=1, help="Target count of verified artwork images to save")
    wcp.add_argument("--image-query", default="", help="Specific entity/game query for accurate fallback image search")
    add_agent_arg(wcp)
    wcp.set_defaults(func=cmd_web_copy)

    ofp = sub.add_parser("office-paste", help="Open compatible Office/Editor app on OS, visually paste clipboard via Ctrl+V, and optionally save .docx")
    ofp.add_argument("--docx", default="", help="Optional .docx output path under ~/Documents/")
    ofp.add_argument("--title", default="")
    ofp.add_argument("--source-file", default="")
    ofp.add_argument("--image", default="", help="Optional image path to embed neatly into .docx")
    ofp.add_argument("--images", default="", help="Comma-separated image paths to embed into .docx")
    add_agent_arg(ofp)
    ofp.set_defaults(func=cmd_office_paste)

    cap = sub.add_parser("close-app", help="Gracefully close window(s) matching app class/title")
    cap.add_argument("target", help="App class or title substring (e.g. kate, code, firefox, libreoffice, vlc, dolphin)")
    cap.add_argument("--force", action="store_true", help="Fallback kill if window refuses graceful close")
    add_agent_arg(cap)
    cap.set_defaults(func=cmd_close_app)

    smp = sub.add_parser("stop-media", help="Stop/pause active YouTube/VLC/audio playback and verify PipeWire silent")
    smp.add_argument("--close-tab", action="store_true", help="Also close active Firefox YouTube tab via Ctrl+W")
    add_agent_arg(smp)
    smp.set_defaults(func=cmd_stop_media)

    fip = sub.add_parser("fetch-images", help="Download N verified topic images via DDG i.js in one fast call")
    fip.add_argument("query", help="Image search keywords")
    fip.add_argument("--count", type=int, default=2, help="Number of images to download (1..8)")
    fip.add_argument("--out", default="/tmp/ai_img.jpg", help="Base output path")
    fip.set_defaults(func=cmd_fetch_images)

    ewp = sub.add_parser("ensure-workspace", help="Switch to an empty workspace if current workspace lacks readable space")
    ewp.add_argument("--app", default="", help="Optional target app name if already open on current workspace")
    ewp.add_argument("--min-w", type=int, default=820)
    ewp.add_argument("--min-h", type=int, default=480)
    ewp.add_argument("--max-windows", type=int, default=1)
    add_agent_arg(ewp)
    ewp.set_defaults(func=cmd_ensure_workspace)

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
