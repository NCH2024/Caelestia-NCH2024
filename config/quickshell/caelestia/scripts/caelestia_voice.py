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
import unicodedata
import wave

import numpy as np

DATA_DIR = Path.home() / ".local" / "share" / "caelestia" / "ai"
PROFILE_PATH = DATA_DIR / "voice_profile.json"
PROFILE_VERSION = 2
DEFAULT_THRESHOLD = 0.62
DEFAULT_WAKE_PHRASES = ["mi mi", "mimi", "hey mi mi", "hey mimi", "hello mi mi", "hello mimi", "my my", "me me"]
WAKE_REGEX = re.compile(
    r"\b(?:h(?:e|a)y\s+|hello\s+|hi\s+)?(?:mi[\s-]*mi|mimi|me[\s-]*me|my[\s-]*my|mew[\s-]*mew)\b|"
    r"\b(?:h(?:e|a)y|hello)\s+mini\b",
    re.IGNORECASE,
)


def strip_accents(text: str) -> str:
    nfd = unicodedata.normalize("NFD", text or "")
    return "".join(ch for ch in nfd if unicodedata.category(ch) != "Mn")


def matches_wake(text: str) -> bool:
    plain = strip_accents(text).lower().strip()
    return bool(WAKE_REGEX.search(plain))


def strip_wake_prefix(text: str) -> str:
    raw = (text or "").strip()
    # Remove leading wake tokens even when Vietnamese accents are present
    tokens = raw.split()
    while tokens and len(tokens) >= 2 and matches_wake(" ".join(tokens[:2])):
        tokens = tokens[2:]
        break
    if len(tokens) >= 3 and matches_wake(" ".join(tokens[:3])):
        tokens = tokens[3:]
    elif len(tokens) >= 1 and strip_accents(tokens[0]).lower().strip(",.!?") == "mimi":
        tokens = tokens[1:]
    return " ".join(tokens).strip(" ,.!?-")


def clean_ac_float(pcm_i16: np.ndarray) -> np.ndarray:
    if len(pcm_i16) == 0:
        return np.array([], dtype=np.float32)
    x = pcm_i16.astype(np.float32) / 32768.0
    return x - float(np.mean(x))


def ac_rms(pcm_i16: np.ndarray) -> float:
    x = clean_ac_float(pcm_i16)
    return float(np.sqrt(np.mean(x * x))) if len(x) else 0.0


def mic_stream_cmd(sr: int = 16000) -> list[str]:
    """Use ffmpeg pulse + 85Hz highpass (eliminates PipeWire raw DMIC s32 DC jitter); fallback parec --raw."""
    if shutil.which("ffmpeg"):
        return [
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-f", "pulse", "-i", "default",
            "-af", "highpass=f=85",
            "-ac", "1", "-ar", str(sr), "-f", "s16le", "-",
        ]
    return ["parec", "--raw", "--format=s16le", f"--rate={sr}", "--channels=1"]

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
    """Compute lightweight 24-band spectral voiceprint vector (DC-removed AC waveform)."""
    if len(pcm_i16) < 400:
        return [0.0] * 24
    x = clean_ac_float(pcm_i16)
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
    """Capture mono 16kHz PCM audio cleanly from Pulse/PipeWire mic via high-passed stream."""
    n_bytes = int(seconds * sr * 2)
    proc = subprocess.Popen(mic_stream_cmd(sr), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    chunks = []
    got = 0
    try:
        while got < n_bytes:
            part = proc.stdout.read(min(6400, n_bytes - got))
            if not part:
                break
            chunks.append(part)
            got += len(part)
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=1.0)
        except Exception:
            proc.kill()
    raw = b"".join(chunks)
    return np.frombuffer(raw[: len(raw) - (len(raw) % 2)], dtype=np.int16)


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
            d = json.loads(PROFILE_PATH.read_text(encoding="utf-8"))
            # Invalidate corrupt v1 noise samples (recorded before DC-offset/raw PCM fix)
            if int(d.get("version", 1)) != PROFILE_VERSION:
                clean = {"version": PROFILE_VERSION, "samples": [], "threshold": DEFAULT_THRESHOLD, "phrases": DEFAULT_WAKE_PHRASES}
                save_profile(clean)
                return clean
            d["samples"] = [s for s in (d.get("samples") or []) if float(s.get("rms", 0)) < 0.35 and s.get("vec")]
            d.setdefault("threshold", DEFAULT_THRESHOLD)
            return d
    except Exception:
        pass
    return {"version": PROFILE_VERSION, "samples": [], "threshold": DEFAULT_THRESHOLD, "phrases": DEFAULT_WAKE_PHRASES}


