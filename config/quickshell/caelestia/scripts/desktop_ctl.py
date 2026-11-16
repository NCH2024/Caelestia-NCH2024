#!/usr/bin/env python3
"""
Caelestia Desktop Control Utility (`caelestia-desktop`)
Reliable Wayland/Hyprland GUI automation bridge for AI agents:
- Screen capture with optional calibrated pixel coordinate grid (`grim` + `PIL`)
- Hyprland window inspection & focusing (supports both Lua `hl.dsp` & standard dispatchers)
- Closed-loop calibrated pointer control (`ydotool` + `hyprctl cursorpos`)
- Full UTF-8 / Vietnamese typing via clipboard paste (`wl-copy` + `Ctrl+V`)
- Clean hotkey combos using Linux evdev keycodes
- Fast on-screen OCR (`tesseract`)
"""

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

# Linux input-event-codes.h keycodes for ydotool key
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


def calibrated_move(tx: int, ty: int):
    """Closed-loop move so pointer lands cleanly within a few pixels of logical (tx, ty)."""
    ensure_ydotool()
    w, h, _ = get_monitor_info()
    tx = max(0, min(w - 1, int(tx)))
    ty = max(0, min(h - 1, int(ty)))

    # Initial move using calibrated 0.5 factor observed on Wayland ydotool 1.0
    scale_x, scale_y = 0.5, 0.5
    run(["ydotool", "mousemove", "--absolute", "-x", str(round(tx * scale_x)), "-y", str(round(ty * scale_y))])
    time.sleep(0.08)
    ax, ay = get_cursor_pos()
    if ax < 0 or (abs(ax - tx) <= 4 and abs(ay - ty) <= 4):
        return ax, ay

    # Adjust dynamically using measured ratio if different from 0.5
    if ax > 20 and tx > 20:
        scale_x = scale_x * (tx / ax)
    if ay > 20 and ty > 20:
        scale_y = scale_y * (ty / ay)
    run(["ydotool", "mousemove", "--absolute", "-x", str(round(tx * scale_x)), "-y", str(round(ty * scale_y))])
    time.sleep(0.08)
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


