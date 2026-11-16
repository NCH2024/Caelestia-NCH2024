#!/usr/bin/env python3
"""
Caelestia AI Task Automation Orchestrator (v3 — Low-Latency 3-Tier Engine).

Architecture:
1. Preloaded Static System Knowledge (`~/AGENTS.md` auto-discovered by `agy` CLI):
   Zero exploration turns for modes, IPC, paths, or `caelestia-desktop` syntax;
   keeps static prefix stable for maximum provider KV prompt caching.
2. Adaptive 3-Tier Routing (`--effort low` triage -> ~2-4s):
   - Tier 1 (`direct`): Pure Q&A / math / snippets -> answered immediately inside triage.
   - Tier 2 (`single`): Browser control, media, system modes, quick fixes, and multi-action
     user workflows -> executed & self-verified inside ONE continuous `agy` session
     (`--effort medium`, `--conversation` cache reuse on polish) — ~4x faster & ~75% fewer tokens.
   - Tier 3 (`multi`): Heavy multi-file UI/code engineering or deep multi-workstream tasks
     -> 2-3 strictly parallel specialist tracks + unified Coordinator verification & polish loop.
3. Persistent Quota Cooldown Cache (~/.cache/caelestia/ai_model_cooldowns.json):
   Parses 429 `Resets in XhYmZs` durations and skips exhausted models immediately.
"""

from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
import queue
import re
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

try:
    import knowledge_mgr
except Exception:
    knowledge_mgr = None

QUOTA_PATTERNS = re.compile(
    r"(quota|rate[_\s-]?limit|resource[_\s-]?exhausted|429|too many requests|"
    r"capacity|exhausted|usage limit|limit reached|exceeded your)",
    re.IGNORECASE,
)

RESET_DURATION_RE = re.compile(
    r"resets?\s+in\s+(?:(\d+)d)?(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?",
    re.IGNORECASE,
)

AUTH_PATTERNS = re.compile(
    r"(not logged into antigravity|authentication required|unauthenticated|"
    r"unauthorized|please log in|sign in required)",
    re.IGNORECASE,
)

COOLDOWN_PATH = Path.home() / ".cache" / "caelestia" / "ai_model_cooldowns.json"
_EMIT_LOCK = threading.Lock()


def emit(event_type: str, **payload):
    msg = {"type": event_type, "ts": datetime.now().strftime("%H:%M:%S"), **payload}
    with _EMIT_LOCK:
        sys.stdout.write(json.dumps(msg, ensure_ascii=False) + "\n")
        sys.stdout.flush()


def parse_reset_seconds(text: str) -> int:
    m = RESET_DURATION_RE.search(text or "")
    if not m:
        return 1800
    days = int(m.group(1) or 0)
    hours = int(m.group(2) or 0)
    mins = int(m.group(3) or 0)
    secs = int(m.group(4) or 0)
    total = days * 86400 + hours * 3600 + mins * 60 + secs
    return max(120, total)


def format_duration(seconds: int) -> str:
    seconds = max(0, int(seconds))
    h, rem = divmod(seconds, 3600)
    m, _ = divmod(rem, 60)
    if h >= 24:
        d, rh = divmod(h, 24)
        return f"{d}d {rh}h"
    if h > 0:
        return f"{h}h {m}m"
    return f"{max(1, m)}m"


class CooldownStore:
    def __init__(self, path: Path = COOLDOWN_PATH):
        self.path = path
        self._lock = threading.Lock()
        self.data = self._load()

    def _load(self) -> dict:
        try:
            if self.path.exists():
                raw = json.loads(self.path.read_text(encoding="utf-8"))
                if isinstance(raw, dict):
                    now = time.time()
                    return {k: v for k, v in raw.items() if isinstance(v, dict) and float(v.get("until", 0)) > now}
        except Exception:
            pass
        return {}

    def _save(self):
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.path.write_text(json.dumps(self.data, indent=2), encoding="utf-8")
        except Exception:
            pass

    def is_cooled_down(self, model: str) -> tuple[bool, int]:
        with self._lock:
            entry = self.data.get(model)
            if not entry:
                return False, 0
            rem = int(float(entry.get("until", 0)) - time.time())
            if rem <= 0:
                self.data.pop(model, None)
                self._save()
                return False, 0
            return True, rem

    def mark_exhausted(self, model: str, err_text: str):
        sec = parse_reset_seconds(err_text)
        until = time.time() + sec
        with self._lock:
            prev = self.data.get(model, {}).get("until", 0)
            if until > prev:
                self.data[model] = {
                    "until": until,
                    "reason": err_text[:180],
                    "marked_at": int(time.time()),
                }
                self._save()


class SessionLogger:
    def __init__(self, log_path: str):
        self.log_path = log_path
        self._lock = threading.Lock()
        Path(log_path).parent.mkdir(parents=True, exist_ok=True)
        with open(self.log_path, "w", encoding="utf-8") as f:
            f.write(
                f"\033[1;36m=== Caelestia AI Automation — Execution Log ===\033[0m\n"
                f"\033[2mStarted at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\033[0m\n\n"
            )

    def write(self, text: str, color: str = ""):
        ts = datetime.now().strftime("%H:%M:%S")
        prefix = f"\033[2m[{ts}]\033[0m "
        line = f"{prefix}{color}{text}\033[0m\n" if color else f"{prefix}{text}\n"
        with self._lock:
            with open(self.log_path, "a", encoding="utf-8") as f:
                f.write(line)

    def raw(self, text: str):
        with self._lock:
            with open(self.log_path, "a", encoding="utf-8") as f:
                f.write(text)


def extract_json_block(text: str):
    if not text:
        return None
    text = text.strip()
    try:
        return json.loads(text)
    except Exception:
        pass
    m = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
    if m:
        try:
            return json.loads(m.group(1))
        except Exception:
            pass
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end > start:
        try:
            return json.loads(text[start : end + 1])
        except Exception:
            pass
    return None


