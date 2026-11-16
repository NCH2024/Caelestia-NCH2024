#!/usr/bin/env python3
"""
Caelestia AI Task Automation Orchestrator.

Flow:
1. Primary Coordinator triages the user's request:
   - "direct": Simple Q&A / explanation -> answers directly in 1 turn without spawning workers.
   - "delegate": Complex or actionable task -> dynamically allocates 1..4 Collaborators
     (e.g. B, C, D, E equivalents scaled to task size/complexity) in parallel/sequential order.
2. Collaborators execute silently in background with full tool & desktop permissions
   while emitting concise live milestone progress into the Chat UI.
3. Primary Coordinator independently verifies collaborator outputs and synthesizes ONE
   clean final response directly to the user (never dumping raw collaborator logs to chat),
   or asks confirmation if verification detects an issue.
"""

from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
import queue
import re
import subprocess
import sys
import threading
from datetime import datetime
from pathlib import Path

QUOTA_PATTERNS = re.compile(
    r"(quota|rate[_\s-]?limit|resource[_\s-]?exhausted|429|too many requests|"
    r"capacity|exhausted|usage limit|limit reached|exceeded your)",
    re.IGNORECASE,
)

AUTH_PATTERNS = re.compile(
    r"(not logged into antigravity|authentication required|unauthenticated|"
    r"unauthorized|please log in|sign in required)",
    re.IGNORECASE,
)

_EMIT_LOCK = threading.Lock()