def draw_grid(img_path: str):
    im = Image.open(img_path).convert("RGBA")
    overlay = Image.new("RGBA", im.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    w, h = im.size
    font = ImageFont.load_default()

    # Major 200px lines & labels, minor 100px dashed hints
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
    out.save(img_path)


def hypr_focus(target: str) -> bool:
    """Focus window matching address/title/class safely across Lua & vanilla Hyprland."""
    res = run(["hyprctl", "clients", "-j"])
    try:
        clients = json.loads(res.stdout)
    except Exception:
        return False

    low = target.lower()
    match = None
    for c in clients:
        if c.get("address", "").lower() == low:
            match = c
            break
    if not match:
        for c in clients:
            if low in c.get("class", "").lower() or low in c.get("title", "").lower():
                match = c
                break
    if not match:
        return False

    addr = match["address"]
    # Try Lua hyprctl dispatcher first, fallback to standard dispatch
    r = run(["hyprctl", "dispatch", f'hl.dsp.window.focus({{ window = "address:{addr}" }})'])
    if r.returncode != 0:
        r = run(["hyprctl", "dispatch", "focuswindow", f"address:{addr}"])
    return r.returncode == 0


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
        draw_grid(out)
    w, h, scale = get_monitor_info()
    cx, cy = get_cursor_pos()
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
    ok = hypr_focus(args.target)
    print(json.dumps({"ok": ok, "target": args.target}))
    if not ok:
        sys.exit(1)


def cmd_launch(args):
    cmd = args.cmd
    subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    print(json.dumps({"ok": True, "launched": cmd}))


def cmd_move(args):
    ax, ay = calibrated_move(args.x, args.y)
    print(json.dumps({"ok": True, "target": [args.x, args.y], "actual": [ax, ay]}))


def cmd_click(args):
    ax, ay = calibrated_move(args.x, args.y)
    code = BUTTON_CODES[args.button]
    if args.double:
        run(["ydotool", "click", "--repeat", "2", "--next-delay", "60", code])
    else:
        run(["ydotool", "click", code])
    print(json.dumps({"ok": True, "button": args.button, "double": args.double, "at": [ax, ay]}))


def cmd_scroll(args):
    if args.x is not None and args.y is not None:
        calibrated_move(args.x, args.y)
    run(["ydotool", "mousemove", "-w", "-x", "0", "-y", str(args.delta)])
    print(json.dumps({"ok": True, "delta": args.delta}))


def cmd_type(args):
    ensure_ydotool()
    text = args.text
    is_ascii = all(32 <= ord(ch) <= 126 for ch in text)
    if is_ascii and len(text) <= 80 and not args.paste:
        run(["ydotool", "type", "--key-delay", "8", text])
        method = "ydotool"
    else:
        # Reliable Unicode/Vietnamese input via clipboard paste
        subprocess.run(["wl-copy", "--", text], check=True)
        time.sleep(0.08)
        press_combo("ctrl+v")
        method = "clipboard_paste"
    if args.enter:
        time.sleep(0.05)
        press_combo("enter")
    print(json.dumps({"ok": True, "method": method, "length": len(text)}))


def cmd_key(args):
    press_combo(args.combo)
    print(json.dumps({"ok": True, "combo": args.combo}))


def cmd_ocr(args):
    tmp = "/tmp/ai_ocr_cap.png"
    cmd = ["grim"]
    if args.region:
        cmd.extend(["-g", args.region])
    cmd.append(tmp)
    run(cmd)
    lang = args.lang or "eng"
    res = run(["tesseract", tmp, "stdout", "-l", lang, "--psm", "6"])
    print(res.stdout.strip())


def main():
    p = argparse.ArgumentParser(description="Caelestia Desktop Control Helper")
    sub = p.add_subparsers(dest="sub", required=True)

    sp = sub.add_parser("screen", help="Capture screen (optionally with pixel coordinate grid)")
    sp.add_argument("--grid", action="store_true")
    sp.add_argument("--region", help="Optional region 'x,y wxh'")
    sp.add_argument("--out", default="/tmp/ai_screen.png")
    sp.set_defaults(func=cmd_screen)

    wp = sub.add_parser("windows", help="List Hyprland windows & geometry")
    wp.set_defaults(func=cmd_windows)

    fp = sub.add_parser("focus", help="Focus window by title substring, class, or address")
    fp.add_argument("target")
    fp.set_defaults(func=cmd_focus)

    lp = sub.add_parser("launch", help="Launch GUI application in background")
    lp.add_argument("cmd", nargs=argparse.REMAINDER)
    lp.set_defaults(func=cmd_launch)

    mp = sub.add_parser("move", help="Move cursor accurately to screen (x, y)")
    mp.add_argument("x", type=int)
    mp.add_argument("y", type=int)
    mp.set_defaults(func=cmd_move)

    cp = sub.add_parser("click", help="Click accurately at screen (x, y)")
    cp.add_argument("x", type=int)
    cp.add_argument("y", type=int)
    cp.add_argument("--button", choices=["left", "right", "middle"], default="left")
    cp.add_argument("--double", action="store_true")
    cp.set_defaults(func=cmd_click)

    scp = sub.add_parser("scroll", help="Scroll mouse wheel")
    scp.add_argument("delta", type=int, help="Negative=down, Positive=up")
    scp.add_argument("--x", type=int)
    scp.add_argument("--y", type=int)
    scp.set_defaults(func=cmd_scroll)

    tp = sub.add_parser("type", help="Type text (supports Vietnamese/Unicode automatically via Ctrl+V)")
    tp.add_argument("text")
    tp.add_argument("--enter", action="store_true")
    tp.add_argument("--paste", action="store_true")
    tp.set_defaults(func=cmd_type)

    kp = sub.add_parser("key", help="Press key combo e.g. ctrl+l, ctrl+t, alt+tab, enter")
    kp.add_argument("combo")
    kp.set_defaults(func=cmd_key)

    op = sub.add_parser("ocr", help="Run tesseract OCR on current screen or region")
    op.add_argument("--region")
    op.add_argument("--lang", default="eng")
    op.set_defaults(func=cmd_ocr)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
