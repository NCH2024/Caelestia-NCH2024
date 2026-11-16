#!/usr/bin/env python3
"""
Caelestia AI Task Automation Orchestrator.

Key capabilities:
1. Persistent Quota Cooldown Cache (~/.cache/caelestia/ai_model_cooldowns.json):
   Parses reset times (`Resets in XhYmZs`) on 429/RESOURCE_EXHAUSTED so exhausted
   models are immediately skipped across threads and future requests (zero 429 thrashing).
2. Smart Triage (`direct` vs `delegate`):
   - `direct`: Simple Q&A -> Coordinator replies immediately without spawning workers.
   - `delegate`: Scales 1..4 specialists dynamically (parallel or sequential).
3. Autonomous Polish-Until-Verified Loop:
   Coordinator audits collaborator work as `complete`, `needs_polish` (auto-fixes up to 2 passes),
   or `needs_user_input` (asks confirmation inline in Chat), then synthesizes ONE clean reply.
4. Pixel-Accurate Desktop Computer-Use Bridge (`caelestia-desktop`):
   Supports GUI workflows across browsers and desktop apps with grid screenshots, calibrated
   cursor clicks, UTF-8/Vietnamese typing, hotkeys, and OCR.
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
        return 1800  # 30 minutes default cooldown on unspecified rate limit
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
        self.ask_on_invalid = bool(config.get("askOnInvalidResult", True))
        self.chat_language = str(config.get("chatLanguage", "vi") or "vi").lower()
        self.cwd = config.get("cwd") or os.path.expanduser("~")
        self.ydotool_active = self._check_ydotool()

    def _check_ydotool(self) -> bool:
        try:
            res = subprocess.run(
                ["systemctl", "--user", "is-active", "ydotool"],
                capture_output=True,
                text=True,
                timeout=2,
            )
            return res.returncode == 0
        except Exception:
            return False

    def is_vi(self) -> bool:
        return self.chat_language == "vi"

    def language_instruction(self) -> str:
        if self.chat_language == "vi":
            return (
                "LANGUAGE REQUIREMENT (STRICT): You MUST write ALL user-facing answers, plans, summaries, "
                "and confirmation questions in clear, natural Vietnamese (Tiếng Việt). "
                "Never refer to internal roles as 'Agent A', 'Agent B', 'Agent C'; speak cohesively as Meow AI."
            )
        elif self.chat_language == "en":
            return (
                "LANGUAGE REQUIREMENT (STRICT): Write ALL user-facing answers, plans, summaries, "
                "and confirmation questions in clear, concise English. "
                "Never refer to internal roles as 'Agent A', 'Agent B', 'Agent C'; speak cohesively as Meow AI."
            )
        return (
            "LANGUAGE REQUIREMENT: Match the exact language of the USER REQUEST for all answers, summaries, "
            "and confirmation questions. Never expose internal 'Agent A/B/C' labels."
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
            cooled, rem = self.cooldowns.is_cooled_down(cand)
            if not cooled:
                return cand
        return None

    def resolve_initial_model(self, role: str, preferred: str) -> str | None:
        with self.model_lock:
            current = self.supervisor_model if role == "coordinator" else self.worker_model
        cooled, rem = self.cooldowns.is_cooled_down(current)
        if not cooled:
            return current
        healthy = self.pick_healthy_model(preferred, set())
        if healthy:
            self.logger.write(
                f"Skipping '{current}' (quota cooldown {format_duration(rem)} left); using healthy model '{healthy}'.",
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

    def desktop_context(self) -> str:
        if not self.allow_desktop:
            return "Desktop/GUI actions are disabled; restrict execution to CLI, files, and shell tasks."
        return (
            "ENVIRONMENT & COMPUTER-USE TOOLING (`caelestia-desktop`):\n"
            f"- OS: Arch Linux + Hyprland Wayland desktop (home: {self.cwd}, ydotoold: {'ACTIVE' if self.ydotool_active else 'auto-starts on call'})\n"
            "- Use `caelestia-desktop` in bash commands for ALL GUI / browser / app control:\n"
            "  * `caelestia-desktop windows` -> JSON list of open windows (title, class, workspace, [x,y], [w,h])\n"
            "  * `caelestia-desktop launch firefox \"https://...\"` (or any GUI app) -> launches cleanly detached\n"
            "  * `caelestia-desktop focus firefox` -> focuses window cleanly across Lua/standard Hyprland\n"
            "  * `caelestia-desktop screen --grid --out /tmp/ai_screen.png` -> captures screen with labeled pixel grid; inspect with `view_file` to find exact (x, y) click targets!\n"
            "  * `caelestia-desktop click <x> <y>` / `--double` / `--button right` -> closed-loop calibrated cursor click (within 3px accuracy)\n"
            "  * `caelestia-desktop move <x> <y>` / `caelestia-desktop scroll -5 --x <x> --y <y>`\n"
            "  * `caelestia-desktop type \"nội dung tiếng Việt hoặc URL\" --enter` -> full UTF-8 / Vietnamese typing via clipboard paste\n"
            "  * `caelestia-desktop key ctrl+l` / `ctrl+t` / `ctrl+c` / `ctrl+v` / `alt+tab` / `enter`\n"
            "  * `caelestia-desktop ocr [--region \"x,y wxh\"]` -> fast tesseract text extraction from screen\n"
            "- Note: On this Lua-wrapped Hyprland setup, prefer `caelestia-desktop` over raw `hyprctl dispatch` or raw `ydotool mousemove`.\n"
        )

    def run_agy(
        self,
        role: str,
        worker_label: str,
        prompt: str,
        preferred_model: str,
    ) -> tuple[bool, str, str, str]:
        tried = set()
        current_model = self.resolve_initial_model(role, preferred_model)

        if not current_model:
            return False, "", "Tất cả model đều đang trong thời gian chờ quota. Hãy kiểm tra lại hoặc xóa cooldown trong Settings -> AI Automation.", preferred_model

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
            if self.full_perms:
                cmd.append("--dangerously-skip-permissions")

            role_color = "\033[1;35m" if role == "coordinator" else "\033[1;32m"
            self.logger.write(
                f"[{worker_label}] starting ({current_model})"
                + (" [FULL PERMS]" if self.full_perms else ""),
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
                    status = res.get("status", "")
                    final_result_text = res.get("response", "")
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
                return False, output_text, "Stopped by user.", current_model

            if auth_hit:
                self.logger.write("Antigravity CLI authentication required!", "\033[1;31m")
                return False, output_text, (
                    "Chưa đăng nhập Antigravity CLI. Vui lòng mở Settings -> AI Automation để đăng nhập."
                    if self.is_vi()
                    else "Antigravity CLI is not authenticated. Open Settings -> AI Automation to sign in."
                ), current_model

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
                        continue
                return False, output_text, (
                    f"Hết hạn mức trên tất cả model khả dụng (tạm nghỉ ~{rem_str})."
                    if self.is_vi()
                    else f"All available models reached quota limits (resets in ~{rem_str})."
                ), current_model

            if failed:
                self.logger.write(f"[{worker_label}] exited with code {proc.returncode}: {err_text}", "\033[1;31m")
                return False, output_text, err_text or f"agy exited with code {proc.returncode}", current_model

            return True, output_text, err_text, current_model

        return False, "", "Stopped by user.", preferred_model

    def run_collaborators(self, user_task: str, specs: list[dict]) -> list[dict]:
        if not specs:
            return []

        results = []
        specs = specs[:4]
        parallel_specs = [s for s in specs if s.get("parallel", True)]
        seq_specs = [s for s in specs if not s.get("parallel", True)]

        def execute_one(idx: int, spec: dict) -> dict:
            rname = str(spec.get("role_name") or f"Specialist {idx + 1}")
            sub_prompt = str(spec.get("prompt") or user_task)
            full_prompt = (
                f"You are an internal execution specialist ({rname}) assisting the Coordinator.\n"
                "Your findings and work will be verified and synthesized by the Coordinator before replying to the user.\n"
                "Execute your assigned scope thoroughly and concisely report exact commands run, files touched, and concrete facts.\n\n"
                f"{self.desktop_context()}\n"
                f"USER REQUEST:\n{user_task}\n\n"
                f"ASSIGNED SCOPE ({rname}):\n{sub_prompt}"
            )
            ok_w, out_w, err_w, eff_m = self.run_agy("executor", rname, full_prompt, self.worker_model)
            return {
                "role_name": rname,
                "ok": ok_w,
                "output": out_w,
                "error": err_w,
                "model": eff_m,
            }

        if parallel_specs and not self.stop_requested:
            # Resolve initial shared worker model BEFORE spawning threads so N threads don't stampede a dead model
            self.resolve_initial_model("executor", self.worker_model)
            with ThreadPoolExecutor(max_workers=min(4, len(parallel_specs))) as pool:
                fut_map = {
                    pool.submit(execute_one, i, s): i
                    for i, s in enumerate(parallel_specs)
                }
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
                f"[{r['role_name']} ({'OK' if r['ok'] else 'ERR'})]:\n{r['output'][:2000]}"
                for r in results
            )
            enriched = dict(s)
            if prior_ctx:
                enriched["prompt"] = f"{s.get('prompt', '')}\n\nPREVIOUS SPECIALIST RESULTS:\n{prior_ctx}"
            results.append(execute_one(len(parallel_specs) + j, enriched))

        return results

    def run_task(self, user_task: str):
        self.logger.write(f"USER REQUEST: {user_task}", "\033[1;34m")
        emit(
            "phase",
            phase="planning",
            progress=12,
            detail="Đang phân tích yêu cầu..." if self.is_vi() else "Classifying request...",
        )

        triage_prompt = (
            "You are Meow AI (Primary Coordinator) on a local Arch Linux + Hyprland desktop.\n"
            "Classify the USER REQUEST carefully:\n"
            '- Use `"mode": "direct"` for simple questions, definitions, general knowledge, quick code snippets, math, or conversation needing NO commands, file inspection, editing, or GUI control.\n'
            '- Use `"mode": "delegate"` whenever execution, file/code inspection, feature building, testing, or GUI/browser desktop control (`caelestia-desktop`) is needed. Scale `"collaborators"` cleanly from 1 to 4:\n'
            "  * Small read/check/open task: 1 collaborator.\n"
            "  * Moderate fix + verification, or browser search + summary app: 2 collaborators (`Research/Action`, `Verification/Summary`).\n"
            "  * Complex feature development: 3–4 collaborators (`Architecture/UI`, `Backend/Service`, `Integration/QA`) with `parallel: false` for QA depending on prior edits.\n\n"
            f"{self.language_instruction()}\n\n"
            f"{self.desktop_context()}\n"
            f"USER REQUEST:\n{user_task}\n\n"
            "Respond ONLY with valid JSON:\n"
            "{\n"
            '  "mode": "direct" or "delegate",\n'
            '  "direct_answer": "Full helpful response if mode=direct, else empty string",\n'
            '  "plan_summary": "1 concise sentence explaining what Meow AI is orchestrating if mode=delegate",\n'
            '  "success_criteria": "Exact checks to verify perfection if mode=delegate",\n'
            '  "collaborators": [\n'
            '    {"role_name": "Short role title", "prompt": "Detailed actionable instruction", "parallel": true}\n'
            "  ]\n"
            "}"
        )

        ok, triage_raw, err, eff_coord = self.run_agy("coordinator", "Coordinator", triage_prompt, self.supervisor_model)
        if not ok:
            emit("task_error", message=err or ("Không thể phân tích yêu cầu." if self.is_vi() else "Failed to analyze request."))
            return

        triage = extract_json_block(triage_raw) or {}
        mode = str(triage.get("mode") or "delegate").lower()

        if mode == "direct" and triage.get("direct_answer"):
            answer = str(triage["direct_answer"]).strip()
            self.logger.write("Triage -> direct answer.", "\033[1;36m")
            emit(
                "assistant_message",
                model=eff_coord,
                title="Trả lời trực tiếp" if self.is_vi() else "Direct Response",
                text=answer,
            )
            emit("task_complete", progress=100, summary=answer)
            self.logger.write("DIRECT RESPONSE COMPLETED.", "\033[1;32m")
            return

        collaborators = triage.get("collaborators") or []
        if not isinstance(collaborators, list) or len(collaborators) == 0:
            collaborators = [{"role_name": "Executor", "prompt": user_task, "parallel": True}]
        collaborators = collaborators[:4]

        collab_count = len(collaborators)
        plan_summary = str(triage.get("plan_summary") or "").strip() or (
            f"Đang điều phối {collab_count} luồng xử lý." if self.is_vi() else f"Coordinating {collab_count} execution track(s)."
        )
        success_criteria = str(triage.get("success_criteria") or "All requested changes and checks succeed cleanly without errors.")
        role_names = ", ".join(str(c.get("role_name", "Task")) for c in collaborators)
        emit(
            "assistant_message",
            model=eff_coord,
            title=f"Điều phối ({collab_count} phân hệ)" if self.is_vi() else f"Plan ({collab_count} track{'s' if collab_count > 1 else ''})",
            text=f"{plan_summary}\n[{role_names}]",
        )
        self.logger.write(f"Triage -> delegate ({collab_count}): {role_names}", "\033[35m")

        # Autonomous polish loop + optional user confirmation
        max_auto_polish = 2
        polish_used = 0
        max_total_rounds = 4
        current_specs = collaborators
        accumulated_notes = []

        for round_idx in range(1, max_total_rounds + 1):
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
                accumulated_notes.append(
                    f"[Round {round_idx} • {r['role_name']} ({'SUCCESS' if r['ok'] else 'ERROR: ' + r['error']})]\n{r['output']}"
                )

            emit(
                "phase",
                phase="verifying",
                progress=86,
                detail="Đang kiểm chứng & tổng hợp..." if self.is_vi() else "Verifying & synthesizing outcome...",
            )
            self.logger.write("Coordinator verifying collaborator outputs...", "\033[1;35m")

            bundled_reports = "\n\n".join(accumulated_notes[-6:])

            synthesis_prompt = (
                "You are Meow AI (Primary Coordinator). The background execution specialists finished Round "
                f"{round_idx} (autonomous polish remaining: {max_auto_polish - polish_used}).\n"
                "Verify actual files, lint/test outputs, or desktop window state yourself using tools if appropriate, and choose ONE verdict:\n"
                '1. `"complete"`: Everything requested is genuinely verified, clean, and ready for the user. Write a polished `final_reply` directly to the user.\n'
                '2. `"needs_polish"`: ONLY if an objective error/lint failure/incomplete detail exists that you can fix automatically right now without bothering the user AND autonomous polish remains > 0! Provide `polish_prompt` with exact fix instructions.\n'
                '3. `"needs_user_input"`: Genuine ambiguity, external blocker (quota/missing login/destructive action), or still failing after auto-polish. Write `question_for_user`.\n\n'
                "CRITICAL: Never mention 'Agent A/B/C' or internal collaborators in `final_reply`.\n\n"
                f"{self.language_instruction()}\n\n"
                f"USER REQUEST:\n{user_task}\n\n"
                f"SUCCESS CRITERIA:\n{success_criteria}\n\n"
                f"INTERNAL SPECIALIST OUTPUTS:\n{bundled_reports}\n\n"
                "Respond ONLY with valid JSON:\n"
                "{\n"
                '  "verdict": "complete" | "needs_polish" | "needs_user_input",\n'
                '  "final_reply": "Complete synthesized response for user if verdict=complete, or issue summary otherwise",\n'
                '  "polish_prompt": "If verdict=needs_polish, exact instructions for fixer specialist",\n'
                '  "question_for_user": "If verdict=needs_user_input, clear question for user"\n'
                "}"
            )

            ok_v, synth_raw, err_v, eff_coord2 = self.run_agy("coordinator", "Coordinator Verify", synthesis_prompt, self.supervisor_model)
            if not ok_v:
                emit("task_error", message=err_v or ("Kiểm chứng thất bại." if self.is_vi() else "Verification failed."))
                return

            synth = extract_json_block(synth_raw) or {}
            verdict = str(synth.get("verdict") or ("complete" if all(r["ok"] for r in collab_results) else "needs_user_input")).lower()
            final_reply = str(synth.get("final_reply") or synth_raw or "Done.").strip()
            polish_prompt = str(synth.get("polish_prompt") or "").strip()
            question = str(synth.get("question_for_user") or "").strip()

            self.logger.write(f"Coordinator Verdict -> {verdict}", "\033[1;35m")

            if verdict == "complete":
                emit(
                    "assistant_message",
                    model=eff_coord2,
                    title="Kết quả đã xác minh" if self.is_vi() else "Verified Result",
                    text=final_reply,
                )
                emit("task_complete", progress=100, summary=final_reply)
                self.logger.write("TASK COMPLETED SUCCESSFULLY.", "\033[1;32m")
                return

            if verdict == "needs_polish" and polish_used < max_auto_polish and polish_prompt:
                polish_used += 1
                self.logger.write(f"Auto-polish #{polish_used}: {polish_prompt[:140]}", "\033[1;36m")
                emit(
                    "engine_step",
                    worker="Coordinator QA",
                    step=polish_used,
                    detail=f"Tự động tối ưu & sửa lỗi (Vòng {polish_used})" if self.is_vi() else f"Auto-polish & fix pass #{polish_used}",
                )
                current_specs = [{
                    "role_name": f"Polish & Fix #{polish_used}",
                    "prompt": polish_prompt,
                    "parallel": True,
                }]
                continue

            if not self.ask_on_invalid:
                emit("task_error", message=final_reply)
                return

            prompt_question = question or (
                f"Hệ thống phát hiện vấn đề cần bạn quyết định:\n{final_reply}\n\nBạn muốn thử lại, chấp nhận kết quả hiện tại, hay hủy?"
                if self.is_vi()
                else f"Verification flagged an issue:\n{final_reply}\n\nWould you like to retry, accept anyway, or abort?"
            )
            emit(
                "phase",
                phase="waiting_user",
                progress=80,
                detail="Đang chờ bạn xác nhận..." if self.is_vi() else "Waiting for your confirmation...",
            )
            emit(
                "user_question",
                model=eff_coord2,
                verification=final_reply,
                question=prompt_question,
                suggestedFix=polish_prompt,
            )
            self.logger.write(f"ASKING USER: {prompt_question}", "\033[1;33m")

            while not self.stop_requested:
                try:
                    reply = self.inbox.get(timeout=0.5)
                except queue.Empty:
                    continue

                rtype = reply.get("type")
                if rtype == "stop":
                    self.stop_requested = True
                    emit("task_error", message="Đã dừng theo yêu cầu." if self.is_vi() else "Stopped by user.")
                    return
                if rtype == "user_reply":
                    action = reply.get("action", "retry")
                    user_text = str(reply.get("text", "")).strip()
                    self.logger.write(f"USER REPLY ({action}): {user_text}", "\033[1;34m")

                    if action == "accept":
                        emit(
                            "assistant_message",
                            model=eff_coord2,
                            title="Kết quả đã xác nhận" if self.is_vi() else "Accepted Result",
                            text=final_reply,
                        )
                        emit("task_complete", progress=100, summary=final_reply)
                        return
                    elif action == "abort":
                        emit("task_error", message="Đã hủy theo xác nhận." if self.is_vi() else "Aborted by user.")
                        return
                    else:
                        guidance = user_text or polish_prompt or "Fix remaining issues and verify thoroughly."
                        current_specs = [{
                            "role_name": "Guided Fixer",
                            "prompt": f"Previous findings:\n{final_reply}\n\nUSER GUIDANCE:\n{guidance}\n\nApply fixes cleanly and verify.",
                            "parallel": True,
                        }]
                        break

        emit("task_error", message="Đã vượt quá số lượt tối đa." if self.is_vi() else "Reached maximum execution rounds.")


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