def emit(event_type: str, **payload):
    msg = {"type": event_type, "ts": datetime.now().strftime("%H:%M:%S"), **payload}
    with _EMIT_LOCK:
        sys.stdout.write(json.dumps(msg, ensure_ascii=False) + "\n")
        sys.stdout.flush()


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
        self.inbox = queue.Queue()
        self.stop_requested = False
        self.active_procs = set()
        self.proc_lock = threading.Lock()
        self.model_lock = threading.Lock()

        self.supervisor_model = config.get("supervisorModel", "") or "gemini-4-hydrogen-high"
        self.worker_model = config.get("workerModel", "") or "gemini-4-argon-high"
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

    def pick_next_model(self, failed_model: str, tried: set) -> str | None:
        candidates = list(self.fallback_models) + [
            "gemini-4-hydrogen-high",
            "gemini-4-argon-high",
            "claude-sonnet-5-5-high",
            "gemini-3.8-flash-high",
            "gemini-3.8-flash-medium",
            "gpt-oss-120b-medium",
        ]
        for c in candidates:
            if c and c != failed_model and c not in tried:
                return c
        return None

    def desktop_context(self) -> str:
        if not self.allow_desktop:
            return "Desktop/GUI actions are disabled; restrict execution to CLI, files, and shell tasks."
        yd_note = (
            "ydotoold daemon is ACTIVE (you can simulate keyboard/mouse input with `ydotool`)."
            if self.ydotool_active
            else "ydotoold is inactive (use Hyprland IPC, app CLIs, xdg-open, wl-copy, grim; or start `systemctl --user start ydotool` if mouse/keyboard synthesis is required)."
        )
        return (
            "ENVIRONMENT & DESKTOP AUTOMATION CAPABILITIES:\n"
            f"- OS: Arch Linux on Hyprland Wayland desktop (user home: {self.cwd})\n"
            "- Launch GUI apps cleanly in background: `setsid -f hyprctl dispatch exec \"<command>\" >/dev/null 2>&1` or `nohup gtk-launch <desktop_id> >/dev/null 2>&1 &`\n"
            "- Inspect/focus windows: `hyprctl clients -j`, `hyprctl activewindow -j`, `hyprctl dispatch focuswindow ...`, `hyprctl dispatch workspace ...`\n"
            "- Open URLs/files: `setsid -f xdg-open \"<url_or_path>\" >/dev/null 2>&1`\n"
            "- Clipboard: `wl-copy` / `wl-paste`\n"
            "- Capture desktop screenshot for inspection: `grim /tmp/ai_screen_check.png`\n"
            f"- Human-like input synthesis: {yd_note}\n"
        )

    def run_agy(
        self,
        role: str,
        worker_label: str,
        prompt: str,
        model: str,
    ) -> tuple[bool, str, str, str]:
        tried = set()
        current_model = model

        while not self.stop_requested:
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
            if (quota_hit or (failed and QUOTA_PATTERNS.search(output_text + "\n" + err_text))) and self.auto_switch:
                next_model = self.pick_next_model(current_model, tried)
                if next_model:
                    self.logger.write(
                        f"Quota / rate limit reached on '{current_model}'. Auto-switching to '{next_model}'...",
                        "\033[1;33m",
                    )
                    emit(
                        "model_switch",
                        role=role,
                        fromModel=current_model,
                        toModel=next_model,
                        reason="Quota or rate limit detected",
                    )
                    with self.model_lock:
                        if role == "coordinator":
                            self.supervisor_model = next_model
                        else:
                            self.worker_model = next_model
                    current_model = next_model
                    continue

            if failed:
                self.logger.write(f"[{worker_label}] exited with code {proc.returncode}: {err_text}", "\033[1;31m")
                return False, output_text, err_text or f"agy exited with code {proc.returncode}", current_model

            return True, output_text, err_text, current_model

        return False, "", "Stopped by user.", current_model

    def run_collaborators(self, user_task: str, specs: list[dict]) -> list[dict]:
        """Run 1..4 specialists cleanly in parallel or sequence based on spec['parallel']."""
        if not specs:
            return []

        results = []
        # Cap at 4 specialists max
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
            with self.model_lock:
                m = self.worker_model
            ok_w, out_w, err_w, eff_m = self.run_agy("executor", rname, full_prompt, m)
            return {
                "role_name": rname,
                "ok": ok_w,
                "output": out_w,
                "error": err_w,
                "model": eff_m,
            }

        if parallel_specs and not self.stop_requested:
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
            # Pass brief context from prior parallel collaborators so dependent steps (e.g. QA/integration) see what changed
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
            progress=15,
            detail="Đang phân tích mức độ yêu cầu..." if self.is_vi() else "Classifying request complexity...",
        )

        # Stage 1: Smart Triage (Direct answer vs 1..4 Collaborators)
        triage_prompt = (
            "You are Meow AI (Primary Coordinator) on a local Arch Linux + Hyprland desktop.\n"
            "First, classify the USER REQUEST carefully:\n"
            '- Use `"mode": "direct"` for simple questions, definitions, general knowledge, quick explanations, code snippets, math, or conversation that do NOT require inspecting files, running commands, editing configs/code, or controlling desktop apps. Provide `"direct_answer"` right away.\n'
            '- Use `"mode": "delegate"` ONLY when execution, live inspection, file editing, UI/code building, or desktop automation is required. Dynamically scale `"collaborators"` between 1 and 4 specialized subtasks according to task complexity:\n'
            "  * Small single-step action (check uptime/disk, open app, quick read): 1 collaborator.\n"
            "  * Moderate task (code fix + test, or multi-command diagnostics): 2 collaborators.\n"
            "  * Complex software/UI engineering (architecture, UI components, backend/service logic, verification): 3-4 collaborators (set `parallel: true` for independent parts, `parallel: false` for final integration/QA checks).\n\n"
            f"{self.language_instruction()}\n\n"
            f"{self.desktop_context()}\n"
            f"USER REQUEST:\n{user_task}\n\n"
            "Respond ONLY with valid JSON:\n"
            "{\n"
            '  "mode": "direct" or "delegate",\n'
            '  "direct_answer": "Full helpful response if mode=direct, else empty string",\n'
            '  "plan_summary": "1 concise sentence explaining what you are mobilizing if mode=delegate",\n'
            '  "success_criteria": "Exact checks to verify after execution if mode=delegate",\n'
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
            self.logger.write("Triage -> direct answer (no workers needed).", "\033[1;36m")
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
        plan_summary = str(triage.get("plan_summary") or "").strip()
        if not plan_summary:
            plan_summary = (
                f"Đang điều phối {collab_count} luồng xử lý chuyên trách để thực hiện yêu cầu."
                if self.is_vi()
                else f"Coordinating {collab_count} specialist track(s) to complete your request."
            )
        success_criteria = str(triage.get("success_criteria") or "All requested actions succeed cleanly without errors.")

        # Subtle plan line inside Progress status instead of noisy chat bubble
        role_names = ", ".join(str(c.get("role_name", "Task")) for c in collaborators)
        emit(
            "assistant_message",
            model=eff_coord,
            title=f"Điều phối ({collab_count} phân hệ)" if self.is_vi() else f"Plan ({collab_count} track{'s' if collab_count > 1 else ''})",
            text=f"{plan_summary}\n[{role_names}]",
        )
        self.logger.write(f"Triage -> delegate ({collab_count}): {role_names}", "\033[35m")

        max_rounds = 3
        current_specs = collaborators

        for round_idx in range(1, max_rounds + 1):
            if self.stop_requested:
                break

            emit(
                "phase",
                phase="working",
                progress=52,
                detail=(
                    f"Đang thực thi {len(current_specs)} phân hệ (Lượt {round_idx})..."
                    if self.is_vi()
                    else f"Executing {len(current_specs)} track(s) (Round {round_idx})..."
                ),
            )

            collab_results = self.run_collaborators(user_task, current_specs)
            if self.stop_requested:
                break

            emit(
                "phase",
                phase="verifying",
                progress=85,
                detail="Đang kiểm chứng & tổng hợp câu trả lời..." if self.is_vi() else "Verifying & synthesizing final answer...",
            )
            self.logger.write("Coordinator verifying collaborator outputs and synthesizing reply...", "\033[1;35m")

            bundled_reports = "\n\n".join(
                f"=== {r['role_name']} ({'SUCCESS' if r['ok'] else 'ERROR: ' + r['error']}) ===\n{r['output']}"
                for r in collab_results
            )

            synthesis_prompt = (
                "You are Meow AI (Primary Coordinator). Your specialist collaborators have finished executing the user's task.\n"
                "IMPORTANT:\n"
                "1. The user did NOT see the raw collaborator reports — YOU are responsible for verifying actual files/system/outputs "
                "(run quick verification checks if appropriate) and writing the ONE authoritative final reply to the user.\n"
                "2. Compare everything strictly against USER REQUEST and SUCCESS CRITERIA.\n"
                "3. If valid=true, summarize exact verified metrics, files changed, or actions performed cleanly and directly in `final_reply` "
                "(NEVER mention 'collaborators', 'Agent A', 'Agent B', 'Agent C').\n"
                "4. If execution failed, missed key requirements, or is risky/incomplete, set `valid=false` and write `question_for_user`.\n\n"
                f"{self.language_instruction()}\n\n"
                f"USER REQUEST:\n{user_task}\n\n"
                f"SUCCESS CRITERIA:\n{success_criteria}\n\n"
                f"INTERNAL SPECIALIST OUTPUTS:\n{bundled_reports}\n\n"
                "Respond ONLY with valid JSON:\n"
                "{\n"
                '  "valid": true or false,\n'
                '  "final_reply": "Complete synthesized answer directly for the user based on verified facts",\n'
                '  "question_for_user": "If valid is false, ask user clearly whether to retry/accept/abort; else empty",\n'
                '  "suggested_fix_prompt": "If valid is false, concrete fix scope for retry; else empty"\n'
                "}"
            )

            ok_v, synth_raw, err_v, eff_coord2 = self.run_agy("coordinator", "Coordinator Verify", synthesis_prompt, self.supervisor_model)
            if not ok_v:
                emit("task_error", message=err_v or ("Kiểm chứng thất bại." if self.is_vi() else "Verification failed."))
                return

            synth = extract_json_block(synth_raw) or {}
            is_valid = bool(synth.get("valid", all(r["ok"] for r in collab_results)))
            final_reply = str(synth.get("final_reply") or synth_raw or "Done.").strip()
            question = str(synth.get("question_for_user") or "").strip()
            fix_prompt = str(synth.get("suggested_fix_prompt") or "").strip()

            self.logger.write(f"Coordinator Verification -> valid={is_valid}", "\033[1;35m")

            if is_valid:
                emit(
                    "assistant_message",
                    model=eff_coord2,
                    title="Kết quả đã xác minh" if self.is_vi() else "Verified Result",
                    text=final_reply,
                )
                emit("task_complete", progress=100, summary=final_reply)
                self.logger.write("TASK COMPLETED SUCCESSFULLY.", "\033[1;32m")
                return

            if not self.ask_on_invalid:
                emit("task_error", message=final_reply)
                return

            fallback_q = (
                f"Hệ thống phát hiện vấn đề khi đối chiếu kết quả:\n{final_reply}\n\nBạn muốn chạy lại để khắc phục, chấp nhận kết quả hiện tại, hay hủy?"
                if self.is_vi()
                else f"Verification detected an issue:\n{final_reply}\n\nWould you like to retry with fixes, accept anyway, or abort?"
            )
            prompt_question = question or fallback_q
            emit(
                "phase",
                phase="waiting_user",
                progress=75,
                detail="Đang chờ bạn xác nhận..." if self.is_vi() else "Waiting for your confirmation...",
            )
            emit(
                "user_question",
                model=eff_coord2,
                verification=final_reply,
                question=prompt_question,
                suggestedFix=fix_prompt,
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
                        guidance = user_text or fix_prompt or "Fix all issues reported during verification."
                        current_specs = [{
                            "role_name": "Recovery Executor",
                            "prompt": (
                                f"Previous verification failed:\n{final_reply}\n\n"
                                f"USER / COORDINATOR GUIDANCE:\n{guidance}\n\n"
                                "Fix everything cleanly and verify outputs."
                            ),
                            "parallel": True,
                        }]
                        break

        emit("task_error", message="Đã vượt quá số lượt thử lại." if self.is_vi() else "Reached maximum retry rounds.")


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
