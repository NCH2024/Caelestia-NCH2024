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
        self.cwd = config.get("cwd") or os.path.expanduser("~")

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

    def run_single_fast(self, user_task: str, plan_summary: str):
        """Tier 2 Fast Lane: One continuous cached `agy` session executes & verifies directly."""
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
                "VISUAL REAL-TIME CURSOR MODE ACTIVE (FAST LANE):\n"
                "- Use `caelestia-desktop` with `--agent \"Meow AI\"` (or `--agent Browser` / `--agent Control` in parallel tracks) so live Ghost Cursors track your work without blinking out.\n"
                "- SPEED RULE #1 — SKIP HOMEPAGE & SCREENSHOTS WHEN POSSIBLE: For YouTube/web searches, launch the direct search URL (`https://www.youtube.com/results?search_query=<url_encoded_query>` or Google search URL), then immediately run accent-insensitive OCR click: `caelestia-desktop click-text \"<title/artist keyword>\" --window firefox --wait 5 --agent \"Meow AI\"`!\n"
                "- SPEED RULE #2 — BATCH COMMANDS: Combine `launch ... && click-text ... --wait 5` (or `nexus openPage 0 && click-text \"Cinema\" --window quickshell --wait 2.5`) inside ONE shell call instead of separate turns!\n"
                "- FALLBACK ONLY: If `click-text` returns not found, run `caelestia-desktop screen --grid --fast --out /tmp/ai_screen.jpg --agent \"Meow AI\"` + `read_file` -> `click <x> <y> --agent \"Meow AI\"`."
            )
        else:
            desktop_rule = "Desktop GUI control (`caelestia-desktop`) is ALLOWED."
        exec_prompt = (
            "You are Meow AI executing a user request in ONE efficient session.\n"
            "Use your preloaded AGENTS.md system cheatsheet directly — DO NOT waste turns exploring config files when IPC commands are already known.\n"
            "Combine independent commands in one shell call where practical, execute cleanly, verify the final state once, and return structured JSON.\n"
            f"{desktop_rule}\n{self.language_instruction()}\n\n"
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
                # Model returned a clean plain markdown answer without JSON wrapper -> treat as complete
                emit("assistant_message", model=eff_m, title="Kết quả đã xác minh" if self.is_vi() else "Verified Result", text=out)
                emit("task_complete", progress=100, summary=out)
                self.logger.write("SINGLE FAST COMPLETED.", "\033[1;32m")
                return

            verdict = str(parsed.get("verdict") or "complete").lower()
            final_reply = str(parsed.get("final_reply") or out).strip()
            question = str(parsed.get("question_for_user") or "").strip()
            polish_hint = str(parsed.get("polish_hint") or "").strip()

            if verdict == "complete":
                emit("assistant_message", model=eff_m, title="Kết quả đã xác minh" if self.is_vi() else "Verified Result", text=final_reply)
                emit("task_complete", progress=100, summary=final_reply)
                self.logger.write("SINGLE FAST COMPLETED.", "\033[1;32m")
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
                f"Role: {rname}. Execute your assigned scope cleanly and verify outputs before reporting.\n"
                "Use preloaded AGENTS.md facts directly (no blind file exploration).\n\n"
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

    def run_multi_agent(self, user_task: str, triage: dict, eff_coord: str, final_barrier: str | None = None):
        """Tier 3 Heavy Engineering / Multi-Workstream Team + Coordinator Audit."""
        collaborators = (triage.get("collaborators") or [])[:3]
        if not collaborators:
            self.run_single_fast(user_task, str(triage.get("plan_summary") or ""))
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
            has_blocker = bool(re.search(r"\b(blocked|unable to|cannot|could not|failed to|chưa thể|không thể|bị khóa)\b", bundled.lower()))
            fast_synth = all_ok and not has_blocker
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
            r"^(?:mở|open)\s+equalizer$": ["qs", "-c", "caelestia", "ipc", "call", "nexus", "openPage", "5"],
        }
        for pat, cmd in app_map.items():
            if re.match(pat, low):
                subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
                return f"Đã mở theo yêu cầu (`{cmd[-1]}`)." if self.is_vi() else f"Launched `{cmd[-1]}`."

        return None

    def looks_heavy_engineering(self, user_task: str) -> bool:
        low = user_task.lower()
        return bool(
            len(user_task) > 180
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
        self.logger.write(f"USER REQUEST: {user_task}", "\033[1;34m")

        # Tier 0: Zero-LLM Instant Local Execution (<100ms, 0 tokens)
        fast_ans = self.try_local_fast_path(user_task)
        if fast_ans is not None:
            self.logger.write(f"Tier 0 local fast-path hit -> {fast_ans}", "\033[1;36m")
            emit("phase", phase="done", progress=100, detail=fast_ans)
            emit("assistant_message", model="local-fast", title="Thực thi tức thì" if self.is_vi() else "Instant Action", text=fast_ans)
            emit("task_complete", progress=100, summary=fast_ans)
            return

        # Fast 0ms heuristic bypasses extra cold Router LLM call for 90% of requests!
        if self.looks_pure_qa(user_task):
            emit("phase", phase="working", progress=35, detail="Đang trả lời nhanh..." if self.is_vi() else "Answering...")
            qa_model = self.fast_router_model(self.supervisor_model)
            ok, ans, err, eff_m, _ = self.run_agy(
                "router",
                "Meow AI",
                f"{self.language_instruction()}\nAnswer concisely and accurately in Markdown without running unnecessary tools:\n{user_task}",
                qa_model,
            )
            if not ok:
                emit("task_error", message=err or "Error")
                return
            emit("assistant_message", model=eff_m, title="Trả lời" if self.is_vi() else "Response", text=ans)
            emit("task_complete", progress=100, summary=ans)
            self.logger.write("DIRECT FAST QA COMPLETED.", "\033[1;32m")
            return

        if not self.looks_heavy_engineering(user_task):
            # When visual cursor mode is active and request spans Browser + Control/App surfaces simultaneously,
            # launch 2 parallel visual cursor tracks (`Browser` + `Control`) directly (0ms router overhead!)
            low = user_task.lower()
            has_browser = bool(re.search(r"\b(trình duyệt|browser|firefox|youtube|google|web|bài báo|trang web)\b", low))
            has_control = bool(re.search(r"\b(chế độ|mode|cài đặt|settings|nexus|bảng điều khiển|độ sáng|âm lượng|equalizer|phần mềm|thống kê)\b", low))
            final_barrier = None
            if re.search(r"\b(cuối cùng|sau cùng|cuối|finally|then lock).*?(khóa màn hình|khóa máy|lock screen|lock)\b", low) or re.search(r"\b(khóa màn hình|lock screen)\b", low):
                final_barrier = "lock"
            if self.allow_desktop and self.prefer_visual_cursor and has_browser and has_control:
                self.logger.write(f"Local router -> parallel multi-cursor GUI tracks (Browser + Control, barrier={final_barrier}).", "\033[1;36m")
                barrier_warn = (
                    " CRITICAL: Do NOT lock/sleep the screen yet — screen lock is handled automatically AFTER all tracks finish!"
                    if final_barrier
                    else ""
                )
                multi_triage = {
                    "plan_summary": (
                        "Đang điều phối đồng thời 2 con trỏ AI thao tác trên Trình duyệt và Bảng điều khiển."
                        if self.is_vi()
                        else "Operating Browser and Control Panel simultaneously with live visual cursors."
                    ),
                    "success_criteria": "Both the browser action and control-panel/app action complete visually and are verified.",
                    "collaborators": [
                        {
                            "role_name": "Browser",
                            "prompt": (
                                "Handle ONLY the browser/web portion visually in 1-2 batched commands using `--agent Browser`: "
                                "launch `https://www.youtube.com/results?search_query=<query>` (for YouTube) with `caelestia-desktop launch firefox \"...\" --agent Browser`, wait briefly, then run `caelestia-desktop click-text \"<song/title keyword>\" --window firefox --wait 5 --agent Browser` (NO homepage screenshots!). "
                                "After clicking a YouTube video, wait 1.5s and verify Firefox audio via `pactl list sink-inputs | grep -E \"application.name|Corked\"` (if missing or `Corked: yes`, run `caelestia-desktop focus firefox --agent Browser && caelestia-desktop key k --agent Browser` and re-check `pactl`). NEVER use `playerctl` for Firefox!"
                                + barrier_warn
                            ),
                            "parallel": True,
                        },
                        {
                            "role_name": "Control",
                            "prompt": (
                                "Handle ONLY settings/modes/audio/brightness/app actions visually in 1 batched shell call using `--agent Control`: "
                                "e.g., `caelestia shell nexus openPage 0 && caelestia-desktop click-text \"Cinema\" --window quickshell --wait 2.5 --agent Control && brightnessctl set 100%`, and verify final state (`extra.json`, `brightnessctl get`, etc.)."
                                + barrier_warn
                            ),
                            "parallel": True,
                        },
                    ],
                }
                self.run_multi_agent(user_task, multi_triage, self.supervisor_model, final_barrier=final_barrier)
                return

            # Direct Unified Single-Session Execution (saves 4-6s + ~10k tokens vs separate Router boot)
            plan_msg = (
                "Đang thực thi trực tiếp trong 1 phiên hợp nhất..."
                if self.is_vi()
                else "Executing in single unified session..."
            )
            self.logger.write("Local router -> unified single fast lane (skipped extra Router boot).", "\033[1;36m")
            self.run_single_fast(user_task, plan_msg)
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
            "Never add a redundant verifier worker (Coordinator audits afterwards). Use parallel=true for independent tracks.\n"
            f"{self.language_instruction()}\n\n"
            f"USER REQUEST:\n{user_task}\n\n"
            'Respond ONLY with JSON: {"mode":"multi","plan_summary":"1 concise sentence","success_criteria":"verification checks","collaborators":[{"role_name":"","prompt":"","parallel":true}]}'
        )
        router_model = self.fast_router_model(self.supervisor_model)
        ok, triage_raw, err, eff_coord, _ = self.run_agy("router", "Coordinator Plan", triage_prompt, router_model)
        if not ok:
            emit("task_error", message=err or ("Không thể lập kế hoạch." if self.is_vi() else "Failed to plan."))
            return

        triage = extract_json_block(triage_raw) or {}
        if triage.get("collaborators"):
            self.run_multi_agent(user_task, triage, eff_coord)
        else:
            self.run_single_fast(user_task, str(triage.get("plan_summary") or user_task))


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
