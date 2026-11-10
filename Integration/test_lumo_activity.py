import json
from pathlib import Path
import tempfile
import unittest

from lumo_activity import update_state


class InputStatusTest(unittest.TestCase):
    def test_permission_prompt_takes_priority_until_tool_returns(self):
        state = {}

        def event(name, **fields):
            nonlocal state
            state = update_state(state, {"hook_event_name": name, "turn_id": "turn", **fields}, now=1)
            return state["display"]

        event("UserPromptSubmit")
        self.assertEqual(
            event("PreToolUse", tool_name="request_permissions", tool_use_id="permission"), "approval"
        )
        self.assertEqual(
            event("PreToolUse", tool_name="Bash", tool_use_id="read", tool_input={"command": "cat README.md"}),
            "approval",
        )
        self.assertEqual(event("PostToolUse", tool_use_id="permission"), "reading")

    def test_async_question_stays_visible_until_answered(self):
        with tempfile.TemporaryDirectory() as directory:
            transcript = Path(directory) / "transcript.jsonl"
            transcript.touch()
            state = {}

            def event(name, **fields):
                nonlocal state
                state = update_state(state, {
                    "hook_event_name": name,
                    "turn_id": "turn",
                    "transcript_path": str(transcript),
                    **fields,
                }, now=1)
                return state["display"]

            def record(**payload):
                with transcript.open("a", encoding="utf-8") as stream:
                    stream.write(json.dumps({"type": "response_item", "payload": payload}) + "\n")

            event("UserPromptSubmit")
            record(type="function_call", name="request_user_input_async", call_id="call_1",
                   arguments=json.dumps({"questions": [{"title": "Private question"}]}))
            record(type="function_call_output", call_id="call_1", output='{"accepted":true}')
            event("PreModelRequest")
            self.assertEqual(event("PreToolUse", tool_name="clock__sleep", tool_use_id="wait"), "input")

            reply = [{"questionItemId": json.dumps(["request_user_input_async", "call_1", 0]),
                      "answer": "Private answer"}]
            record(type="message", role="user", content=[{
                "type": "input_text",
                "text": "<send_user_message_question_reply>\n" + json.dumps(reply)
                    + "\n</send_user_message_question_reply>",
            }])
            self.assertEqual(event("PreModelRequest"), "working")
            self.assertNotIn("Private", json.dumps(state))


if __name__ == "__main__":
    unittest.main()
