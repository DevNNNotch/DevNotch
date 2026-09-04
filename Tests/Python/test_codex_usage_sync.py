import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "Examples" / "codex_usage_sync.py"
sys.path.insert(0, str(MODULE_PATH.parent))
SPEC = importlib.util.spec_from_file_location("codex_usage_sync", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class CodexUsageSyncTests(unittest.TestCase):
    def test_reads_only_structured_usage_fields(self) -> None:
        records = [
            {
                "type": "session_meta",
                "payload": {"id": "session-1", "cwd": "/tmp/project", "base_instructions": "private"},
            },
            {"type": "turn_context", "payload": {"model": "gpt-test"}},
            {
                "type": "response_item",
                "payload": {"content": "must not be collected"},
            },
            {
                "timestamp": "2026-09-04T01:02:03Z",
                "type": "event_msg",
                "payload": {
                    "type": "token_count",
                    "info": {
                        "total_token_usage": {
                            "input_tokens": 120,
                            "cached_input_tokens": 80,
                            "output_tokens": 30,
                            "total_tokens": 150,
                        }
                    },
                },
            },
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "session.jsonl"
            path.write_text("".join(json.dumps(record) + "\n" for record in records), encoding="utf-8")
            usage = MODULE.parse_session(path)

        self.assertIsNotNone(usage)
        assert usage is not None
        self.assertEqual(usage.session_id, "session-1")
        self.assertEqual(usage.input_tokens, 120)
        self.assertEqual(usage.cached_input_tokens, 80)
        self.assertEqual(usage.output_tokens, 30)
        self.assertNotIn("content", usage.payload())

    def test_rejects_malformed_token_counts(self) -> None:
        records = [
            {"type": "session_meta", "payload": {"id": "session-1"}},
            {
                "type": "event_msg",
                "payload": {
                    "type": "token_count",
                    "info": {
                        "total_token_usage": {
                            "input_tokens": -1,
                            "output_tokens": 2,
                            "total_tokens": 1,
                        }
                    },
                },
            },
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "session.jsonl"
            path.write_text("".join(json.dumps(record) + "\n" for record in records), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "input_tokens"):
                MODULE.parse_session(path)


if __name__ == "__main__":
    unittest.main()