def save_profile(prof: dict):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    prof["version"] = PROFILE_VERSION
    PROFILE_PATH.write_text(json.dumps(prof, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def play_chime(async_play: bool = False):
    """Crisp 2-tone acknowledgement chime; async_play=True starts recording immediately after wake."""
    sr = 24000
    t1 = np.linspace(0, 0.08, int(sr * 0.08), False)
    t2 = np.linspace(0, 0.12, int(sr * 0.12), False)
    env1 = np.sin(np.pi * t1 / 0.08)
    env2 = np.sin(np.pi * t2 / 0.12)
    w1 = 0.28 * env1 * np.sin(2 * np.pi * 660 * t1)
    w2 = 0.32 * env2 * np.sin(2 * np.pi * 990 * t2)
    pcm = (np.concatenate([w1, w2]) * 32767).astype(np.int16)
    p = Path("/tmp/caelestia_wake_chime.wav")
    save_wav(p, pcm, sr=sr)
    if shutil.which("ffplay"):
        cmd = ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", str(p)]
    else:
        cmd = ["pw-play", str(p)]
    if async_play:
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


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
    audio_f32 = clean_ac_float(pcm_i16)
    segs, _ = model.transcribe(audio_f32, language=lang, beam_size=1, vad_filter=True)
    return " ".join(s.text.strip() for s in segs).strip()


def cmd_train(args):
    """Record user's own voice saying 'Mi Mi' / 'Hey Mi Mi' to build personal wake voiceprint."""
    play_chime(async_play=False)
    time.sleep(0.15)
    pcm = record_pcm_chunk(2.4)
    rms = ac_rms(pcm)
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
    play_chime(async_play=True)
    ipc_voice_state("listening", "Mi Mi đang nghe lệnh...")
    pcm = record_spoken_utterance(max_sec=8.5)
    ipc_voice_state("thinking", "Đang nhận diện giọng nói...")
    txt = strip_wake_prefix(transcribe_pcm(pcm, model_size=args.model, lang=args.lang))
    if not txt:
        ipc_voice_state("error", "Không nghe rõ lệnh — vui lòng thử lại")
        time.sleep(1.6)
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


def record_spoken_utterance(max_sec: float = 8.5, sr: int = 16000, vad_thr: float = 0.018) -> np.ndarray:
    """Stream clean high-passed mic audio until 1.1s trailing silence after speech starts."""
    chunk_bytes = int(0.18 * sr * 2)  # 180ms frames
    proc = subprocess.Popen(mic_stream_cmd(sr), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    frames = []
    started = False
    silent_chunks = 0
    t0 = time.time()
    try:
        while (time.time() - t0) < max_sec:
            raw = proc.stdout.read(chunk_bytes)
            if not raw:
                break
            arr = np.frombuffer(raw[: len(raw) - (len(raw) % 2)], dtype=np.int16)
            if len(arr) == 0:
                continue
            rms = ac_rms(arr)
            frames.append(arr)
            if rms > vad_thr:
                started = True
                silent_chunks = 0
            elif started:
                silent_chunks += 1
                if silent_chunks >= 6 and (time.time() - t0) >= 0.8:
                    break
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=1.0)
        except Exception:
            proc.kill()
    return np.concatenate(frames) if frames else np.array([], dtype=np.int16)


def cmd_daemon(args):
    """Always-on low-CPU listener waiting for 'Mi Mi / Hey Mi Mi / Hello Mi Mi' with clear visual/audio wake feedback."""
    running = True

    def stop_handler(*_):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop_handler)
    signal.signal(signal.SIGINT, stop_handler)

    # Pre-warm tiny wake model before going ready so first wake detection is instantaneous
    get_whisper_model("tiny")
    sr = 16000
    chunk_bytes = int(0.25 * sr * 2)
    cmd = mic_stream_cmd(sr)
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    ring = []
    baseline_samples = []
    vad_thr = 0.020
    cooldown_until = 0.0
    ipc_voice_state("ready", "Mi Mi sẵn sàng — hãy gọi 'Mi Mi'")

    try:
        while running:
            raw = proc.stdout.read(chunk_bytes)
            if not raw:
                time.sleep(0.2)
                continue
            arr = np.frombuffer(raw[: len(raw) - (len(raw) % 2)], dtype=np.int16)
            if len(arr) == 0:
                continue
            ring.append(arr)
            if len(ring) > 7:  # ~1.75s rolling window
                ring.pop(0)
            rms = ac_rms(arr)
            if len(baseline_samples) < 4:
                baseline_samples.append(rms)
                if len(baseline_samples) == 4:
                    ambient = float(np.median(baseline_samples))
                    vad_thr = max(0.015, min(0.055, ambient * 2.1))
                continue
            if rms < vad_thr or time.time() < cooldown_until or len(ring) < 3:
                continue

            window_pcm = np.concatenate(ring[-6:])
            prof = load_profile()
            samples = prof.get("samples") or []
            if samples:
                vp = compute_mel_voiceprint(window_pcm)
                best_sim = max(cosine_sim(vp, s["vec"]) for s in samples if s.get("vec"))
                if best_sim < float(prof.get("threshold", DEFAULT_THRESHOLD)):
                    continue

            phrase = transcribe_pcm(window_pcm, model_size="tiny", lang="en")
            matched = matches_wake(phrase)
            if not matched:
                phrase_vi = transcribe_pcm(window_pcm, model_size="tiny", lang="vi")
                matched = matches_wake(phrase_vi)
            if not matched:
                continue

            # Wake word detected! Unmistakable audio chime + glowing top screen pill immediately!
            proc.terminate()
            try:
                proc.wait(timeout=1.0)
            except Exception:
                proc.kill()
            ring.clear()
            play_chime(async_play=True)
            ipc_voice_state("listening", "Mi Mi đã thức — Đang nghe lệnh...")
            cmd_pcm = record_spoken_utterance(max_sec=8.5, vad_thr=vad_thr * 0.9)
            ipc_voice_state("thinking", "Đang hiểu lệnh...")
            raw_spoken = transcribe_pcm(cmd_pcm, model_size=args.model, lang=args.lang)
            spoken = strip_wake_prefix(raw_spoken)
            if spoken:
                ipc_voice_state("thinking", f"Đã nghe: «{spoken[:72]}»")
                subprocess.Popen(
                    ["qs", "-c", "caelestia", "ipc", "call", "ai", "runVoiceTask", spoken],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
            else:
                ipc_voice_state("error", "Không nghe rõ lệnh — hãy gọi lại 'Mi Mi'")
                time.sleep(1.8)
            cooldown_until = time.time() + 2.0
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            if not spoken:
                ipc_voice_state("ready", "Mi Mi sẵn sàng — hãy gọi 'Mi Mi'")
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
