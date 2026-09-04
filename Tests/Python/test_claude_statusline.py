import importlib.util
import pathlib
import sys
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "Examples" / "claude_statusline.py"
sys.path.insert(0, str(MODULE_PATH.parent))
SPEC = importlib.util.spec_from_file_location("claude_statusline", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ClaudeStatusLineTests(unittest.TestCase):
    def test_maps_official_current_usage_without_prompt_content(self) -> None:
        payload = MODULE.usage_payload(
            {
                "session_id": "session-1",
                "model": {"id": "claude-test", "display_name": "Test"},
                "workspace": {"project_dir": "/tmp/project"},
                "context_window": {
                    "used_percentage": 12,
                    "current_usage": {
                        "input_tokens": 100,
                        "cache_creation_input_tokens": 20,
                        "cache_read_input_tokens": 30,
                        "output_tokens": 40,
                    },
                },
                "prompt": "must not be collected",
            }
        )

        self.assertIsNotNone(payload)
        assert payload is not None
        self.assertEqual(payload["inputTokens"], 150)
        self.assertEqual(payload["cachedInputTokens"], 50)
        self.assertEqual(payload["outputTokens"], 40)
        self.assertEqual(payload["totalTokens"], 190)
        self.assertNotIn("prompt", payload)

    def test_returns_none_before_first_api_response(self) -> None:
        self.assertIsNone(MODULE.usage_payload({"context_window": {"current_usage": None}}))


if __name__ == "__main__":
    unittest.main()
