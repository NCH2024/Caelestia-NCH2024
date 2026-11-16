#!/usr/bin/env python3
"""
Caelestia Voice Assistant (`caelestia_voice.py`)
Supports:
- Personal wake-word voice training ("Mi Mi" / "Hey Mi Mi" / "Hello Mi Mi") via 24-band Mel voiceprint + faster-whisper
- Continuous PipeWire mic listening daemon (<2% CPU idle via RMS VAD gate)
- Vietnamese Speech-to-Text (`faster-whisper`) -> dispatches directly to Meow AI (`qs -c caelestia ipc call ai runVoiceTask`)
- Natural Vietnamese neural voice reply (`edge-tts` `vi-VN-HoaiMyNeural` + offline `espeak-ng` fallback)
"""

import sys
from pathlib import Path

_VENV_PY = Path.home() / ".local" / "share" / "caelestia" / "voice-venv" / "bin" / "python"
if _VENV_PY.exists() and Path(sys.executable).resolve() != _VENV_PY.resolve():
    import os as _os
    _os.execv(str(_VENV_PY), [str(_VENV_PY), __file__, *sys.argv[1:]])

import argparse
import asyncio
import json
import os
import re
import shutil
import signal
import subprocess
import tempfile
import time
import wave

import numpy as np

DATA_DIR = Path.home() / ".local" / "share" / "caelestia" / "ai"
PROFILE_PATH = DATA_DIR / "voice_profile.json"
DEFAULT_WAKE_PHRASES = ["mi mi", "mimi", "hey mi mi", "hey mimi", "hello mi mi", "hello mimi", "my my", "me me"]
WAKE_REGEX = re.compile(r"\b(h(?:e|a)y\s+mi\s*mi|hello\s+mi\s*mi|mi\s*mi|mimi|m[ií]\s*m[ií]|my\s*my|me\s*me)\b", re.IGNORECASE)

_WHISPER_TINY = None
_WHISPER_CMD = None


def ipc_voice_state(state: str, text: str = ""):
    try:
        subprocess.Popen(
            ["qs", "-c", "caelestia", "ipc", "call", "ai", "voiceEvent", state, text[:180]],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception:
        pass


def get_whisper_model(size: str = "base"):
    global _WHISPER_TINY, _WHISPER_CMD
    from faster_whisper import WhisperModel
    if size == "tiny":
        if _WHISPER_TINY is None:
            _WHISPER_TINY = WhisperModel("tiny", device="cpu", compute_type="int8")
        return _WHISPER_TINY
    if _WHISPER_CMD is None:
        _WHISPER_CMD = WhisperModel(size, device="cpu", compute_type="int8")
    return _WHISPER_CMD


def compute_mel_voiceprint(pcm_i16: np.ndarray, sr: int = 16000) -> list[float]:
    """Compute lightweight 24-band spectral voiceprint vector (no heavy PyTorch dependency)."""
    if len(pcm_i16) < 400:
        return [0.0] * 24
    x = pcm_i16.astype(np.float32) / 32768.0
    # Keep voiced frames above 15% of peak RMS
    frame_len = 400
    hop = 160
    specs = []
    win = np.hanning(frame_len)
    freqs = np.fft.rfftfreq(frame_len, 1.0 / sr)
    edges = np.linspace(120, 4200, 25)
    for start in range(0, len(x) - frame_len, hop):
        fr = x[start:start + frame_len]
        if np.sqrt(np.mean(fr * fr)) < 0.008:
            continue
        mag = np.abs(np.fft.rfft(fr * win)) ** 2
        band_e = []
        for b in range(24):
            mask = (freqs >= edges[b]) & (freqs < edges[b + 1])
            band_e.append(float(np.log1p(np.mean(mag[mask]) if np.any(mask) else 0.0)))
        specs.append(band_e)
    if not specs:
        return [0.0] * 24
    vec = np.mean(np.array(specs), axis=0)
    norm = float(np.linalg.norm(vec))
    return (vec / norm).tolist() if norm > 1e-6 else [0.0] * 24


def cosine_sim(a: list[float], b: list[float]) -> float:
    va = np.array(a, dtype=np.float32)
    vb = np.array(b, dtype=np.float32)
    na, nb = np.linalg.norm(va), np.linalg.norm(vb)
    if na < 1e-6 or nb < 1e-6:
        return 0.0
    return float(np.dot(va, vb) / (na * nb))


def record_pcm_chunk(seconds: float, sr: int = 16000) -> np.ndarray:
    """Capture mono 16kHz PCM audio cleanly from PipeWire mic via ffmpeg/pw-record."""
    n_bytes = int(seconds * sr * 2)
    if shutil.which("pw-record"):
        proc = subprocess.Popen(
            ["pw-record", "--format=s16", f"--rate={sr}", "--channels=1", "-"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        try:
            raw = proc.stdout.read(n_bytes)
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=1.0)
            except Exception:
                proc.kill()
        # Skip 44-byte WAV header if pw-record outputs RIFF header on stdout
        if raw.startswith(b"RIFF") and len(raw) > 44:
            raw = raw[44:]
        return np.frombuffer(raw[: len(raw) - (len(raw) % 2)], dtype=np.int16)
    proc = subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "pulse", "-i", "default", "-t", str(seconds), "-ac", "1", "-ar", str(sr), "-f", "s16le", "-"],
        capture_output=True,
    )
    return np.frombuffer(proc.stdout, dtype=np.int16)


