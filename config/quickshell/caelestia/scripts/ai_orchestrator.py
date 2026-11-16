#!/usr/bin/env python3
"""
Caelestia AI Task Automation Orchestrator.

Runs a two-stage Coordinator -> Execution Engine loop using Antigravity CLI (`agy`)
with automatic quota/rate-limit model failover and live NDJSON progress events for QML UI.
"""

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


def emit(event_type: str, **payload):
    msg = {"type": event_type, "ts": datetime.now().strftime("%H:%M:%S"), **payload}
    sys.stdout.write(json.dumps(msg, ensure_ascii=False) + "\n")
    sys.stdout.flush()


class SessionLogger:
    def __init__(self, log_path: str):
        self.log_path = log_path
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
        with open(self.log_path, "a", encoding="utf-8") as f:
            f.write(line)

    def raw(self, text: str):
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
        self.current_proc = None
        self.proc_lock = threading.Lock()

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
                "LANGUAGE REQUIREMENT (STRICT): You MUST write ALL user-facing explanations, summaries, "
                "verification notes, and confirmation questions in clear, natural Vietnamese (Tiếng Việt). "
                "Do NOT refer to yourself as 'Agent A' or 'Agent B'; speak naturally as a unified AI assistant."
            )
        elif self.chat_language == "en":
            return (
                "LANGUAGE REQUIREMENT (STRICT): Write ALL user-facing explanations, summaries, "
                "verification notes, and confirmation questions in clear, concise English. "
                "Do NOT refer to yourself as 'Agent A' or 'Agent B'; speak naturally as a unified AI assistant."
            )
        return (
            "LANGUAGE REQUIREMENT: Match the exact language of the USER REQUEST for all summaries, "
            "verification notes, and confirmation questions. Do NOT expose 'Agent A' or 'Agent B' labels."
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
                        if self.current_proc and self.current_proc.poll() is None:
                            try:
                                self.current_proc.terminate()
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
            "ydotoold daemon is ACTIVE (you can simulate real keyboard/mouse input with `ydotool`)."
            if self.ydotool_active
            else "ydotoold is currently inactive (use Hyprland IPC, app CLIs, xdg-open, wl-copy, grim; or start `systemctl --user start ydotool` if mouse/keyboard synthesis is truly required)."
        )
        return (
            "ENVIRONMENT & DESKTOP AUTOMATION CAPABILITIES:\n"
            f"- OS: Arch Linux on Hyprland Wayland desktop (user home: {self.cwd})\n"
            "- Launch GUI apps cleanly in background (never block): `setsid -f hyprctl dispatch exec \"<command>\" >/dev/null 2>&1` or `nohup gtk-launch <desktop_id> >/dev/null 2>&1 &`\n"
            "- Inspect/focus windows: `hyprctl clients -j`, `hyprctl activewindow -j`, `hyprctl dispatch focuswindow ...`, `hyprctl dispatch workspace ...`\n"
            "- Open URLs/files: `setsid -f xdg-open \"<url_or_path>\" >/dev/null 2>&1`\n"
            "- Clipboard: `wl-copy` / `wl-paste`\n"
            "- Capture desktop screenshot to inspect GUI state visually: `grim /tmp/ai_screen_check.png`\n"
            f"- Human-like input synthesis: {yd_note}\n"
        )

    def run_agy(
        self,
        role: str,
        prompt: str,
        model: str,
        stream_to_ui: bool = False,
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

            role_label = "Coordinator" if role == "supervisor" else "Execution Engine"
            role_color = "\033[1;35m" if role == "supervisor" else "\033[1;32m"
            self.logger.write(
                f"{role_label} starting with model [{current_model}]"
                + (" [FULL PERMISSIONS]" if self.full_perms else ""),
                role_color,
            )
            emit(
                "engine_start",
                role=role,
                model=current_model,
                fullPermissions=self.full_perms,
            )

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
                self.current_proc = proc

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
                        self.logger.write(f"[{role_label}] stderr: {clean}", "\033[33m")
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
                    if stream_to_ui:
                        emit("engine_delta", role=role, text=raw_line)
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
                        if stream_to_ui:
                            emit("engine_delta", role=role, text=delta)
                    elif step_type not in ("user_input", "agent_response", "") and step_idx not in seen_step_tool_idx:
                        seen_step_tool_idx.add(step_idx)
                        tool_info = su.get("tool_name") or step_type
                        self.logger.write(f"  -> {role_label} step #{step_idx}: {tool_info}", "\033[36m")
                        emit("engine_step", role=role, step=step_idx, detail=str(tool_info))
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
                self.current_proc = None

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
                    if role == "supervisor":
                        self.supervisor_model = next_model
                    else:
                        self.worker_model = next_model
                    current_model = next_model
                    continue

            if failed:
                self.logger.write(f"{role_label} exited with code {proc.returncode}: {err_text}", "\033[1;31m")
                return False, output_text, err_text or f"agy exited with code {proc.returncode}", current_model

            return True, output_text, err_text, current_model

        return False, "", "Stopped by user.", current_model

    def run_task(self, user_task: str):
        self.logger.write(f"USER REQUEST: {user_task}", "\033[1;34m")
        emit(
            "phase",
            phase="planning",
            progress=18,
            detail="Đang phân tích yêu cầu & lập kế hoạch..." if self.is_vi() else "Analyzing request & planning steps...",
        )

        # 1. Primary Coordinator plans execution instructions and verification criteria
        plan_prompt = (
            "You are the Primary AI Coordinator on a local Linux desktop.\n"
            "Analyze the user's request, write clear concrete execution steps for the background execution engine, "
            "and define verifiable success criteria.\n\n"
            f"{self.language_instruction()}\n\n"
            f"{self.desktop_context()}\n"
            f"USER REQUEST:\n{user_task}\n\n"
            "Respond ONLY with valid JSON matching this schema (no extra markdown outside JSON):\n"
            "{\n"
            '  "summary": "1-2 sentence plan summary for the user",\n'
            '  "execution_prompt": "Complete step-by-step actionable instructions for execution and output verification",\n'
            '  "success_criteria": "Exact things to verify afterwards to confirm the task succeeded"\n'
            "}"
        )

        ok, plan_raw, err, eff_sup = self.run_agy("supervisor", plan_prompt, self.supervisor_model, stream_to_ui=False)
        if not ok:
            emit("task_error", message=err or ("Không thể lập kế hoạch thực thi." if self.is_vi() else "Failed to plan task."))
            return

        plan_json = extract_json_block(plan_raw) or {}
        plan_summary = plan_json.get("summary") or ("Bắt đầu thực thi tác vụ." if self.is_vi() else "Starting task execution.")
        exec_prompt = plan_json.get("execution_prompt") or (
            f"Execute this user request completely and report concrete verified results:\n{user_task}\n\n{self.desktop_context()}"
        )
        success_criteria = plan_json.get("success_criteria") or (
            "Tất cả tác vụ hoàn tất chính xác và không có lỗi."
            if self.is_vi()
            else "All requested actions complete cleanly without errors."
        )

        emit(
            "assistant_message",
            model=eff_sup,
            title="Kế hoạch thực thi" if self.is_vi() else "Execution Plan",
            text=plan_summary,
        )
        self.logger.write(f"Plan: {plan_summary}", "\033[35m")

        max_rounds = 4
        current_exec_prompt = (
            "You are the background Execution Engine operating on the user's machine.\n"
            "Execute the task thoroughly and concisely report exact commands, files, or windows touched.\n\n"
            f"{self.language_instruction()}\n\n"
            f"{self.desktop_context()}\n"
            f"USER REQUEST:\n{user_task}\n\n"
            f"EXECUTION PLAN:\n{exec_prompt}"
        )

        for round_idx in range(1, max_rounds + 1):
            if self.stop_requested:
                break

            emit(
                "phase",
                phase="working",
                progress=52,
                detail=(
                    f"Đang thực thi tác vụ (Lượt {round_idx})..."
                    if self.is_vi()
                    else f"Executing task (Step {round_idx})..."
                ),
            )
            self.logger.write(f"--- Executing Task (Round {round_idx}) ---", "\033[1;32m")

            ok_b, worker_out, err_b, eff_exec = self.run_agy("executor", current_exec_prompt, self.worker_model, stream_to_ui=True)
            emit(
                "execution_report",
                model=eff_exec,
                round=round_idx,
                title=(f"Kết quả thực thi (Lượt {round_idx})" if self.is_vi() else f"Execution Result (Round {round_idx})"),
                text=worker_out or (f"Error: {err_b}" if err_b else "(No output)"),
                ok=ok_b,
            )

            if self.stop_requested:
                break

            emit(
                "phase",
                phase="verifying",
                progress=84,
                detail="Đang kiểm chứng kết quả thực tế..." if self.is_vi() else "Verifying actual outcome against your request...",
            )
            self.logger.write("Auditing execution output against user request...", "\033[1;35m")

            audit_prompt = (
                "You are the Quality & Safety Auditor reviewing what the background Execution Engine just did.\n"
                "Objectively verify the output (and run quick inspection checks if needed) against the USER REQUEST and SUCCESS CRITERIA.\n"
                "Be strict: if the task failed, did something wrong, missed part of the request, or left an error/risk, set valid=false and write a helpful confirmation question for the user.\n\n"
                f"{self.language_instruction()}\n\n"
                f"USER REQUEST:\n{user_task}\n\n"
                f"SUCCESS CRITERIA:\n{success_criteria}\n\n"
                f"EXECUTION STATUS: {'SUCCESS' if ok_b else 'FAILED (' + err_b + ')'}\n"
                f"EXECUTION REPORT:\n{worker_out}\n\n"
                "Respond ONLY with valid JSON:\n"
                "{\n"
                '  "valid": true or false,\n'
                '  "verification": "Clear concise summary of what was verified and the final outcome",\n'
                '  "question_for_user": "If valid is false (or confirmation is required), direct question asking how to proceed; otherwise empty string",\n'
                '  "suggested_fix_prompt": "If valid is false, concrete fix instructions; otherwise empty string"\n'
                "}"
            )

            ok_v, audit_raw, err_v, eff_sup2 = self.run_agy("supervisor", audit_prompt, self.supervisor_model, stream_to_ui=False)
            if not ok_v:
                emit("task_error", message=err_v or ("Kiểm chứng thất bại." if self.is_vi() else "Verification failed."))
                return

            audit = extract_json_block(audit_raw) or {}
            is_valid = bool(audit.get("valid", ok_b))
            verification = str(audit.get("verification") or audit_raw or "Done.")
            question = str(audit.get("question_for_user") or "").strip()
            fix_prompt = str(audit.get("suggested_fix_prompt") or "").strip()

            self.logger.write(f"Audit -> valid={is_valid}: {verification}", "\033[1;35m")

            if is_valid:
                emit(
                    "assistant_message",
                    model=eff_sup2,
                    title="Hoàn tất & Đã kiểm chứng" if self.is_vi() else "Verified & Completed",
                    text=verification,
                )
                emit("task_complete", progress=100, summary=verification)
                self.logger.write("TASK COMPLETED SUCCESSFULLY.", "\033[1;32m")
                return

            if not self.ask_on_invalid:
                emit(
                    "assistant_message",
                    model=eff_sup2,
                    title="Phát hiện vấn đề" if self.is_vi() else "Verification Issue",
                    text=verification,
                )
                emit("task_error", message=verification)
                return

            fallback_q = (
                f"Hệ thống phát hiện vấn đề khi kiểm chứng:\n{verification}\n\nBạn muốn chạy lại để sửa, chấp nhận kết quả này, hay dừng tác vụ?"
                if self.is_vi()
                else f"Verification detected an issue:\n{verification}\n\nWould you like to retry with fixes, accept anyway, or stop?"
            )
            prompt_question = question or fallback_q
            emit(
                "phase",
                phase="waiting_user",
                progress=75,
                detail="Đang chờ xác nhận từ bạn..." if self.is_vi() else "Waiting for your confirmation...",
            )
            emit(
                "user_question",
                model=eff_sup2,
                verification=verification,
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
                    emit("task_error", message="Đã dừng theo yêu cầu." if self.is_vi() else "Task stopped by user.")
                    return
                if rtype == "user_reply":
                    action = reply.get("action", "retry")
                    user_text = str(reply.get("text", "")).strip()
                    self.logger.write(f"USER REPLY ({action}): {user_text}", "\033[1;34m")

                    if action == "accept":
                        emit("task_complete", progress=100, summary=verification)
                        return
                    elif action == "abort":
                        emit("task_error", message="Đã hủy theo xác nhận người dùng." if self.is_vi() else "Aborted by user.")
                        return
                    else:
                        guidance = user_text or fix_prompt or "Fix the identified issues and verify carefully."
                        current_exec_prompt = (
                            "Previous attempt did not pass verification. Apply corrections carefully.\n\n"
                            f"{self.language_instruction()}\n\n"
                            f"{self.desktop_context()}\n"
                            f"ORIGINAL USER REQUEST:\n{user_task}\n\n"
                            f"VERIFICATION ISSUE:\n{verification}\n\n"
                            f"USER / COORDINATOR GUIDANCE:\n{guidance}\n\n"
                            "Fix the issue completely and report verified results."
                        )
                        break

        emit("task_error", message="Đã vượt quá số lần thử lại tối đa." if self.is_vi() else "Reached maximum retry rounds.")


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