class Orchestrator:
    def __init__(self, config: dict, log_path: str):
        self.cfg = config
        self.logger = SessionLogger(log_path)
        self.cooldowns = CooldownStore()
        self.inbox = queue.Queue()
        self.stop_requested = False
        self.active_procs = set()
        self.proc_lock = threading.Lock()
        self.model_lock = threading.Lock()
        self.reported_switches = set()

        self.supervisor_model = config.get("supervisorModel", "") or "gemini-4-hydrogen-high"
        self.worker_model = config.get("workerModel", "") or "gemini-4-hydrogen-medium"
        self.fallback_models = [
            m for m in config.get("fallbackModels", []) if isinstance(m, str) and m.strip()
        ]
        self.auto_switch = bool(config.get("autoSwitchOnQuota", True))
        self.full_perms = bool(config.get("fullPermissions", True))
        self.allow_desktop = bool(config.get("allowDesktopActions", True))
        self.prefer_visual_cursor = bool(config.get("preferVisualCursor", True))
        self.ask_on_invalid = bool(config.get("askOnInvalidResult", True))
        self.chat_language = str(config.get("chatLanguage", "vi") or "vi").lower()
        self.voice_mode = bool(config.get("voiceMode", False))
        self.cwd = config.get("cwd") or os.path.expanduser("~")

    def _apply_quick_system_actions(self, spec: dict) -> list[str]:
        """Apply instant (<0.15s) OS controls extracted from intent JSON without LLM tool loops."""
        notes = []
        nl = spec.get("night_light")
        if nl is True:
            res = subprocess.run(["caelestia", "shell", "modes", "setNightLight", "true", "3500"], capture_output=True, text=True)
            if res.returncode == 0:
                notes.append("Night Light: **Đã bật (3500K)**" if self.is_vi() else "Night Light: **Enabled (3500K)**")
        elif nl is False:
            res = subprocess.run(["caelestia", "shell", "modes", "setNightLight", "false", "0"], capture_output=True, text=True)
            if res.returncode == 0:
                notes.append("Night Light: **Đã tắt**" if self.is_vi() else "Night Light: **Disabled**")

        mode_id = str(spec.get("mode_id") or "").strip().lower()
        if mode_id in {"standard", "gaming", "work", "coding", "cinema", "sleep"}:
            res = subprocess.run(["caelestia", "shell", "modes", "activate", mode_id], capture_output=True, text=True)
            if res.returncode == 0:
                notes.append(f"Chế độ hệ thống: **{mode_id}**" if self.is_vi() else f"System Mode: **{mode_id}**")

        bp = spec.get("brightness_pct")
        if isinstance(bp, (int, float)) and 5 <= int(bp) <= 100:
            pct = int(bp)
            subprocess.run(["brightnessctl", "set", f"{pct}%"], capture_output=True)
            notes.append(f"Độ sáng màn hình: **{pct}%**" if self.is_vi() else f"Brightness: **{pct}%**")
        return notes

    def _record_and_reflect_async(self, user_task: str, task_start_ts: float, success: bool, route: str, summary: str = "", note: str = "") -> None:
        """Record verified run stats into knowledge.json and asynchronously reflect if run was slow/failed."""
        if knowledge_mgr is None:
            return
        dur = round(max(0.05, time.time() - task_start_ts), 2)
        notes = [f"route={route}"]
        if note:
            notes.append(note)
        try:
            knowledge_mgr.record_run(user_task, dur, success, summary[:300], trace_notes=notes)
        except Exception:
            pass

        if (not success or dur > 65.0) and not self.stop_requested:
            def _reflect():
                try:
                    fast_m = self.fast_router_model(self.supervisor_model)
                    prompt = (
                        "CRITICAL: Do NOT call ANY tools. Reply immediately with ONE concise English operational rule (<=150 chars) "
                        "to prevent repeating slowness or failure on this system.\n"
                        f"Task: {user_task[:220]}\nRoute: {route}, Duration: {dur}s, Success: {success}\nOutcome: {summary[:220]}"
                    )
                    ok_r, lesson, _, _, _ = self.run_agy("router", "KB Reflect", prompt, fast_m)
                    if ok_r and lesson and len(lesson.strip()) >= 12:
                        topic = f"Optimize {route} workflow"
                        knowledge_mgr.record_run(user_task, dur, success, summary[:300], learned_items=[{"topic": topic, "lesson": lesson.strip()[:190]}])
                except Exception:
                    pass
            threading.Thread(target=_reflect, daemon=True).start()

    def is_vi(self) -> bool:
        return self.chat_language == "vi"

    def language_instruction(self) -> str:
        if self.chat_language == "vi":
            return (
                "LANGUAGE: Write ALL user-facing text in natural, concise Vietnamese (Tiếng Việt). "
                "Never expose internal labels ('Agent A/B/C')."
            )
        elif self.chat_language == "en":
            return (
                "LANGUAGE: Write ALL user-facing text in clear, concise English. "
                "Never expose internal labels ('Agent A/B/C')."
            )
        return (
            "LANGUAGE: Match the exact language of USER REQUEST for all user-facing text. "
            "Never expose internal labels ('Agent A/B/C')."
        )

    def start_stdin_reader(self):
        def reader():
            for line in sys.stdin:
                line = line.strip()
                if not line:
                    continue
                try:
                    cmd = json.loads(line)
                except Exception:
                    continue
                if cmd.get("type") == "stop":
                    self.stop_requested = True
                    with self.proc_lock:
                        for p in list(self.active_procs):
                            if p.poll() is None:
                                try:
                                    p.terminate()
                                except Exception:
                                    pass
                    self.inbox.put(cmd)
                    break
                self.inbox.put(cmd)

        t = threading.Thread(target=reader, daemon=True)
        t.start()

    def ordered_candidates(self, preferred: str) -> list[str]:
        base = [
            preferred,
            *self.fallback_models,
            "gemini-4-hydrogen-high",
            "gemini-4-hydrogen-medium",
            "gemini-4-hydrogen-low",
            "gemini-3.8-flash-high",
            "gemini-3.8-flash-medium",
            "claude-sonnet-5-5-high",
            "gpt-oss-120b-medium",
        ]
        seen = set()
        out = []
        for m in base:
            if m and m not in seen:
                seen.add(m)
                out.append(m)
        return out

    def pick_healthy_model(self, preferred: str, tried: set) -> str | None:
        for cand in self.ordered_candidates(preferred):
            if cand in tried:
                continue
            cooled, _ = self.cooldowns.is_cooled_down(cand)
            if not cooled:
                return cand
        return None

    def resolve_initial_model(self, role: str, preferred: str) -> str | None:
        with self.model_lock:
            if role == "router":
                current = preferred
            else:
                current = self.supervisor_model if role == "coordinator" else self.worker_model
        cooled, rem = self.cooldowns.is_cooled_down(current)
        if not cooled:
            return current
        healthy = self.pick_healthy_model(preferred, set())
        if healthy:
            self.logger.write(
                f"Skipping '{current}' (cooldown {format_duration(rem)} left); using '{healthy}'.",
                "\033[33m",
            )
            with self.model_lock:
                if role == "coordinator":
                    self.supervisor_model = healthy
                else:
                    self.worker_model = healthy
            key = (role, current, healthy)
            if key not in self.reported_switches:
                self.reported_switches.add(key)
                emit(
                    "model_switch",
                    role=role,
                    fromModel=current,
                    toModel=healthy,
                    reason=f"Cached cooldown ({format_duration(rem)} remaining)",
                )
            return healthy
        return None

    def fast_router_model(self, model: str) -> str:
        """Pick lightweight `-low` sibling for fast triage when healthy; avoids model-vs-effort conflicts."""
        for suffix in ("-xhigh", "-high", "-medium"):
            if model.endswith(suffix):
                cand = model[: -len(suffix)] + "-low"
                cooled, _ = self.cooldowns.is_cooled_down(cand)
                if not cooled:
                    return cand
        return model

    def run_agy(
        self,
        role: str,
        worker_label: str,
        prompt: str,
        preferred_model: str,
        conversation_id: str | None = None,
    ) -> tuple[bool, str, str, str, str]:
        """Returns: (ok, output_text, err_text, effective_model, conversation_id)"""
        tried = set()
        current_model = self.resolve_initial_model(role, preferred_model)

        if not current_model:
            return False, "", "Tất cả model đều đang trong thời gian chờ quota.", preferred_model, ""

        while not self.stop_requested and current_model:
            tried.add(current_model)
            cmd = [
                "agy",
                "-p",
                prompt,
                "--output-format",
                "stream-json",
                "--model",
                current_model,
            ]
            if conversation_id:
                cmd.extend(["--conversation", conversation_id])
            if self.full_perms:
                cmd.append("--dangerously-skip-permissions")

            role_color = "\033[1;35m" if role == "coordinator" else "\033[1;32m"
            self.logger.write(
                f"[{worker_label}] starting ({current_model}"
                + (f", resume={conversation_id[:8]}" if conversation_id else "")
                + ")",
                role_color,
            )
            emit("engine_start", role=role, label=worker_label, model=current_model)

            env = os.environ.copy()
            env["TERM"] = "dumb"
            local_bin = os.path.expanduser("~/.local/bin")
            if local_bin not in env.get("PATH", ""):
                env["PATH"] = f"{local_bin}:{env.get('PATH', '')}"

            proc = subprocess.Popen(
                cmd,
                cwd=self.cwd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,
                env=env,
            )
            with self.proc_lock:
                self.active_procs.add(proc)

            collected_text = []
            stderr_lines = []
            quota_hit = False
            auth_hit = False
            final_result_text = None
            captured_conv_id = conversation_id or ""

            def read_stderr():
                for line in proc.stderr:
                    stderr_lines.append(line)
                    clean = line.rstrip()
                    if clean:
                        self.logger.write(f"[{worker_label}] stderr: {clean}", "\033[33m")
                        if QUOTA_PATTERNS.search(clean):
                            nonlocal quota_hit
                            quota_hit = True
                        if AUTH_PATTERNS.search(clean):
                            nonlocal auth_hit
                            auth_hit = True

            err_thread = threading.Thread(target=read_stderr, daemon=True)
            err_thread.start()

            seen_step_tool_idx = set()

            for raw_line in proc.stdout:
                if self.stop_requested:
                    break
                line = raw_line.strip()
                if not line:
                    continue
                try:
                    ev = json.loads(line)
                except Exception:
                    collected_text.append(raw_line)
                    if QUOTA_PATTERNS.search(raw_line):
                        quota_hit = True
                    if AUTH_PATTERNS.search(raw_line):
                        auth_hit = True
                    self.logger.raw(raw_line)
                    continue

                if ev.get("conversation_id") and not captured_conv_id:
                    captured_conv_id = str(ev["conversation_id"])

                ev_type = ev.get("event")
                if ev_type == "step_update":
                    su = ev.get("step_update", {})
                    step_type = su.get("step_type", "")
                    step_idx = su.get("step_index", -1)
                    delta = su.get("text_delta", "")
                    error_msg = su.get("error", "") or su.get("message", "")
                    if error_msg and QUOTA_PATTERNS.search(str(error_msg)):
                        quota_hit = True
                    if error_msg and AUTH_PATTERNS.search(str(error_msg)):
                        auth_hit = True

                    if step_type == "agent_response" and delta:
                        collected_text.append(delta)
                        self.logger.raw(delta)
                        if QUOTA_PATTERNS.search(delta):
                            quota_hit = True
                    elif step_type not in ("user_input", "agent_response", "") and step_idx not in seen_step_tool_idx:
                        seen_step_tool_idx.add(step_idx)
                        tool_info = su.get("tool_name") or step_type
                        self.logger.write(f"  -> [{worker_label}] step #{step_idx}: {tool_info}", "\033[36m")
                        emit("engine_step", worker=worker_label, step=step_idx, detail=str(tool_info))
                elif ev_type == "result":
                    res = ev.get("result", {})
                    if res.get("conversation_id"):
                        captured_conv_id = str(res["conversation_id"])
                    status = res.get("status", "")
                    final_result_text = res.get("response", "")
                    usage = res.get("usage")
                    if usage:
                        self.logger.write(
                            f"  [{worker_label}] tokens: in={usage.get('input_tokens', 0)} "
                            f"cached={usage.get('cache_read_tokens', 0)} out={usage.get('output_tokens', 0)} "
                            f"time={res.get('duration_seconds', 0):.1f}s",
                            "\033[2m",
                        )
                    err_detail = str(res.get("error", "") or "")
                    if err_detail:
                        if QUOTA_PATTERNS.search(err_detail):
                            quota_hit = True
                        if AUTH_PATTERNS.search(err_detail):
                            auth_hit = True
                        stderr_lines.append(err_detail)
                    if status != "SUCCESS" and final_result_text and QUOTA_PATTERNS.search(final_result_text):
                        quota_hit = True
                elif ev_type == "error":
                    err_str = json.dumps(ev, ensure_ascii=False)
                    stderr_lines.append(err_str)
                    if QUOTA_PATTERNS.search(err_str):
                        quota_hit = True
                    if AUTH_PATTERNS.search(err_str):
                        auth_hit = True

            proc.wait()
            err_thread.join(timeout=2)
            with self.proc_lock:
                self.active_procs.discard(proc)

            self.logger.raw("\n")
            output_text = (final_result_text if final_result_text is not None else "".join(collected_text)).strip()
            err_text = "\n".join(stderr_lines).strip()

            if self.stop_requested:
                return False, output_text, "Stopped by user.", current_model, captured_conv_id

            if auth_hit:
                return False, output_text, (
                    "Chưa đăng nhập Antigravity CLI." if self.is_vi() else "Antigravity CLI is not authenticated."
                ), current_model, captured_conv_id

            failed = proc.returncode != 0
            combined_err = output_text + "\n" + err_text
            if quota_hit or (failed and QUOTA_PATTERNS.search(combined_err)):
                self.cooldowns.mark_exhausted(current_model, err_text or combined_err)
                rem_str = format_duration(parse_reset_seconds(err_text or combined_err))
                if self.auto_switch:
                    next_model = self.pick_healthy_model(preferred_model, tried)
                    if next_model:
                        self.logger.write(
                            f"Quota reached on '{current_model}' (reset ~{rem_str}). Switching to '{next_model}'...",
                            "\033[1;33m",
                        )
                        with self.model_lock:
                            if role == "coordinator":
                                self.supervisor_model = next_model
                            else:
                                self.worker_model = next_model
                        sw_key = (role, current_model, next_model)
                        if sw_key not in self.reported_switches:
                            self.reported_switches.add(sw_key)
                            emit(
                                "model_switch",
                                role=role,
                                fromModel=current_model,
                                toModel=next_model,
                                reason=f"Quota exhausted (resets in ~{rem_str})",
                            )
                        current_model = next_model
                        conversation_id = None  # Cannot reuse conversation ID across model switch safely
                        continue
                return False, output_text, (
                    f"Hết hạn mức trên tất cả model khả dụng (tạm nghỉ ~{rem_str})."
                    if self.is_vi()
                    else f"All available models reached quota limits (resets in ~{rem_str})."
                ), current_model, captured_conv_id

            if failed:
                self.logger.write(f"[{worker_label}] exited with code {proc.returncode}: {err_text}", "\033[1;31m")
                return False, output_text, err_text or f"agy exited with code {proc.returncode}", current_model, captured_conv_id

            return True, output_text, err_text, current_model, captured_conv_id

        return False, "", "Stopped by user.", preferred_model, ""

    def wait_user_reply(self, question: str, final_reply: str, suggest_fix: str, model_used: str) -> tuple[str, str]:
        emit(
            "phase",
            phase="waiting_user",
            progress=80,
            detail="Đang chờ bạn xác nhận..." if self.is_vi() else "Waiting for your confirmation...",
        )
        emit(
            "user_question",
            model=model_used,
            verification=final_reply,
            question=question,
            suggestedFix=suggest_fix,
        )
        self.logger.write(f"ASKING USER: {question}", "\033[1;33m")

        while not self.stop_requested:
            try:
                reply = self.inbox.get(timeout=0.5)
            except queue.Empty:
                continue
            rtype = reply.get("type")
            if rtype == "stop":
                return "abort", ""
            if rtype == "user_reply":
                action = str(reply.get("action", "retry"))
                text = str(reply.get("text", "")).strip()
                self.logger.write(f"USER REPLY ({action}): {text}", "\033[1;34m")
                return action, text
        return "abort", ""

    def extract_final_barrier(self, user_task: str) -> tuple[str, str | None]:
        """Strip end-of-task lock barrier from prompts so LLMs NEVER lock prematurely before verification."""
        low = user_task.lower()
        if not re.search(r"\b(khóa màn hình|khóa máy|lock screen)\b", low):
            return user_task, None
        cleaned = re.sub(
            r"(?i)(?:,|\s)*(?:\b(?:và|rồi|sau đó|cuối cùng|sau cùng|then|and|finally)\b\s*)*\b(?:khóa màn hình(?: lại)?|khóa máy(?: lại)?|lock(?:\s+the)?\s+screen)\b[.!\s]*",
            " ",
            user_task,
        )
        cleaned = re.sub(r"\s+", " ", cleaned).strip(" ,")
        return cleaned or user_task, "lock"

    def verify_deterministic_claims(self, user_task: str, task_start_ts: float) -> tuple[bool, str]:
        """Hard OS-level verification gate BEFORE reporting complete or locking screen."""
        low = user_task.lower()
        # 1. Verify Firefox YouTube playback is genuinely uncorked (Corked: no) & not stuck on /results
        if re.search(r"\b(youtube)\b", low) and re.search(r"\b(phát|mở|nghe|play)\b", low):
            out = subprocess.run(["pactl", "list", "sink-inputs"], capture_output=True, text=True).stdout
            ff_playing = any(
                "firefox" in blk.lower() and "corked: no" in blk.lower()
                for blk in out.split("Sink Input #")
            )
            if not ff_playing:
                return False, (
                    "Kiểm chứng hệ thống phát hiện Firefox/YouTube CHƯA phát âm thanh (`Corked: no` chưa hoạt động)."
                    if self.is_vi()
                    else "System check failed: Firefox/YouTube audio is NOT actively playing (`Corked: no` missing)."
                )
        # 2. Verify Word/.docx file was created cleanly during this task
        if re.search(r"\b(word|\.docx|docx)\b", low) and re.search(r"\b(copy|chép|lưu|tạo|xuất|sang|vào)\b", low):
            docs_dir = Path.home() / "Documents"
            recent_docx = [
                p for p in (docs_dir.glob("*.docx") if docs_dir.exists() else [])
                if p.stat().st_mtime >= (task_start_ts - 5) and p.stat().st_size > 400
            ]
            if not recent_docx:
                return False, (
                    "Chưa thấy file Word (.docx) mới hợp lệ được tạo trong ~/Documents/."
                    if self.is_vi()
                    else "System check failed: no newly created valid .docx file found in ~/Documents/."
                )
        return True, ""

    def run_single_fast(self, user_task: str, plan_summary: str, final_barrier: str | None = None, task_start_ts: float | None = None):
        """Tier 2 Fast Lane: One continuous cached `agy` session executes & verifies directly."""
        if task_start_ts is None:
            task_start_ts = time.time()
        emit(
            "assistant_message",
            model=self.worker_model,
            title="Đang thực thi" if self.is_vi() else "Executing",
            text=plan_summary,
        )
        emit(
            "phase",
            phase="working",
            progress=45,
            detail="Đang thực thi & tự kiểm chứng..." if self.is_vi() else "Executing & verifying...",
        )

        wants_visual = self.allow_desktop and (
            self.prefer_visual_cursor
            or bool(re.search(r"\b(chuột|con trỏ|click|bấm|nhấp|rê|cursor|mouse)\b", user_task.lower()))
        )
        if not self.allow_desktop:
            desktop_rule = "Desktop GUI actions are DISABLED; use CLI/files only."
        elif wants_visual:
            desktop_rule = (
                "HUMAN-LIKE VISUAL GUI MODE ACTIVE:\n"
                "- USER-FACING APP TASKS (browsing web articles, reading/scrolling, copying text, pasting into LibreOffice/Word/Editor, playing YouTube): DO THEM VISIBLY ON SCREEN like a human using `caelestia-desktop` + Ghost Cursors (`--agent Browser`, `--agent Editor`). Do NOT silently bypass with headless `search_web` + `write-docx` unless GUI is blocked!\n"
                "  * Browse/read/scroll/copy web article visually: `caelestia-desktop web-copy \"<topic query>\" --agent Browser`\n"
                "  * Open compatible OS Office/Editor (`lowriter`/`libreoffice` > `onlyoffice` > `wps` > `abiword` > `kate`) & visually paste (`Ctrl+V`) + save `.docx`: `caelestia-desktop office-paste --docx ~/Documents/<Name>.docx --title \"<Title>\" --agent Editor`\n"
                "  * YouTube visual search & verified playback: `caelestia-desktop yt-play \"<song/video query>\" --agent Browser`\n"
                "- BACKGROUND SYSTEM CONTROLS (system modes, brightness, volume, telemetry, service checks): USE FAST CLI/IPC directly (`caelestia shell modes activate`, `brightnessctl`, `wpctl`, `pactl`) for instant execution.\n"
                "- FALLBACK ONLY: If `click-text` / `web-copy` / `yt-play` returns error, inspect with `caelestia-desktop screen --grid --fast --out /tmp/ai_screen.jpg --agent \"Meow AI\"` + `read_file` -> `click`.\n"
                "- SAFETY RULE: NEVER run `caelestia shell lock lock` inside your commands — screen lock runs automatically ONLY AFTER verification passes!"
            )
        else:
            desktop_rule = "Desktop GUI control (`caelestia-desktop`) is ALLOWED."
        voice_rule = (
            "\nVOICE ASSISTANT MODE: Keep `final_reply` natural and concise for spoken audio (2-4 complete sentences, NO markdown bullets/tables/URLs, finish every sentence cleanly)."
            if self.voice_mode
            else ""
        )
        exec_prompt = (
            "You are Meow AI executing a user request in ONE efficient session.\n"
            "Use your preloaded AGENTS.md system cheatsheet directly — DO NOT waste turns exploring config files when IPC commands are already known.\n"
            "Combine independent commands in one shell call where practical, execute cleanly, verify the final state once, and return structured JSON.\n"
            f"{desktop_rule}\n{self.language_instruction()}{voice_rule}\n\n"
            f"USER REQUEST:\n{user_task}\n\n"
            "Respond ONLY with valid JSON:\n"
            "{\n"
            '  "verdict": "complete" | "needs_polish" | "needs_user_input",\n'
            '  "final_reply": "Concise verified answer/summary directly for the user",\n'
            '  "question_for_user": "If verdict=needs_user_input, clear question; else empty",\n'
            '  "polish_hint": "If verdict=needs_polish, what still needs fixing; else empty"\n'
            "}"
        )

        conv_id = None
        next_prompt = exec_prompt
        for attempt in range(1, 4):
            ok, out, err, eff_m, conv_id = self.run_agy(
                "executor",
                "Meow AI",
                next_prompt,
                self.worker_model,
                conversation_id=conv_id,
            )
            if not ok:
                emit("task_error", message=err or ("Thực thi thất bại." if self.is_vi() else "Execution failed."))
                return

            parsed = extract_json_block(out)
            if parsed is None:
                ok_det, det_msg = self.verify_deterministic_claims(user_task, task_start_ts)
                if not ok_det and attempt < 3:
                    emit("engine_step", worker="Meow AI", step=attempt, detail=f"Kiểm chứng thất bại — đang khắc phục ({det_msg[:60]})")
                    next_prompt = f"VERIFICATION GATE FAILED: {det_msg}\nFix the actual missing/unplayed item now (e.g. run `caelestia-desktop yt-play ...` or `write-docx ...`) and re-verify cleanly."
                    continue
                if not ok_det:
                    emit("task_error", message=det_msg)
                    return
                barrier_msg = self.run_final_barrier(final_barrier)
                final_txt = f"{out}\n- {barrier_msg}" if barrier_msg else out
                emit("assistant_message", model=eff_m, title="Kết quả đã xác minh" if self.is_vi() else "Verified Result", text=final_txt)
                emit("task_complete", progress=100, summary=final_txt)
                self.logger.write("SINGLE FAST COMPLETED.", "\033[1;32m")
                self._record_and_reflect_async(user_task, task_start_ts, True, "single_fast", final_txt)
                return

            verdict = str(parsed.get("verdict") or "complete").lower()
            final_reply = str(parsed.get("final_reply") or out).strip()
            question = str(parsed.get("question_for_user") or "").strip()
            polish_hint = str(parsed.get("polish_hint") or "").strip()

            if verdict == "complete":
                ok_det, det_msg = self.verify_deterministic_claims(user_task, task_start_ts)
                if not ok_det and attempt < 3:
                    emit("engine_step", worker="Meow AI", step=attempt, detail=f"Kiểm chứng thất bại — đang khắc phục ({det_msg[:60]})")
                    next_prompt = f"VERIFICATION GATE FAILED: {det_msg}\nDo NOT claim complete until fixed (e.g. run `caelestia-desktop yt-play ...` or `write-docx ...`). Respond with JSON."
                    continue
                if not ok_det:
                    emit("task_error", message=det_msg)
                    self._record_and_reflect_async(user_task, task_start_ts, False, "single_fast", det_msg)
                    return
                barrier_msg = self.run_final_barrier(final_barrier)
                if barrier_msg:
                    final_reply = f"{final_reply}\n- {barrier_msg}"
                emit("assistant_message", model=eff_m, title="Kết quả đã xác minh" if self.is_vi() else "Verified Result", text=final_reply)
                emit("task_complete", progress=100, summary=final_reply)
                self.logger.write("SINGLE FAST COMPLETED.", "\033[1;32m")
                self._record_and_reflect_async(user_task, task_start_ts, True, "single_fast", final_reply)
                return

            if verdict == "needs_polish" and attempt < 3:
                emit("engine_step", worker="Meow AI", step=attempt, detail=f"Tự động hoàn thiện (Lượt {attempt})" if self.is_vi() else f"Auto-polish pass #{attempt}")
                next_prompt = f"Continue fixing the remaining issue cleanly and re-verify:\n{polish_hint or final_reply}\n\nRespond with the same JSON schema."
                continue

            if not self.ask_on_invalid:
                emit("task_error", message=final_reply)
                return

            action, user_txt = self.wait_user_reply(
                question or final_reply,
                final_reply,
                polish_hint,
                eff_m,
            )
            if action == "accept":
                emit("assistant_message", model=eff_m, title="Kết quả đã xác nhận" if self.is_vi() else "Accepted Result", text=final_reply)
                emit("task_complete", progress=100, summary=final_reply)
                return
            elif action == "abort":
                emit("task_error", message="Đã hủy theo yêu cầu." if self.is_vi() else "Aborted by user.")
                return
            else:
                next_prompt = f"User guidance:\n{user_txt or polish_hint}\n\nFinish and verify cleanly, responding with the JSON schema."

        emit("task_error", message="Đã vượt quá số lượt tự động." if self.is_vi() else "Exceeded max attempts.")

    def run_collaborators(self, user_task: str, specs: list[dict]) -> list[dict]:
        if not specs:
            return []

        results = []
        specs = specs[:3]  # Tight cap: max 3 parallel engineering tracks (no redundant verifier worker)
        parallel_specs = [s for s in specs if s.get("parallel", True)]
        seq_specs = [s for s in specs if not s.get("parallel", True)]

        def execute_one(idx: int, spec: dict) -> dict:
            rname = str(spec.get("role_name") or f"Specialist {idx + 1}")
            sub_prompt = str(spec.get("prompt") or user_task)
            full_prompt = (
                f"Role: {rname}. Execute ONLY your assigned scope cleanly and verify outputs before reporting.\n"
                "Use preloaded AGENTS.md facts directly (no blind file exploration). Keep output concise without meta-notes about excluded scopes.\n"
                f"{self.language_instruction()}\n\n"
                f"USER REQUEST:\n{user_task}\n\n"
                f"SCOPE:\n{sub_prompt}"
            )
            ok_w, out_w, err_w, eff_m, _ = self.run_agy("executor", rname, full_prompt, self.worker_model)
            # Auxiliary parallel worker cursors retire cleanly when their track finishes; primary stays alive until task_complete
            if rname not in ("Meow AI", "Browser"):
                emit("cursor_done", agent=rname)
            return {
                "role_name": rname,
                "ok": ok_w,
                "output": out_w,
                "error": err_w,
                "model": eff_m,
            }

        if parallel_specs and not self.stop_requested:
            self.resolve_initial_model("executor", self.worker_model)
            with ThreadPoolExecutor(max_workers=len(parallel_specs)) as pool:
                fut_map = {pool.submit(execute_one, i, s): i for i, s in enumerate(parallel_specs)}
                indexed_res = {}
                for fut in as_completed(fut_map):
                    i = fut_map[fut]
                    try:
                        indexed_res[i] = fut.result()
                    except Exception as ex:
                        indexed_res[i] = {
                            "role_name": parallel_specs[i].get("role_name", "Specialist"),
                            "ok": False,
                            "output": "",
                            "error": str(ex),
                            "model": self.worker_model,
                        }
                for i in sorted(indexed_res):
                    results.append(indexed_res[i])

        for j, s in enumerate(seq_specs):
            if self.stop_requested:
                break
            # Strict stage gate: halt downstream sequential stages if a preceding stage failed or was blocked
            prior_failed = any(
                (not r.get("ok"))
                or bool(re.search(r"\b(blocked|unable to|cannot|could not|failed to|chưa thể|không thể|bị khóa|corked:\s*yes)\b", str(r.get("output", "")).lower()))
                for r in results
            )
            if prior_failed:
                self.logger.write(f"Halting sequential stage '{s.get('role_name')}' because prior stage failed verification.", "\033[33m")
                break
            prior_ctx = "\n\n".join(
                f"[{r['role_name']} ({'OK' if r['ok'] else 'ERR'})]:\n{r['output'][:1500]}"
                for r in results
            )
            enriched = dict(s)
            if prior_ctx:
                enriched["prompt"] = f"{s.get('prompt', '')}\n\nPRIOR RESULTS:\n{prior_ctx}"
            results.append(execute_one(len(parallel_specs) + j, enriched))

        return results

    def run_final_barrier(self, final_barrier: str | None) -> str:
        """Execute strict end-of-task barrier action (e.g., lock screen) ONLY after all tracks finish."""
        if not final_barrier:
            return ""
        if final_barrier == "lock":
            self.logger.write("Executing post-completion barrier: caelestia shell lock lock", "\033[1;36m")
            res = subprocess.run(["caelestia", "shell", "lock", "lock"], capture_output=True, text=True)
            if res.returncode == 0:
                return "Đã khóa màn hình sau khi tất cả phân hệ hoàn tất." if self.is_vi() else "Locked screen after all tracks completed."
            return f"Không thể khóa màn hình ({res.stderr.strip() or res.returncode})."
        return ""

    def run_multi_agent(self, user_task: str, triage: dict, eff_coord: str, final_barrier: str | None = None, task_start_ts: float | None = None):
        """Tier 3 Heavy Engineering / Multi-Workstream Team + Coordinator Audit."""
        if task_start_ts is None:
            task_start_ts = time.time()
        collaborators = (triage.get("collaborators") or [])[:3]
        if not collaborators:
            self.run_single_fast(user_task, str(triage.get("plan_summary") or ""), final_barrier=final_barrier, task_start_ts=task_start_ts)
            return

        plan_summary = str(triage.get("plan_summary") or "").strip() or (
            f"Đang điều phối {len(collaborators)} phân hệ chuyên trách."
            if self.is_vi()
            else f"Coordinating {len(collaborators)} specialist tracks."
        )
        success_criteria = str(triage.get("success_criteria") or "All changes pass checks & match request cleanly.")
        role_names = ", ".join(str(c.get("role_name", "Track")) for c in collaborators)
        emit(
            "assistant_message",
            model=eff_coord,
            title=f"Điều phối ({len(collaborators)} phân hệ)" if self.is_vi() else f"Plan ({len(collaborators)} tracks)",
            text=f"{plan_summary}\n[{role_names}]",
        )
        self.logger.write(f"Triage -> multi ({len(collaborators)}): {role_names}", "\033[35m")

        max_auto_polish = 2
        polish_used = 0
        current_specs = collaborators
        accumulated = []
        coord_conv_id = None

        for round_idx in range(1, 4):
            if self.stop_requested:
                break

            emit(
                "phase",
                phase="working",
                progress=min(75, 35 + round_idx * 15),
                detail=(
                    f"Đang thực thi {len(current_specs)} phân hệ (Lượt {round_idx})..."
                    if self.is_vi()
                    else f"Executing {len(current_specs)} track(s) (Round {round_idx})..."
                ),
            )

            collab_results = self.run_collaborators(user_task, current_specs)
            if self.stop_requested:
                break

            for r in collab_results:
                accumulated.append(
                    f"[Round {round_idx} • {r['role_name']} ({'OK' if r['ok'] else 'ERR: ' + r['error']})]\n{r['output']}"
                )

            emit(
                "phase",
                phase="verifying",
                progress=86,
                detail="Đang tổng hợp kết quả..." if self.is_vi() else "Synthesizing verified outcome...",
            )
            self.logger.write("Coordinator verifying & synthesizing outputs...", "\033[1;35m")

            bundled = "\n\n".join(accumulated[-5:])
            all_ok = bool(collab_results) and all(r.get("ok") for r in collab_results)
            has_blocker = bool(re.search(r"\b(blocked|unable to|cannot|could not|failed to|chưa thể|không thể|bị khóa|tạm dừng|corked:\s*yes)\b", bundled.lower()))
            ok_det, det_msg = self.verify_deterministic_claims(user_task, task_start_ts)
            if not ok_det:
                self.logger.write(f"Deterministic claim check failed: {det_msg}", "\033[33m")
                accumulated.append(f"[System Deterministic Audit -> FAIL]\n{det_msg}")
                bundled = "\n\n".join(accumulated[-5:])
            fast_synth = all_ok and not has_blocker and ok_det
            if fast_synth and not self.looks_heavy_engineering(user_task):
                # Deterministic 0ms Python synthesis when non-heavy multi-tracks already verified clean state
                summary_parts = [r["output"].strip() for r in collab_results if r.get("output", "").strip()]
                final_reply = "\n\n".join(summary_parts) if summary_parts else ("Đã hoàn tất tất cả phân hệ." if self.is_vi() else "All tracks completed.")
                barrier_msg = self.run_final_barrier(final_barrier)
                if barrier_msg:
                    final_reply = f"{final_reply}\n- {barrier_msg}"
                self.logger.write("Zero-cloud deterministic synthesis -> complete (0ms Coordinator overhead).", "\033[1;32m")
                emit("assistant_message", model="local-verify", title="Kết quả đã xác minh" if self.is_vi() else "Verified Result", text=final_reply)
                emit("task_complete", progress=100, summary=final_reply)
                self.logger.write("TASK COMPLETED SUCCESSFULLY.", "\033[1;32m")
                self._record_and_reflect_async(user_task, task_start_ts, True, "multi_agent", final_reply)
                return
            audit_model = self.fast_router_model(self.supervisor_model) if fast_synth else self.supervisor_model
            no_tool_hint = (
                "All tracks succeeded cleanly and ran their own checks — synthesize `final_reply` directly WITHOUT running redundant verification commands."
                if fast_synth
                else "Verify actual edited files/tests/status cleanly and choose ONE verdict:"
            )
            barrier_note = (
                f"\nNOTE: Post-task barrier '{final_barrier}' will execute automatically right after you confirm verdict='complete'."
                if final_barrier
                else ""
            )
            synth_prompt = (
                f"Coordinator Audit (Round {round_idx}, auto-polish left: {max_auto_polish - polish_used}).\n"
                f"{no_tool_hint}\n"
                '- `"complete"`: Everything passes & satisfies the request; write `final_reply` directly for the user.\n'
                '- `"needs_polish"`: Fixable lint/code/test error exists & polish > 0; set `polish_prompt`.\n'
                '- `"needs_user_input"`: Ambiguous or external blocker; set `question_for_user`.\n'
                f"{self.language_instruction()}{barrier_note}\n\n"
                f"USER REQUEST:\n{user_task}\n\n"
                f"SUCCESS CRITERIA:\n{success_criteria}\n\n"
                f"SPECIALIST OUTPUTS:\n{bundled}\n\n"
                'Respond ONLY with JSON: {"verdict": "...", "final_reply": "...", "polish_prompt": "...", "question_for_user": "..."}'
            )

            ok_v, synth_raw, err_v, eff_c2, coord_conv_id = self.run_agy(
                "router" if fast_synth else "coordinator",
                "Coordinator Verify",
                synth_prompt,
                audit_model,
                conversation_id=coord_conv_id,
            )
            if not ok_v:
                emit("task_error", message=err_v or ("Kiểm chứng thất bại." if self.is_vi() else "Verification failed."))
                return

            synth = extract_json_block(synth_raw) or {}
            verdict = str(synth.get("verdict") or "complete").lower()
            final_reply = str(synth.get("final_reply") or synth_raw).strip()
            polish_prompt = str(synth.get("polish_prompt") or "").strip()
            question = str(synth.get("question_for_user") or "").strip()

            self.logger.write(f"Coordinator Verdict -> {verdict}", "\033[1;35m")

            if verdict == "complete":
                barrier_msg = self.run_final_barrier(final_barrier)
                if barrier_msg:
                    final_reply = f"{final_reply}\n- {barrier_msg}"
                emit("assistant_message", model=eff_c2, title="Kết quả đã xác minh" if self.is_vi() else "Verified Result", text=final_reply)
                emit("task_complete", progress=100, summary=final_reply)
                self.logger.write("TASK COMPLETED SUCCESSFULLY.", "\033[1;32m")
                self._record_and_reflect_async(user_task, task_start_ts, True, "multi_agent", final_reply)
                return

            if verdict == "needs_polish" and polish_used < max_auto_polish and polish_prompt:
                polish_used += 1
                emit("engine_step", worker="Coordinator QA", step=polish_used, detail=f"Tự động tối ưu & sửa lỗi (Vòng {polish_used})" if self.is_vi() else f"Auto-polish #{polish_used}")
                current_specs = [{"role_name": f"Polish #{polish_used}", "prompt": polish_prompt, "parallel": True}]
                continue

            if not self.ask_on_invalid:
                emit("task_error", message=final_reply)
                return

            action, user_txt = self.wait_user_reply(question or final_reply, final_reply, polish_prompt, eff_c2)
            if action == "accept":
                emit("assistant_message", model=eff_c2, title="Kết quả đã xác nhận" if self.is_vi() else "Accepted Result", text=final_reply)
                emit("task_complete", progress=100, summary=final_reply)
                return
            elif action == "abort":
                emit("task_error", message="Đã hủy theo yêu cầu." if self.is_vi() else "Aborted by user.")
                return
            else:
                current_specs = [{"role_name": "Guided Fixer", "prompt": user_txt or polish_prompt, "parallel": True}]

        emit("task_error", message="Đã vượt quá số lượt tối đa." if self.is_vi() else "Reached max rounds.")

    def try_local_fast_path(self, user_task: str) -> str | None:
        """
        Tier 0 (<100ms, 0 LLM tokens): Instant execution for clear single-intent commands.
        Returns response string if handled cleanly, or None to delegate to AI.
        """
        raw = user_task.strip()
        low = raw.lower()
        # Skip Tier 0 for compound multi-clause prompts or coding/research tasks
        if len(raw) > 85 or re.search(r"\b(và|rồi|sau đó|tìm|code|sửa|tạo|viết|thống kê|check|kiểm tra|phân tích)\b", low):
            return None

        # 1. Instant System Mode Switch
        mode_map = {
            "gaming": r"\b(gaming|chơi game|game mode|turbo)\b",
            "cinema": r"\b(cinema|giải trí|xem phim|media)\b",
            "work": r"\b(work|làm việc|tập trung|focus)\b",
            "coding": r"\b(coding|lập trình|developer|dev)\b",
            "sleep": r"\b(sleep|ngủ|tiết kiệm pin|battery)\b",
            "standard": r"\b(standard|balanced|cân bằng|bình thường)\b",
        }
        if re.search(r"\b(chuyển|đổi|bật|kích hoạt|activate|switch|set)\b", low) and re.search(r"\b(chế độ|mode)\b", low):
            for mode_id, pat in mode_map.items():
                if re.search(pat, low):
                    res = subprocess.run(["caelestia", "shell", "modes", "activate", mode_id], capture_output=True, text=True)
                    if res.returncode == 0:
                        return (
                            f"Đã chuyển chế độ hệ thống sang **{mode_id}** tức thì (`0ms` LLM)."
                            if self.is_vi()
                            else f"Switched system mode to **{mode_id}** instantly."
                        )

        # 2. Instant Audio / Volume / Media
        if re.fullmatch(r"(tắt tiếng|mute|tắt âm thanh)", low):
            subprocess.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "1"])
            return "Đã tắt tiếng âm thanh hệ thống." if self.is_vi() else "Muted system audio."
        if re.fullmatch(r"(bật tiếng|unmute|mở âm thanh)", low):
            subprocess.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"])
            return "Đã bật lại âm thanh." if self.is_vi() else "Unmuted system audio."
        vol_m = re.search(r"(?:âm lượng|volume)\s*(?:lên|về|là|=)?\s*(\d{1,3})\s*%?", low)
        if vol_m:
            pct = max(0, min(150, int(vol_m.group(1))))
            subprocess.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{pct}%"])
            return f"Đã đặt âm lượng hệ thống thành **{pct}%**." if self.is_vi() else f"Set volume to **{pct}%**."
        if re.fullmatch(r"(tạm dừng|pause|dừng nhạc|dừng video)", low):
            subprocess.run(["playerctl", "pause"])
            return "Đã tạm dừng phát media." if self.is_vi() else "Paused media playback."
        if re.fullmatch(r"(phát tiếp|tiếp tục phát|play|resume)", low):
            subprocess.run(["playerctl", "play"])
            return "Đã tiếp tục phát media." if self.is_vi() else "Resumed media playback."
        if re.fullmatch(r"(bài tiếp|bài kế|next track|next song)", low):
            subprocess.run(["playerctl", "next"])
            return "Đã chuyển sang bài tiếp theo." if self.is_vi() else "Skipped to next track."

        # 3. Instant App Launch
        app_map = {
            r"^(?:mở|open|chạy)\s+(?:trình duyệt\s+)?firefox$": ["caelestia-desktop", "launch", "firefox"],
            r"^(?:mở|open|chạy)\s+terminal$": ["caelestia-desktop", "launch", "foot"],
            r"^(?:mở|open)\s+(?:cài đặt|settings|nexus)$": ["qs", "-c", "caelestia", "ipc", "call", "nexus", "open"],
            r"^(?:mở|open)\s+equalizer$": ["qs", "-c", "caelestia", "ipc", "call", "nexus", "openPage", "6"],
        }
        for pat, cmd in app_map.items():
            if re.match(pat, low):
                subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
                return f"Đã mở theo yêu cầu (`{cmd[-1]}`)." if self.is_vi() else f"Launched `{cmd[-1]}`."

        return None

    def try_compound_visual_fast_path(self, user_task: str) -> str | None:
        """
        Tier 0.5 (~4-7s, 0 cloud LLM tokens): Handles clear multi-clause desktop automation
        (YouTube search+play + System Mode + Brightness + Volume + Post-Completion Lock)
        visually with parallel Ghost Cursors (`--agent Browser` & `--agent Control`) + live verification.
        Falls back cleanly (`return None`) if any clause is unrecognized or needs Cloud reasoning.
        """
        raw = user_task.strip()
        if not raw or len(raw) > 260:
            return None
        low = raw.lower()
        # Bail immediately for coding, files, web reading/research, or complex analysis
        if re.search(r"\b(code|sửa file|tạo file|viết|refactor|bài báo|google|thống kê|phân tích|tại sao|giải thích|so sánh)\b", low):
            return None

        clauses = [
            c.strip()
            for c in re.split(
                r"(?:\s*,\s*|\b(?:và sau đó|sau đó|đồng thời|rồi|cuối cùng|sau cùng)\b|\bvà\s+(?=(?:chuyển|đổi|bật|tắt|tăng|giảm|đặt|mở|phát|khóa|switch|set|turn|open|play|lock)\b))",
                raw,
                flags=re.IGNORECASE,
            )
            if c.strip()
        ]
        # Allow "mở và phát ..." inside first YouTube clause by re-joining if a clause is just "mở"
        merged_clauses = []
        i = 0
        while i < len(clauses):
            cur = clauses[i]
            if re.fullmatch(r"(?:mở|open)", cur.lower()) and i + 1 < len(clauses):
                merged_clauses.append(f"{cur} {clauses[i+1]}")
                i += 2
            else:
                merged_clauses.append(cur)
                i += 1
        clauses = merged_clauses
        if len(clauses) < 2:
            return None

        yt_query = None
        mode_id = None
        brightness_pct = None
        volume_pct = None
        mute_state = None
        final_barrier = None

        mode_map = {
            "gaming": (r"\b(gaming|chơi game|game mode|turbo)\b", "Gaming"),
            "cinema": (r"\b(cinema|giải trí|xem phim|media)\b", "Cinema"),
            "work": (r"\b(work|làm việc|tập trung|focus)\b", "Work"),
            "coding": (r"\b(coding|lập trình|developer|dev)\b", "Developer"),
            "sleep": (r"\b(sleep|ngủ|tiết kiệm pin|battery)\b", "Night"),
            "standard": (r"\b(standard|balanced|cân bằng|bình thường)\b", "Balanced"),
        }
        mode_label = None

        for cl in clauses:
            cl_low = cl.lower().strip()
            # 1. Lock barrier
            if re.search(r"\b(khóa màn hình|khóa máy|lock screen|lock)\b", cl_low) and len(cl_low) <= 45:
                final_barrier = "lock"
                continue
            # 2. YouTube search/play
            if "youtube" in cl_low and re.search(r"\b(mở|phát|tìm|chạy|xem|nghe|open|play|search)\b", cl_low):
                q = re.sub(
                    r"(?i)\b(mở|và|phát|tìm|chạy|xem|nghe|bài hát|bài|video|clip|nhạc|của|trên|ở|youtube|open|play|search|on|song)\b",
                    " ",
                    cl,
                )
                q = re.sub(r"\s+", " ", q).strip(" ,.-")
                if q:
                    yt_query = q
                    continue
                return None
            # 3. Mode switch
            if re.search(r"\b(chuyển|đổi|bật|kích hoạt|activate|switch|set)\b", cl_low) and re.search(r"\b(chế độ|mode)\b", cl_low):
                matched_m = False
                for mid, (pat, lbl) in mode_map.items():
                    if re.search(pat, cl_low):
                        mode_id = mid
                        mode_label = lbl
                        matched_m = True
                        break
                if matched_m:
                    continue
                return None
            # 4. Brightness
            if re.search(r"\b(độ sáng|brightness)\b", cl_low):
                if re.search(r"\b(tối đa|max|full|hết cỡ)\b", cl_low):
                    brightness_pct = 100
                    continue
                if re.search(r"\b(tối thiểu|min|thấp nhất)\b", cl_low):
                    brightness_pct = 10
                    continue
                bm = re.search(r"(\d{1,3})\s*%?", cl_low)
                if bm:
                    brightness_pct = max(5, min(100, int(bm.group(1))))
                    continue
                return None
            # 5. Volume
            if re.search(r"\b(âm lượng|volume|tắt tiếng|bật tiếng|mute|unmute)\b", cl_low):
                if re.search(r"\b(tắt tiếng|mute)\b", cl_low):
                    mute_state = "1"
                    continue
                if re.search(r"\b(bật tiếng|unmute)\b", cl_low):
                    mute_state = "0"
                    continue
                vm = re.search(r"(\d{1,3})\s*%?", cl_low)
                if vm:
                    volume_pct = max(0, min(150, int(vm.group(1))))
                    continue
                return None
            # Unknown clause -> defer to Cloud AI cleanly
            return None

        if not (yt_query or mode_id or brightness_pct is not None or volume_pct is not None or mute_state is not None):
            return None

        self.logger.write(
            f"Tier 0.5 visual compound fast-path -> yt={yt_query!r}, mode={mode_id}, bright={brightness_pct}, barrier={final_barrier}",
            "\033[1;36m",
        )
        emit(
            "assistant_message",
            model="local-visual-fast",
            title="Điều phối đa bước có kiểm chứng" if self.is_vi() else "Verified Sequential Visual Pipeline",
            text=(
                "Đang thực thi tuần tự từng bước với con trỏ trực quan (chỉ chuyển bước & khóa khi bước trước đã xác minh)."
                if self.is_vi()
                else "Executing ordered visual stages sequentially (verifying each stage before proceeding)."
            ),
        )
        emit("phase", phase="working", progress=45, detail="Đang thao tác trực quan..." if self.is_vi() else "Executing visual actions...")

        from urllib.parse import quote_plus
        from concurrent.futures import ThreadPoolExecutor

        def run_browser_track() -> tuple[bool, str]:
            emit("engine_start", role="executor", label="Browser", model="local-visual")
            emit("engine_step", worker="Browser", step=1, detail=f"Mở & xác minh phát YouTube: {yt_query}")
            res = subprocess.run(
                ["caelestia-desktop", "yt-play", yt_query, "--agent", "Browser"],
                capture_output=True,
                text=True,
            )
            if res.returncode != 0:
                return False, f"Video '{yt_query}' chưa phát âm thanh (`Corked: no` chưa kích hoạt)."
            return True, f"Firefox YouTube (**{yt_query}**): đã mở và xác nhận đang phát (`Corked: no`)."

        def run_control_track() -> tuple[bool, list[str]]:
            emit("engine_start", role="executor", label="Control", model="local-visual")
            notes = []
            if mode_id:
                if self.prefer_visual_cursor:
                    subprocess.run(["caelestia", "shell", "nexus", "openPage", "1"], capture_output=True)
                    subprocess.run(
                        ["caelestia-desktop", "click-text", mode_label or mode_id, "--window", "quickshell", "--wait", "2.5", "--agent", "Control"],
                        capture_output=True,
                    )
                subprocess.run(["caelestia", "shell", "modes", "activate", mode_id], capture_output=True)
                emit("engine_step", worker="Control", step=1, detail=f"Chuyển chế độ -> {mode_id}")
                notes.append(f"Chế độ hệ thống: **{mode_id}**")
            if brightness_pct is not None:
                subprocess.run(["brightnessctl", "set", f"{brightness_pct}%"], capture_output=True)
                subprocess.Popen(
                    ["qs", "-c", "caelestia", "ipc", "call", "ai", "cursorEvent", "1840", "240", "auto_awesome", f"Sáng {brightness_pct}%", "0", "Control"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                emit("engine_step", worker="Control", step=2, detail=f"Độ sáng -> {brightness_pct}%")
                notes.append(f"Độ sáng màn hình: **{brightness_pct}%**")
            if volume_pct is not None:
                subprocess.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{volume_pct}%"], capture_output=True)
                notes.append(f"Âm lượng: **{volume_pct}%**")
            if mute_state is not None:
                subprocess.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", mute_state], capture_output=True)
                notes.append("Đã tắt tiếng." if mute_state == "1" else "Đã bật tiếng.")
            emit("cursor_done", agent="Control")
            return True, notes

        # Strict sequential stage ordering: Stage 1 (Browser media verified playing) -> Stage 2 (Control/Mode/Brightness) -> Stage 3 (Lock Barrier)
        has_control_ops = bool(mode_id or brightness_pct is not None or volume_pct is not None or mute_state is not None)
        summary_lines = []
        if yt_query:
            browser_ok, brw_msg = run_browser_track()
            summary_lines.append(f"- {brw_msg}")
            if not browser_ok:
                # CRITICAL: Do NOT apply lock screen or downstream mode switch when Stage 1 playback failed!
                self.logger.write(f"Tier 0.5 halted before Stage 2/Barrier: {brw_msg}", "\033[33m")
                return None

        if has_control_ops:
            ctl_ok, ctl_notes = run_control_track()
            for n in ctl_notes:
                summary_lines.append(f"- {n}")
            if not ctl_ok:
                self.logger.write("Tier 0.5 halted before final barrier: Control track failed.", "\033[33m")
                return None

        if final_barrier:
            # Brief beat so final cursor & verified status are visible before screen locks
            time.sleep(0.5)
        barrier_msg = self.run_final_barrier(final_barrier)
        if barrier_msg:
            summary_lines.append(f"- {barrier_msg}")
        return "\n".join(summary_lines)

    def try_curated_web_office_pipeline(self, user_task: str, clean_task: str, final_barrier: str | None, task_start_ts: float) -> str | None:
        """
        Overhauled Human-Like Web->Word/Office (+ optional YouTube) Pipeline (~15-22s total):
        1) 1-shot fast intent extract (no tool loops, ~2s)
        2) Direct visible Firefox web-copy (Reader View + scroll + Ctrl+C, ~7s, 0 LLM steps)
        3) Parallel: AI Curation/Formatting (strips web junk -> styled Markdown, ~3s) || YouTube yt-play (~6s)
        4) Visual office-paste (opens OS Word/Editor + pastes curated text + writes styled .docx, ~1.5s)
        5) Hard OS verification gate -> final lock barrier
        """
        fast_m = self.fast_router_model(self.supervisor_model)
        emit("phase", phase="planning", progress=15, detail="Đang phân tích yêu cầu bài viết & tài liệu..." if self.is_vi() else "Parsing article & document parameters...")

        parse_prompt = (
            "CRITICAL: Do NOT call ANY tools (no run_command, no read_file, no search_web). Reply immediately with ONLY valid JSON.\n"
            "Normalize any spelling typos (e.g. 'Onui'->'One UI', 'saung'->'sau đó', 'Hoyovers'->'HoYoverse') into clean search queries:\n"
            f"USER REQUEST: {clean_task}\n\n"
            "Return JSON schema:\n"
            '{"article_query":"concise search words for web","doc_filename":"Clean_Ascii_Name.docx","doc_title":"Clean Document Title",'
            '"curation_focus":"what key facts/sections the user wants","yt_query":"song/video query if user asked to play YouTube else empty string",'
            '"want_image":true,"night_light":null,"mode_id":"","brightness_pct":null}\n'
            "Rules: set night_light to true/false only if user explicitly asked for Night Light; set mode_id only if user asked to switch system mode (standard/gaming/work/coding/cinema/sleep)."
        )
        ok_p, raw_p, _, eff_p, _ = self.run_agy("router", "Intent Parse", parse_prompt, fast_m)
        if not ok_p:
            return None
        spec = extract_json_block(raw_p) or {}
        article_query = str(spec.get("article_query") or "").strip()
        if not article_query:
            return None
        doc_filename = re.sub(r"[^A-Za-z0-9_.-]+", "_", str(spec.get("doc_filename") or "Article_Summary.docx")).strip("_") or "Article_Summary.docx"
        if not doc_filename.lower().endswith(".docx"):
            doc_filename += ".docx"
        doc_title = str(spec.get("doc_title") or article_query).strip()
        curation_focus = str(spec.get("curation_focus") or clean_task).strip()
        yt_query = str(spec.get("yt_query") or "").strip()
        want_image = bool(spec.get("want_image")) or bool(re.search(r"\b(ảnh|hình|minh họa|chèn ảnh|image|picture|photo)\b", clean_task.lower()))
        img_out_path = Path("/tmp/ai_article_img.jpg")
        try:
            img_out_path.unlink(missing_ok=True)
        except Exception:
            pass

        self.logger.write(
            f"Curated Web->Office pipeline -> query={article_query!r}, doc={doc_filename}, yt={yt_query!r}, img={want_image}, nl={spec.get('night_light')}, barrier={final_barrier}",
            "\033[1;36m",
        )
        emit(
            "assistant_message",
            model=eff_p,
            title="Thực thi trực quan (Đọc web → Chọn lọc → Soạn thảo)" if self.is_vi() else "Human-Like Curated Pipeline",
            text=(
                f"Đang mở Firefox tìm & đọc bài về **{article_query}**, lọc thông tin trọng tâm vào **{doc_filename}**"
                + (" (kèm ảnh minh họa)" if want_image else "")
                + (f" và phát **{yt_query}** trên YouTube." if yt_query else ".")
                if self.is_vi()
                else f"Browsing **{article_query}**, curating clean content into **{doc_filename}**" + (f", and playing **{yt_query}**." if yt_query else ".")
            ),
        )

        # Phase 2: Human-like visible web-copy directly via desktop_ctl (0 LLM step latency!)
        emit("phase", phase="working", progress=35, detail="Đang mở Firefox tìm, cuộn đọc & copy bài viết..." if self.is_vi() else "Browsing & scrolling article in Firefox...")
        emit("engine_start", role="executor", label="Browser", model="local-visual")
        emit("engine_step", worker="Browser", step=1, detail=f"Mở Firefox tìm & cuộn đọc: {article_query}")
        wc_cmd = ["caelestia-desktop", "web-copy", article_query, "--scrolls", "2", "--agent", "Browser"]
        if want_image:
            wc_cmd += ["--save-image", str(img_out_path)]
        wc_res = subprocess.run(
            wc_cmd,
            capture_output=True,
            text=True,
            timeout=40,
        )
        if wc_res.returncode == 2:
            emit("task_error", message="Trang tìm kiếm yêu cầu xác minh CAPTCHA/người thật — AI đã dừng theo quy tắc an toàn." if self.is_vi() else "Blocked by CAPTCHA verification.")
            return "__ABORTED__"
        if wc_res.returncode != 0:
            self.logger.write(f"web-copy missed ({wc_res.stdout.strip()}); handing off cleanly.", "\033[33m")
            return None

        wc_info = extract_json_block(wc_res.stdout) or {}
        raw_path = Path(wc_info.get("raw_file") or "/tmp/ai_web_copied.txt")
        raw_text = raw_path.read_text(encoding="utf-8") if raw_path.exists() else subprocess.run(["wl-paste", "--no-newline"], capture_output=True, text=True).stdout
        raw_trimmed = raw_text[:9000]

        # Phase 3: Parallel AI Content Curation (no GUI!) + Visual YouTube yt-play (Firefox GUI!)
        emit("phase", phase="working", progress=62, detail="Đang chọn lọc & biên tập nội dung đẹp cho Word..." if self.is_vi() else "Curating clean article structure...")
        curated_path = Path("/tmp/ai_curated_doc.md")

        def run_curation() -> tuple[bool, str]:
            emit("engine_start", role="router", label="Editor AI", model=fast_m)
            emit("engine_step", worker="Editor AI", step=1, detail="Lọc bỏ rác trang web & biên tập cấu trúc Word")
            curate_prompt = (
                "CRITICAL: Do NOT call ANY tools (no run_command, no write_file, no read_file). Reply IMMEDIATELY with ONLY clean Markdown.\n"
                "You are an editor turning raw webpage clipboard text into a clean, well-structured Word document.\n"
                f"TASK GOAL / FOCUS: {curation_focus}\n"
                f"ARTICLE TITLE HINT: {wc_info.get('page_title') or doc_title}\n"
                f"{self.language_instruction()}\n"
                "STRICT RULES:\n"
                "- Remove ALL leftover navigation menus, ads, cookie notices, 'Skip to content', login buttons, unrelated links.\n"
                "- Select ONLY accurate, substantive facts from the source text below.\n"
                "- Format cleanly for Word typography using `# Main Title`, `## Section Heading`, and concise `- **Key point:** details` bullets + `## Nguồn tham khảo` at the end.\n"
                "- When comparing items, release dates, platforms, or specs, include a concise Markdown comparison table (`| Col 1 | Col 2 |`) so it renders as a formatted Word table.\n\n"
                f"RAW COPIED WEBPAGE TEXT:\n{raw_trimmed}"
            )
            ok_c, curated_md, err_c, _, _ = self.run_agy("router", "Editor AI", curate_prompt, fast_m)
            if not ok_c or len((curated_md or "").strip()) < 120:
                return False, err_c or "Curation returned empty text"
            # Strip accidental markdown code fences if model wrapped output
            cleaned_md = re.sub(r"^```(?:markdown|md)?\s*|\s*```$", "", curated_md.strip(), flags=re.IGNORECASE)
            curated_path.write_text(cleaned_md, encoding="utf-8")
            return True, cleaned_md

        def run_youtube() -> tuple[bool, dict]:
            emit("engine_step", worker="Browser", step=2, detail=f"Mở & kiểm tra phát YouTube: {yt_query}")
            res_y = subprocess.run(["caelestia-desktop", "yt-play", yt_query, "--agent", "Browser"], capture_output=True, text=True, timeout=30)
            info_y = extract_json_block(res_y.stdout) or {}
            return res_y.returncode == 0, info_y

        yt_ok = True
        yt_info = {}
        with ThreadPoolExecutor(max_workers=2) as pool:
            fut_cur = pool.submit(run_curation)
            fut_yt = pool.submit(run_youtube) if yt_query else None
            cur_ok, cur_out = fut_cur.result()
            if fut_yt:
                yt_ok, yt_info = fut_yt.result()

        if not cur_ok:
            curated_path.write_text(raw_trimmed, encoding="utf-8")

        # Phase 4: Open highest-priority OS Office/Editor, visually paste curated text + write styled .docx (+ embedded image if saved)
        emit("phase", phase="verifying", progress=84, detail="Đang mở trình soạn thảo, dán & định dạng file Word..." if self.is_vi() else "Pasting curated doc into Office/Editor...")
        docx_out = str(Path.home() / "Documents" / doc_filename)
        emit("engine_start", role="executor", label="Editor", model="local-visual")
        emit("engine_step", worker="Editor", step=1, detail=f"Mở app & dán bài viết tinh chỉnh -> {doc_filename}")
        op_cmd = ["caelestia-desktop", "office-paste", "--source-file", str(curated_path), "--docx", docx_out, "--title", doc_title, "--agent", "Editor"]
        has_img = bool(want_image and img_out_path.exists() and img_out_path.stat().st_size >= 10000)
        if has_img:
            op_cmd += ["--image", str(img_out_path)]
        op_res = subprocess.run(
            op_cmd,
            capture_output=True,
            text=True,
            timeout=25,
        )
        op_info = extract_json_block(op_res.stdout) or {}
        emit("cursor_done", agent="Editor")

        # Instant (<0.1s) OS controls extracted from intent (Night Light / Mode / Brightness)
        sys_notes = self._apply_quick_system_actions(spec)

        # Phase 5: Hard OS Verification Gate before final barrier
        if yt_query and not yt_ok:
            emit(
                "task_error",
                message=(
                    f"Đã biên tập bài viết vào [Word](file://{docx_out}), nhưng YouTube chưa xác nhận phát âm thanh (`Corked: no`) nên đã DỪNG trước bước khóa màn hình."
                    if self.is_vi()
                    else f"Saved curated doc {docx_out}, but YouTube playback check failed — halted before lock screen."
                ),
            )
            return "__ABORTED__"

        ok_det, det_msg = self.verify_deterministic_claims(user_task, task_start_ts)
        if not ok_det:
            emit("task_error", message=det_msg)
            return "__ABORTED__"

        summary_lines = [
            f"- **Bài viết nguồn (đọc trực quan trên Firefox):** {wc_info.get('page_title') or wc_info.get('matched_link')}",
            f"- **Biên tập & định dạng Word:** Đã lọc bỏ rác web, định dạng tiêu đề/đề mục/bảng biểu sạch đẹp tại [{doc_filename}](file://{docx_out})"
            + (" kèm ảnh minh họa nhúng trong tài liệu" if has_img else "")
            + f" (trình soạn thảo đã mở: `{op_info.get('app') or 'none'}`).",
        ]
        if yt_query:
            summary_lines.append(f"- **YouTube (`Corked: no`):** Đang phát *{yt_info.get('title') or yt_query}*.")
        for sn in sys_notes:
            summary_lines.append(f"- {sn}")

        if final_barrier:
            time.sleep(0.5)
        barrier_msg = self.run_final_barrier(final_barrier)
        if barrier_msg:
            summary_lines.append(f"- {barrier_msg}")

        return "\n".join(summary_lines)

    def looks_heavy_engineering(self, user_task: str) -> bool:
        low = user_task.lower()
        is_desktop_media = bool(
            re.search(
                r"\b(youtube|word|libreoffice|liboffice|\.docx|docx|night light|chế độ|độ sáng|âm lượng|bài viết|bài nhạc|game|tìm kiếm|copy|dán)\b",
                low,
            )
        )
        max_len = 500 if is_desktop_media else 180
        return bool(
            len(user_task) > max_len
            or re.search(
                r"\b(thêm tính năng|xây dựng tính năng|tạo module|tái cấu trúc|refactor|"
                r"implement feature|add feature|multi-?agent|nghiên cứu.*thống kê|"
                r"viết giao diện|code thêm)\b",
                low,
            )
        )

    def looks_pure_qa(self, user_task: str) -> bool:
        low = user_task.lower().strip()
        if len(low) > 140:
            return False
        action_verbs = (
            r"\b(mở|open|chuyển|đổi|bật|tắt|kiểm tra|check|tìm|search|click|bấm|gõ|type|"
            r"sửa|edit|tạo|create|xóa|delete|cài|install|chạy|run|phát|play|chụp|screenshot|"
            r"lưu|save|push|git|commit|cập nhật|update|caelestia|firefox|terminal|file|thư mục)\b"
        )
        return not re.search(action_verbs, low)

    def run_task(self, user_task: str):
        task_start_ts = time.time()
        self.logger.write(f"USER REQUEST: {user_task}", "\033[1;34m")

        # Tier 0: Zero-LLM Instant Local Execution (<100ms, 0 tokens)
        fast_ans = self.try_local_fast_path(user_task)
        if fast_ans is not None:
            self.logger.write(f"Tier 0 local fast-path hit -> {fast_ans}", "\033[1;36m")
            emit("phase", phase="done", progress=100, detail=fast_ans)
            emit("assistant_message", model="local-fast", title="Thực thi tức thì" if self.is_vi() else "Instant Action", text=fast_ans)
            emit("task_complete", progress=100, summary=fast_ans)
            self._record_and_reflect_async(user_task, task_start_ts, True, "tier0_fast", fast_ans)
            return

        # Tier 0.5: Sequential Visual Compound Fast-Path (~5-9s, 0 cloud tokens, real Ghost Cursors!)
        compound_ans = self.try_compound_visual_fast_path(user_task)
        if compound_ans is not None:
            self.logger.write("Tier 0.5 visual compound fast-path completed.", "\033[1;32m")
            emit("assistant_message", model="local-visual", title="Hoàn tất tức thì" if self.is_vi() else "Completed Fast", text=compound_ans)
            emit("task_complete", progress=100, summary=compound_ans)
            self._record_and_reflect_async(user_task, task_start_ts, True, "tier05_compound", compound_ans)
            return

        # Global safety invariant: extract end-of-task lock barrier from ALL AI routes
        clean_task, final_barrier = self.extract_final_barrier(user_task)

        # Fast 0ms heuristic bypasses extra cold Router LLM call for 90% of requests!
        if self.looks_pure_qa(clean_task):
            emit("phase", phase="working", progress=35, detail="Đang trả lời nhanh..." if self.is_vi() else "Answering...")
            qa_model = self.fast_router_model(self.supervisor_model)
            qa_style = (
                "Voice assistant mode: reply concisely in 1-3 natural spoken sentences without Markdown tables/URLs or code formatting."
                if self.voice_mode
                else "Answer concisely and accurately in Markdown without running unnecessary tools:"
            )
            ok, ans, err, eff_m, _ = self.run_agy(
                "router",
                "Meow AI",
                f"{self.language_instruction()}\n{qa_style}\n{clean_task}",
                qa_model,
            )
            if not ok:
                emit("task_error", message=err or "Error")
                self._record_and_reflect_async(user_task, task_start_ts, False, "direct_qa", err or "Error")
                return
            barrier_msg = self.run_final_barrier(final_barrier)
            if barrier_msg:
                ans = f"{ans}\n- {barrier_msg}"
            emit("assistant_message", model=eff_m, title="Trả lời" if self.is_vi() else "Response", text=ans)
            emit("task_complete", progress=100, summary=ans)
            self.logger.write("DIRECT FAST QA COMPLETED.", "\033[1;32m")
            self._record_and_reflect_async(user_task, task_start_ts, True, "direct_qa", ans)
            return

        if not self.looks_heavy_engineering(clean_task):
            low = clean_task.lower()
            has_browser = bool(re.search(r"\b(trình duyệt|browser|firefox|youtube|google|web|bài báo|trang web)\b", low))
            has_control = bool(re.search(r"\b(chế độ|mode|cài đặt|settings|nexus|bảng điều khiển|độ sáng|âm lượng|equalizer|phần mềm|thống kê)\b", low))
            has_research_doc = bool(
                re.search(r"\b(bài viết|bài báo|trên mạng|tìm bài|tìm kiếm|thông tin|copy|chép|dán|word|libreoffice|liboffice|\.docx|docx|soạn thảo)\b", low)
                and re.search(r"\b(word|libreoffice|liboffice|\.docx|docx|soạn thảo|bài viết|bài báo)\b", low)
            )
            has_youtube_play = bool(re.search(r"\b(youtube)\b", low) and re.search(r"\b(mở|phát|nghe|play)\b", low))

            barrier_warn = (
                " CRITICAL: Do NOT run `caelestia shell lock lock` yourself — screen lock runs automatically ONLY AFTER verified completion!"
                if final_barrier
                else ""
            )

            # Overhauled Human-Like Web->Curated Word/Office (+ optional YouTube + Night Light/Mode) Pipeline (~20-28s total!)
            if self.allow_desktop and has_research_doc:
                curated_ans = self.try_curated_web_office_pipeline(user_task, clean_task, final_barrier, task_start_ts)
                if curated_ans == "__ABORTED__":
                    self._record_and_reflect_async(user_task, task_start_ts, False, "curated_web_word", "Aborted at safety/verification gate")
                    return
                if curated_ans is not None:
                    self.logger.write("Curated Web->Office pipeline completed cleanly.", "\033[1;32m")
                    emit("assistant_message", model="curated-pipeline", title="Kết quả đã tinh chỉnh & xác minh" if self.is_vi() else "Curated & Verified Result", text=curated_ans)
                    emit("task_complete", progress=100, summary=curated_ans)
                    self._record_and_reflect_async(user_task, task_start_ts, True, "curated_web_word", curated_ans)
                    return

            if self.allow_desktop and self.prefer_visual_cursor and has_browser and has_control:
                has_seq_order = bool(re.search(r"\b(sau đó|rồi|tiếp theo|cuối cùng|sau cùng|then|after that)\b", low))
                ctl_parallel = not has_seq_order
                self.logger.write(
                    f"Local router -> multi-cursor GUI tracks (Browser + Control, sequential={has_seq_order}, barrier={final_barrier}).",
                    "\033[1;36m",
                )
                multi_triage = {
                    "plan_summary": (
                        "Đang điều phối tuần tự theo từng bước (kiểm chứng xong mới chuyển bước) với con trỏ trực quan."
                        if has_seq_order and self.is_vi()
                        else (
                            "Đang điều phối đồng thời 2 con trỏ AI thao tác trên Trình duyệt và Bảng điều khiển."
                            if self.is_vi()
                            else "Operating Browser and Control Panel with live visual cursors."
                        )
                    ),
                    "success_criteria": "Browser playback/task and Control settings complete in order and pass verification.",
                    "collaborators": [
                        {
                            "role_name": "Browser",
                            "prompt": (
                                "Handle ONLY the browser/web portion visually using `--agent Browser`: "
                                "for YouTube, run `caelestia-desktop yt-play \"<song/video query>\" --agent Browser` in ONE call (already skips `--min-y 185`, waits cleanly for autoplay, and verifies `Corked: no`). "
                                "For other websites, launch Firefox and click via `click-text ... --window firefox --min-y 185 --wait 5 --agent Browser`. Fail cleanly if audio/action is unverified."
                                + barrier_warn
                            ),
                            "parallel": True,
                        },
                        {
                            "role_name": "Control",
                            "prompt": (
                                "Handle ONLY settings/modes/audio/brightness/app actions visually in 1 batched shell call using `--agent Control`: "
                                "e.g., `caelestia shell nexus openPage 1 && caelestia-desktop click-text \"Cinema\" --window quickshell --wait 2.5 --agent Control && brightnessctl set 100%`, and verify final state (`extra.json`, `brightnessctl get`, etc.)."
                                + barrier_warn
                            ),
                            "parallel": ctl_parallel,
                        },
                    ],
                }
                self.run_multi_agent(user_task, multi_triage, self.supervisor_model, final_barrier=final_barrier, task_start_ts=task_start_ts)
                return

            # Direct Unified Single-Session Execution (saves 4-6s + ~10k tokens vs separate Router boot)
            plan_msg = (
                "Đang thực thi trực tiếp trong 1 phiên hợp nhất..."
                if self.is_vi()
                else "Executing in single unified session..."
            )
            self.logger.write(f"Local router -> unified single fast lane (barrier={final_barrier}).", "\033[1;36m")
            self.run_single_fast(clean_task, plan_msg, final_barrier=final_barrier, task_start_ts=task_start_ts)
            return

        # Tier 3: Heavy Multi-Agent Decomposition
        emit(
            "phase",
            phase="planning",
            progress=12,
            detail="Đang phân chia phân hệ chuyên trách..." if self.is_vi() else "Decomposing complex task...",
        )
        triage_prompt = (
            "Decompose this complex request into 2-3 focused parallel/sequential specialist tracks.\n"
            "Respect temporal dependencies ('sau đó', 'rồi', 'cuối cùng', 'then', 'after'): use parallel=false for dependent downstream stages so Stage N verifies before Stage N+1 runs.\n"
            "Never add a redundant verifier worker (Coordinator audits afterwards). Use parallel=true only for truly independent tracks.\n"
            f"CRITICAL: NEVER include lock/sleep commands inside worker tracks.\n"
            f"{self.language_instruction()}\n\n"
            f"USER REQUEST:\n{clean_task}\n\n"
            'Respond ONLY with JSON: {"mode":"multi","plan_summary":"1 concise sentence","success_criteria":"verification checks","collaborators":[{"role_name":"","prompt":"","parallel":true}]}'
        )
        router_model = self.fast_router_model(self.supervisor_model)
        ok, triage_raw, err, eff_coord, _ = self.run_agy("router", "Coordinator Plan", triage_prompt, router_model)
        if not ok:
            emit("task_error", message=err or ("Không thể lập kế hoạch." if self.is_vi() else "Failed to plan."))
            return

        triage = extract_json_block(triage_raw) or {}
        if triage.get("collaborators"):
            self.run_multi_agent(user_task, triage, eff_coord, final_barrier=final_barrier, task_start_ts=task_start_ts)
        else:
            self.run_single_fast(clean_task, str(triage.get("plan_summary") or clean_task), final_barrier=final_barrier, task_start_ts=task_start_ts)


def main():
    if len(sys.argv) < 3:
        print("Usage: ai_orchestrator.py <config_json> <log_path> [task_prompt]", file=sys.stderr)
        sys.exit(2)

    cfg = json.loads(sys.argv[1])
    log_path = sys.argv[2]
    task_prompt = sys.argv[3] if len(sys.argv) > 3 else ""

    orch = Orchestrator(cfg, log_path)
    orch.start_stdin_reader()

    if task_prompt:
        orch.run_task(task_prompt)
    else:
        while not orch.stop_requested:
            try:
                cmd = orch.inbox.get(timeout=0.5)
                if cmd.get("type") == "start":
                    orch.run_task(cmd.get("task", ""))
                    break
            except queue.Empty:
                continue


if __name__ == "__main__":
    main()