def save_wav(path: Path, pcm_i16: np.ndarray, sr: int = 16000):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(pcm_i16.tobytes())


def load_profile() -> dict:
    try:
        if PROFILE_PATH.exists():
            return json.loads(PROFILE_PATH.read_text(encoding="utf-8"))
    except Exception:
        pass
    return {"samples": [], "threshold": 0.72, "phrases": DEFAULT_WAKE_PHRASES}


def save_profile(prof: dict):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    PROFILE_PATH.write_text(json.dumps(prof, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def play_chime():
    """Soft crisp 2-tone acknowledgement chime using pure numpy + pw-play/ffplay."""
    sr = 24000
    t1 = np.linspace(0, 0.09, int(sr * 0.09), False)
    t2 = np.linspace(0, 0.13, int(sr * 0.13), False)
    env1 = np.sin(np.pi * t1 / 0.09)
    env2 = np.sin(np.pi * t2 / 0.13)
    w1 = 0.25 * env1 * np.sin(2 * np.pi * 660 * t1)
    w2 = 0.28 * env2 * np.sin(2 * np.pi * 880 * t2)
    pcm = (np.concatenate([w1, w2]) * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
        p = Path(tf.name)
    save_wav(p, pcm, sr=sr)
    player = "pw-play" if shutil.which("pw-play") else "ffplay"
    cmd = [player, str(p)] if player == "pw-play" else [player, "-nodisp", "-autoexit", "-loglevel", "quiet", str(p)]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    p.unlink(missing_ok=True)


async def _edge_tts_async(text: str, voice: str, out_mp3: Path):
    import edge_tts
    comm = edge_tts.Communicate(text, voice)
    await comm.save(str(out_mp3))


def speak_text(text: str, voice: str = "vi-VN-HoaiMyNeural"):
    """Speak concise Vietnamese/English response cleanly via gTTS/edge-tts + ffplay (offline fallback: espeak-ng)."""
    clean = re.sub(r"[`*_#>\[\]\(\)]+", " ", text or "")
    clean = re.sub(r"https?://\S+|file://\S+", "", clean)
    clean = re.sub(r"\s+", " ", clean).strip()[:450]
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
    if shutil.which("espeak-ng"):
        subprocess.run(["espeak-ng", "-v", tts_lang, clean], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def transcribe_pcm(pcm_i16: np.ndarray, model_size: str = "base", lang: str = "vi") -> str:
    if len(pcm_i16) < 3200:
        return ""
    model = get_whisper_model(model_size)
    audio_f32 = pcm_i16.astype(np.float32) / 32768.0
    segs, _ = model.transcribe(audio_f32, language=lang, beam_size=1, vad_filter=True)
    return " ".join(s.text.strip() for s in segs).strip()


def cmd_train(args):
    """Record user's own voice saying 'Mi Mi' / 'Hey Mi Mi' to build personal wake voiceprint."""
    play_chime()
    pcm = record_pcm_chunk(2.4)
    rms = float(np.sqrt(np.mean((pcm.astype(np.float32) / 32768.0) ** 2))) if len(pcm) else 0.0
    if rms < 0.005:
        print(json.dumps({"ok": False, "error": "Microphone audio too quiet; please speak 'Mi Mi' closer to mic."}))
        sys.exit(1)
    vp = compute_mel_voiceprint(pcm)
    prof = load_profile()
    samples = prof.setdefault("samples", [])
    samples.append({"ts": int(time.time()), "rms": round(rms, 4), "vec": vp})
    prof["samples"] = samples[-5:]
    save_profile(prof)
    print(json.dumps({"ok": True, "samples": len(prof["samples"]), "rms": round(rms, 4)}))


def cmd_listen_once(args):
    """Capture one voice command immediately (without waiting for wake word) and dispatch to Meow AI."""
    play_chime()
    ipc_voice_state("listening", "Đang nghe lệnh giọng nói...")
    pcm = record_spoken_utterance(max_sec=9.0)
    ipc_voice_state("thinking", "Đang nhận diện giọng nói...")
    txt = transcribe_pcm(pcm, model_size=args.model, lang=args.lang)
    # Strip leading wake phrase if included cleanly
    txt = WAKE_REGEX.sub("", txt).strip(" ,.!?")
    if not txt:
        ipc_voice_state("idle", "")
        print(json.dumps({"ok": False, "error": "No speech recognized"}))
        sys.exit(1)
    ipc_voice_state("idle", txt)
    if args.dispatch:
        subprocess.Popen(
            ["qs", "-c", "caelestia", "ipc", "call", "ai", "runVoiceTask", txt],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    print(json.dumps({"ok": True, "text": txt}, ensure_ascii=False))


def record_spoken_utterance(max_sec: float = 9.0, sr: int = 16000) -> np.ndarray:
    """Stream PipeWire mic until 1.2s trailing silence after speech starts."""
    chunk_bytes = int(0.2 * sr * 2)  # 200ms frames
    cmd = ["pw-record", "--format=s16", f"--rate={sr}", "--channels=1", "-"] if shutil.which("pw-record") else [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "pulse", "-i", "default", "-ac", "1", "-ar", str(sr), "-f", "s16le", "-"
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    frames = []
    started = False
    silent_chunks = 0
    header_skipped = not shutil.which("pw-record")
    t0 = time.time()
    try:
        while (time.time() - t0) < max_sec:
            raw = proc.stdout.read(chunk_bytes)
            if not raw:
                break
            if not header_skipped and raw.startswith(b"RIFF"):
                raw = raw[44:]
                header_skipped = True
            header_skipped = True
            arr = np.frombuffer(raw[: len(raw) - (len(raw) % 2)], dtype=np.int16)
            if len(arr) == 0:
                continue
            rms = float(np.sqrt(np.mean((arr.astype(np.float32) / 32768.0) ** 2)))
            frames.append(arr)
            if rms > 0.016:
                started = True
                silent_chunks = 0
            elif started:
                silent_chunks += 1
                if silent_chunks >= 6:  # 1.2s silence -> finished speaking!
                    break
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=1.0)
        except Exception:
            proc.kill()
    return np.concatenate(frames) if frames else np.array([], dtype=np.int16)


def cmd_daemon(args):
    """Always-on low-CPU PipeWire listener waiting for 'Mi Mi / Hey Mi Mi / Hello Mi Mi'."""
    running = True

    def stop_handler(*_):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop_handler)
    signal.signal(signal.SIGINT, stop_handler)

    sr = 16000
    chunk_bytes = int(0.25 * sr * 2)
    cmd = ["pw-record", "--format=s16", f"--rate={sr}", "--channels=1", "-"] if shutil.which("pw-record") else [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "pulse", "-i", "default", "-ac", "1", "-ar", str(sr), "-f", "s16le", "-"
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    ring = []
    header_skipped = not shutil.which("pw-record")
    cooldown_until = 0.0
    ipc_voice_state("ready", "Mi Mi sẵn sàng")

    try:
        while running:
            raw = proc.stdout.read(chunk_bytes)
            if not raw:
                time.sleep(0.2)
                continue
            if not header_skipped and raw.startswith(b"RIFF"):
                raw = raw[44:]
            header_skipped = True
            arr = np.frombuffer(raw[: len(raw) - (len(raw) % 2)], dtype=np.int16)
            if len(arr) == 0:
                continue
            ring.append(arr)
            if len(ring) > 8:  # ~2.0s rolling window
                ring.pop(0)
            rms = float(np.sqrt(np.mean((arr.astype(np.float32) / 32768.0) ** 2)))
            if rms < 0.018 or time.time() < cooldown_until or len(ring) < 4:
                continue

            window_pcm = np.concatenate(ring[-7:])
            prof = load_profile()
            samples = prof.get("samples") or []
            if samples:
                vp = compute_mel_voiceprint(window_pcm)
                best_sim = max(cosine_sim(vp, s["vec"]) for s in samples if s.get("vec"))
                if best_sim < float(prof.get("threshold", 0.72)):
                    continue

            phrase = transcribe_pcm(window_pcm, model_size="tiny", lang="en")
            if not WAKE_REGEX.search(phrase):
                # Retry Vietnamese tiny pass if accent triggered slightly differently
                phrase_vi = transcribe_pcm(window_pcm, model_size="tiny", lang="vi")
                if not WAKE_REGEX.search(phrase_vi):
                    continue

            # Wake word detected! Pause mic stream cleanly, capture full Vietnamese command!
            proc.terminate()
            try:
                proc.wait(timeout=1.0)
            except Exception:
                proc.kill()
            ring.clear()
            play_chime()
            ipc_voice_state("listening", "Mi Mi đang nghe...")
            cmd_pcm = record_spoken_utterance(max_sec=9.5)
            ipc_voice_state("thinking", "Đang hiểu lệnh...")
            spoken = transcribe_pcm(cmd_pcm, model_size=args.model, lang=args.lang)
            spoken = WAKE_REGEX.sub("", spoken).strip(" ,.!?")
            if spoken:
                ipc_voice_state("idle", spoken)
                subprocess.Popen(
                    ["qs", "-c", "caelestia", "ipc", "call", "ai", "runVoiceTask", spoken],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
            else:
                ipc_voice_state("idle", "")
            cooldown_until = time.time() + 2.5
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            header_skipped = not shutil.which("pw-record")
    finally:
        proc.terminate()
        ipc_voice_state("off", "")


def main():
    p = argparse.ArgumentParser(description="Caelestia Meow AI Voice Assistant (Mi Mi)")
    sub = p.add_subparsers(dest="sub", required=True)

    tr = sub.add_parser("train", help="Record a personal 'Mi Mi' wake-word sample")
    tr.set_defaults(func=cmd_train)

    lo = sub.add_parser("listen-once", help="Capture 1 spoken Vietnamese command now and dispatch to AI")
    lo.add_argument("--model", default="base", choices=["tiny", "base", "small"])
    lo.add_argument("--lang", default="vi")
    lo.add_argument("--dispatch", action="store_true")
    lo.set_defaults(func=cmd_listen_once)

    dm = sub.add_parser("daemon", help="Always-on 'Mi Mi / Hey Mi Mi / Hello Mi Mi' wake-word daemon")
    dm.add_argument("--model", default="base", choices=["tiny", "base", "small"])
    dm.add_argument("--lang", default="vi")
    dm.set_defaults(func=cmd_daemon)

    sp = sub.add_parser("speak", help="Speak Vietnamese/English text via neural TTS")
    sp.add_argument("text")
    sp.add_argument("--voice", default="vi-VN-HoaiMyNeural")
    sp.set_defaults(func=lambda a: speak_text(a.text, a.voice))

    st = sub.add_parser("status", help="Show voice profile & trained sample count")
    st.set_defaults(func=lambda a: print(json.dumps({
        "samples": len(load_profile().get("samples", [])),
        "threshold": load_profile().get("threshold", 0.72),
        "profile_path": str(PROFILE_PATH),
    })))

    cl = sub.add_parser("clear-profile", help="Clear recorded personal voiceprint samples")
    cl.set_defaults(func=lambda a: (PROFILE_PATH.unlink(missing_ok=True), print(json.dumps({"ok": True}))))

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
