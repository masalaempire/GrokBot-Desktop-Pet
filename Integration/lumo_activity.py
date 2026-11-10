#!/usr/bin/env python3
"""Send local Codex lifecycle status to Lumo without changing the task."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import stat
import sys
import tempfile
import time

EVENTS = (
    "UserPromptSubmit", "PreModelRequest", "PreToolUse", "PermissionRequest",
    "PostToolUse", "Stop", "Interrupt", "SessionEnd",
)
TERMINAL = {"done", "stopped"}
ACTIVITY_FILE = re.compile(r"lumo-[0-9a-f]{32}\.json")
ASYNC_QUESTION_TOOL = "request_user_input_async"
QUESTION_REPLY_TAG = "send_user_message_question_reply"


def write_text(path, content):
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as stream:
        temp = Path(stream.name)
        try:
            stream.write(content)
            stream.close()
            temp.chmod(mode)
            os.replace(temp, path)
        finally:
            temp.unlink(missing_ok=True)


def write_json(path, value):
    write_text(path, json.dumps(value, ensure_ascii=True, indent=2) + "\n")


def hook_command(data_dir):
    return shlex.join((sys.executable, str(data_dir / "lumo_activity.py"), "relay", str(data_dir / "Activity")))


def configure(codex_dir, data_dir, install):
    path = codex_dir / "hooks.json"
    config = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    hooks = config.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError(f"Expected a hooks object in {path}")

    command = hook_command(data_dir)
    # Match the installed relay path, including when the Python interpreter changes.
    relay_path = shlex.quote(str(data_dir / "lumo_activity.py"))
    for event in EVENTS:
        groups = []
        for group in hooks.get(event, []):
            kept = [
                handler for handler in group["hooks"]
                if f" {relay_path} relay " not in handler.get("command", "")
            ]
            if kept:
                groups.append({**group, "hooks": kept})
        if install:
            handler = {"type": "command", "command": command, "timeout": 2}
            groups.append({"hooks": [handler]})
        if groups:
            hooks[event] = groups
        else:
            hooks.pop(event, None)

    if install:
        activity_dir = data_dir / "Activity"
        activity_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        write_json(activity_dir / "lumo-activity.json", {"version": 1})
        relay = data_dir / "lumo_activity.py"
        if Path(__file__).resolve() != relay.resolve():
            write_text(relay, Path(__file__).read_text(encoding="utf-8"))
        codex_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    if install or path.exists():
        write_json(path, config)


def tool_status(payload):
    name = payload.get("tool_name", "")
    function = name.rsplit("__", 1)[-1] if isinstance(name, str) else ""
    if function == "request_permissions":
        return "approval"
    if function in {"request_user_input", ASYNC_QUESTION_TOOL}:
        return "input"
    if name in {"apply_patch", "Edit", "Write"}:
        return "editing"
    if name not in {"Bash", "exec_command"}:
        if isinstance(name, str) and name.endswith(("__read_file", "__read_text_file")):
            return "reading"
        return "tool"
    inputs = payload.get("tool_input") or {}
    command = inputs.get("command", inputs.get("cmd", "")) if isinstance(inputs, dict) else ""
    try:
        args = shlex.split(command) if isinstance(command, str) else []
    except ValueError:
        args = []
    program = Path(args[0]).name if args else ""
    if program in {"cat", "head", "tail", "sed", "nl", "less"}:
        return "reading"
    if program in {"rg", "grep", "find", "ls"}:
        return "searching"
    if program in {"pytest", "xcodebuild", "swift", "cargo", "npm", "pnpm", "bun", "go"}:
        if program == "pytest" or "test" in args[1:]:
            return "testing"
        if "build" in args[1:]:
            return "building"
    return "command"


def update_pending_questions(state, transcript_path):
    if not isinstance(transcript_path, str) or not transcript_path:
        return
    source = hashlib.sha256(os.fsencode(transcript_path)).hexdigest()
    if state.get("transcriptSource", source) != source:
        return

    try:
        with Path(transcript_path).open("rb") as transcript:
            end = transcript.seek(0, os.SEEK_END)
            position = state.get("transcriptPosition", end)
            state["transcriptSource"] = source
            state["transcriptPosition"] = min(position, end)
            transcript.seek(state["transcriptPosition"])
            pending = state.setdefault("pendingQuestions", {})

            while line := transcript.readline():
                if not line.endswith(b"\n"):
                    break
                state["transcriptPosition"] += len(line)
                if b"request_user_input_async" not in line and (not pending or b"function_call_output" not in line):
                    continue
                try:
                    record = json.loads(line)
                    if record.get("type") == "response_item":
                        track_question(pending, record["payload"])
                except (ValueError, TypeError, KeyError, AttributeError):
                    continue
    except OSError:
        return


def track_question(pending, item):
    kind = item.get("type")
    call_id = item.get("call_id")
    if kind == "function_call" and item.get("name") == ASYNC_QUESTION_TOOL:
        questions = json.loads(item["arguments"]).get("questions")
        if isinstance(call_id, str) and isinstance(questions, list) and questions:
            pending[call_id] = list(range(len(questions)))
    elif kind == "function_call_output" and call_id in pending:
        try:
            accepted = json.loads(item["output"]).get("accepted") is True
        except (ValueError, TypeError, KeyError, AttributeError):
            accepted = False
        if not accepted:
            pending.pop(call_id)
    elif kind == "message" and item.get("role") == "user" and pending:
        start, end = f"<{QUESTION_REPLY_TAG}>", f"</{QUESTION_REPLY_TAG}>"
        for part in item.get("content", []):
            content = part.get("text", "").strip()
            if not content.startswith(start) or not content.endswith(end):
                continue
            for reply in json.loads(content[len(start):-len(end)]):
                tool, question_call, index = json.loads(reply["questionItemId"])
                indexes = pending.get(question_call, [])
                if tool == ASYNC_QUESTION_TOOL and index in indexes:
                    indexes.remove(index)
                    if not indexes:
                        pending.pop(question_call)


def update_state(state, payload, now):
    event = payload["hook_event_name"]
    turn = payload.get("turn_id")
    if event == "UserPromptSubmit" or not state:
        cwd = payload.get("cwd")
        project = Path(cwd).name if isinstance(cwd, str) else ""
        state = {
            "version": 1, "turn": turn, "project": "".join(filter(str.isprintable, project))[:40],
            "tools": {}, "approval": False, "status": "working",
        }
    elif turn and state.get("turn") and turn != state["turn"]:
        # A late result from an earlier turn must not replace the current one.
        return None

    # Async questions acknowledge immediately. Only a matching reply closes them.
    update_pending_questions(state, payload.get("transcript_path"))
    pending = state.get("pendingQuestions", {})
    tools = state["tools"]
    tool_id = payload.get("tool_use_id")
    if event in {"UserPromptSubmit", "PreModelRequest"}:
        state["approval"] = False
        tools.clear()
        state["status"] = "working"
    elif event == "PreToolUse":
        status = tool_status(payload)
        if isinstance(tool_id, str):
            tools[tool_id] = status
        state["status"] = status
    elif event == "PostToolUse":
        if state["status"] in TERMINAL:
            return None
        if isinstance(tool_id, str):
            tools.pop(tool_id, None)
        state["status"] = next(reversed(tools.values()), "working")
    elif event == "PermissionRequest":
        state["approval"] = True
    elif event in {"Stop", "Interrupt", "SessionEnd"}:
        if event == "SessionEnd" and state["status"] in TERMINAL and not pending:
            return None
        if event != "Stop":
            pending.clear()
        state["approval"] = False
        tools.clear()
        state["status"] = "done" if event == "Stop" else "stopped"

    if state["approval"] or "approval" in tools.values():
        state["display"] = "approval"
    elif pending:
        state["display"] = "input"
    else:
        state["display"] = state["status"]
    state["updatedAt"] = now
    return state


def relay(activity_dir):
    payload = json.load(sys.stdin)
    if not isinstance(payload, dict) or payload.get("hook_event_name") not in EVENTS:
        return
    session = payload.get("session_id")
    if not isinstance(session, str) or not session or not activity_dir.is_dir():
        return
    name = hashlib.sha256(session.encode()).hexdigest()[:32]
    path = activity_dir / f"lumo-{name}.json"

    with (activity_dir / ".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        now = time.time()
        try:
            previous = json.loads(path.read_text(encoding="utf-8"))
        except (FileNotFoundError, ValueError):
            previous = {}
        if not previous and payload["hook_event_name"] in {"PostToolUse", "SessionEnd"}:
            return
        state = update_state(previous, payload, now)
        if state is not None:
            write_json(path, state)
        if payload["hook_event_name"] == "UserPromptSubmit":
            for old in activity_dir.iterdir():
                if ACTIVITY_FILE.fullmatch(old.name) and now - old.stat().st_mtime > 86400:
                    old.unlink(missing_ok=True)


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "relay":
        try:
            relay(Path(sys.argv[2]))
        except (OSError, ValueError, TypeError, KeyError, AttributeError):
            pass
        # An empty JSON response is informational even for the Stop hook.
        print("{}")
        return

    if len(sys.argv) != 2 or sys.argv[1] not in {"install", "uninstall"}:
        sys.exit("Usage: python3 lumo_activity.py install|uninstall")
    codex_dir = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")).expanduser().resolve()
    data_dir = Path.home() / "Library" / "Application Support" / "Lumo"
    install = sys.argv[1] == "install"
    try:
        configure(codex_dir, data_dir, install)
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        sys.exit(f"Lumo setup could not update {codex_dir / 'hooks.json'}: {error}")

    if install:
        print(f"Added Lumo's hooks to {codex_dir / 'hooks.json'}.")
        print("In ChatGPT, review and trust the Lumo hooks in Settings > Hooks.")
        print("Right-click Lumo, choose Connect Task Activity, and select:")
        print(data_dir / "Activity")
    else:
        print("Removed Lumo's hook definitions. You can disconnect the activity folder in Lumo.")


if __name__ == "__main__":
    main()
