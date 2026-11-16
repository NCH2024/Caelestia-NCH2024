#!/usr/bin/env python3
"""
Caelestia Push-to-Talk & Neural Speech Helper (`caelestia_voice.py`)
Supports:
- One-shot Vietnamese/English Speech-to-Text (`listen-once` via faster-whisper + high-sensitivity AGC)
- Sentence-complete natural voice replies (`speak` via gTTS / edge-tts + espeak-ng offline fallback)
"""

import os
import sys
from pathlib import Path

_VENV_PY = Path.home() / ".local" / "share" / "caelestia" / "voice-venv" / "bin" / "python"
if _VENV_PY.exists() and Path(sys.executable).resolve() != _VENV_PY.resolve():
    os.execv(str(_VENV_PY), [str(_VENV_PY), __file__, *sys.argv[1:]])

import argparse
import asyncio
import json
import re
import shutil
import subprocess
import tempfile
import time

import numpy as np

_WHISPER_CMD = None


def ipc_voice_state(state: str, text: str = ""):
    try:
        subprocess.Popen(
            ["qs", "-c", "caelestia", "ipc", "call", "ai", "voiceEvent", state, text[:260]],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception:
        pass


def get_whisper_model(size: str = "base"):
    global _WHISPER_CMD
    from faster_whisper import WhisperModel
    if _WHISPER_CMD is None:
        _WHISPER_CMD = WhisperModel(size, device="cpu", compute_type="int8")
    return _WHISPER_CMD


def clean_ac_float(pcm_i16: np.ndarray) -> np.ndarray:
    if len(pcm_i16) == 0:
        return np.array([], dtype=np.float32)
    x = pcm_i16.astype(np.float32) / 32768.0
    return x - float(np.mean(x))


def ac_rms(pcm_i16: np.ndarray) -> float:
    x = clean_ac_float(pcm_i16)
    return float(np.sqrt(np.mean(x * x))) if len(x) else 0.0


def normalize_for_asr(pcm_i16: np.ndarray, target_rms: float = 0.14, max_gain: float = 28.0) -> np.ndarray:
    """Automatic Gain Control (AGC) for laptop DMICs."""
    x = clean_ac_float(pcm_i16)
    if len(x) == 0:
        return x
    rms = float(np.sqrt(np.mean(x * x)))
    if rms < 0.0012:
        return x
    gain = min(max_gain, max(1.0, target_rms / rms))
    return np.tanh(x * gain * 1.1).astype(np.float32)


def mic_stream_cmd(sr: int = 16000) -> list[str]:
    if shutil.which("ffmpeg"):
        return [
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-f", "pulse", "-i", "default",
            "-af", "highpass=f=85,lowpass=f=7600",
            "-ac", "1", "-ar", str(sr), "-f", "s16le", "-",
        ]
    return ["parec", "--raw", "--format=s16le", f"--rate={sr}", "--channels=1"]


def _clip_sentences(text: str, limit: int = 1400) -> str:
    if len(text) <= limit:
        return text
    sub = text[:limit]
    best = max(sub.rfind(". "), sub.rfind("! "), sub.rfind("? "), sub.rfind(".\n"))
    if best >= int(limit * 0.4):
        return sub[: best + 1].strip()
    sp = sub.rfind(" ")
    return (sub[:sp] if sp > 0 else sub).strip()


async def _edge_tts_async(text: str, voice: str, out_mp3: Path):
    import edge_tts
    comm = edge_tts.Communicate(text, voice)
    await comm.save(str(out_mp3))


def speak_text(text: str, voice: str = "vi-VN-HoaiMyNeural"):
    """Speak complete Vietnamese/English response cleanly via gTTS/edge-tts + ffplay (offline fallback: espeak-ng)."""
    clean = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text or "")
    clean = re.sub(r"https?://\S+|file://\S+", "", clean)
    clean = re.sub(r"[`*_#>\[\]\(\)•]+", " ", clean)
    clean = re.sub(r"\s+", " ", clean).strip()
    clean = _clip_sentences(clean, 1400)
    if not clean:
        return
    ipc_voice_state("speaking", clean)
    tts_lang = "en" if str(voice).lower().startswith("en") else "vi"
    with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as tf:
        mp3_path = Path(tf.name)
    try:
        synthesized = False
        try:
            asyncio.run(_edge_tts_async(clean, voice, mp3_path))
            synthesized = mp3_path.exists() and mp3_path.stat().st_size > 500
        except Exception:
            synthesized = False
        if not synthesized:
            try:
                from gtts import gTTS
                gTTS(clean, lang=tts_lang).save(str(mp3_path))
                synthesized = mp3_path.exists() and mp3_path.stat().st_size > 500
            except Exception:
                synthesized = False
        if synthesized:
            if shutil.which("ffplay"):
                subprocess.run(["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", str(mp3_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            elif shutil.which("pw-play"):
                wav_p = mp3_path.with_suffix(".wav")
                subprocess.run(["ffmpeg", "-y", "-i", str(mp3_path), str(wav_p)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                subprocess.run(["pw-play", str(wav_p)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                wav_p.unlink(missing_ok=True)
            return
    finally:
        mp3_path.unlink(missing_ok=True)
        ipc_voice_state("idle", "")
    if shutil.which("espeak-ng"):
        subprocess.run(["espeak-ng", "-v", tts_lang, clean], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def transcribe_pcm(pcm_i16: np.ndarray, model_size: str = "base", lang: str = "vi") -> str:
    if len(pcm_i16) < 3200:
        return ""
    model = get_whisper_model(model_size)
    audio_f32 = normalize_for_asr(pcm_i16)
    segs, _ = model.transcribe(
        audio_f32,
        language=lang,
        beam_size=1,
        vad_filter=True,
        vad_parameters={"min_silence_duration_ms": 450, "threshold": 0.30},
        condition_on_previous_text=False,
        no_speech_threshold=0.65,
        max_new_tokens=96,
    )
    kept = [s.text.strip() for s in segs if getattr(s, "no_speech_prob", 0.0) <= 0.72 and s.text.strip()]
    return " ".join(kept).strip()


def record_spoken_utterance(max_sec: float = 11.0, sr: int = 16000, vad_thr: float = 0.0040) -> tuple[np.ndarray, bool]:
    chunk_bytes = int(0.15 * sr * 2)
    proc = subprocess.Popen(mic_stream_cmd(sr), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    frames = []
    started = False
    speech_streak = 0
    silent_chunks = 0
    total_samples = 0
    try:
        while True:
            audio_sec = total_samples / float(sr)
            if audio_sec >= max_sec or (not started and audio_sec >= 6.0):
                break
            raw = proc.stdout.read(chunk_bytes)
            if not raw:
                break
            arr = np.frombuffer(raw[: len(raw) - (len(raw) % 2)], dtype=np.int16)
            if len(arr) == 0:
                continue
            frames.append(arr)
            total_samples += len(arr)
            rms = ac_rms(arr)
            if rms > vad_thr:
                speech_streak += 1
                silent_chunks = 0
                if speech_streak >= 2:
                    started = True
            else:
                speech_streak = 0
                if started:
                    silent_chunks += 1
                    if (total_samples / float(sr)) >= 2.8 and silent_chunks >= 11:
                        break
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=1.0)
        except Exception:
            proc.kill()
    return (np.concatenate(frames) if frames else np.array([], dtype=np.int16)), started


def cmd_listen_once(args):
    """Capture one voice command on demand (Push-to-Talk) and dispatch to Meow AI."""
    ipc_voice_state("listening", "Đang nghe lệnh giọng nói...")
    pcm, had_speech = record_spoken_utterance(max_sec=11.0)
    if not had_speech:
        ipc_voice_state("error", "Chưa nghe thấy lệnh — vui lòng thử lại")
        time.sleep(1.4)
        ipc_voice_state("idle", "")
        print(json.dumps({"ok": False, "error": "No speech detected"}))
        sys.exit(1)
    ipc_voice_state("thinking", "Đang nhận diện giọng nói...")
    txt = transcribe_pcm(pcm, model_size=args.model, lang=args.lang)
    if not txt:
        ipc_voice_state("error", "Không nghe rõ lệnh — vui lòng thử lại")
        time.sleep(1.5)
        ipc_voice_state("idle", "")
        print(json.dumps({"ok": False, "error": "No speech recognized"}))
        sys.exit(1)
    ipc_voice_state("thinking", f"Đã nghe: «{txt[:72]}»")
    if args.dispatch:
        subprocess.Popen(
            ["qs", "-c", "caelestia", "ipc", "call", "ai", "runVoiceTask", txt],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    print(json.dumps({"ok": True, "text": txt}, ensure_ascii=False))


def main():
    p = argparse.ArgumentParser(description="Caelestia Push-to-Talk & Voice Reply Helper")
    sub = p.add_subparsers(dest="sub", required=True)

    lo = sub.add_parser("listen-once", help="Capture 1 spoken command now and dispatch to AI")
    lo.add_argument("--model", default="base", choices=["tiny", "base", "small"])
    lo.add_argument("--lang", default="vi")
    lo.add_argument("--dispatch", action="store_true")
    lo.set_defaults(func=cmd_listen_once)

    sp = sub.add_parser("speak", help="Speak Vietnamese/English text via TTS")
    sp.add_argument("text")
    sp.add_argument("--voice", default="vi-VN-HoaiMyNeural")
    sp.set_defaults(func=lambda a: speak_text(a.text, a.voice))

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
