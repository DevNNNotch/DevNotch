#!/usr/bin/env python3
"""Claude Code status-line adapter for DevNotch.

Reads the official status-line JSON from stdin, reports the latest session token
snapshot to DevNotch, and prints a compact status line for Claude Code.
"""

from __future__ import annotations

import datetime
import json
import sys

from devnotch_client import post


def usage_payload(source: dict[str, object]) -> dict[str, object] | None:
    context = source.get("context_window")
    if not isinstance(context, dict):
        return None
    current = context.get("current_usage")
    if not isinstance(current, dict):
        return None

    def token(name: str) -> int:
        value = current.get(name, 0)
        if not isinstance(value, int) or value < 0:
            raise ValueError(f"context_window.current_usage.{name} must be a non-negative integer")
        return value

    direct_input = token("input_tokens")
    cache_creation = token("cache_creation_input_tokens")
    cache_read = token("cache_read_input_tokens")
    output = token("output_tokens")
    total_input = direct_input + cache_creation + cache_read

    model = source.get("model")
    workspace = source.get("workspace")
    payload: dict[str, object] = {
        "provider": "claude-code",
        "inputTokens": total_input,
        "cachedInputTokens": cache_creation + cache_read,
        "outputTokens": output,
        "totalTokens": total_input + output,
        "timestamp": datetime.datetime.now(datetime.timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z"),
    }
    if isinstance(source.get("session_id"), str):
        payload["sessionID"] = source["session_id"]
    if isinstance(model, dict) and isinstance(model.get("id"), str):
        payload["model"] = model["id"]
    if isinstance(workspace, dict) and isinstance(workspace.get("project_dir"), str):
        payload["accountOrWorkspace"] = workspace["project_dir"]
    return payload


def status_line(source: dict[str, object], suffix: str | None = None) -> str:
    model = source.get("model")
    name = model.get("display_name", "Claude") if isinstance(model, dict) else "Claude"
    context = source.get("context_window")
    percentage = context.get("used_percentage", 0) if isinstance(context, dict) else 0
    line = f"{name} | context {percentage}%"
    return f"{line} | DevNotch: {suffix}" if suffix else line


def main() -> int:
    try:
        source = json.load(sys.stdin)
        if not isinstance(source, dict):
            raise ValueError("status-line input must be a JSON object")
        payload = usage_payload(source)
        if payload is not None:
            post("/v1/usage/events", payload)
        print(status_line(source))
        return 0
    except (json.JSONDecodeError, RuntimeError, ValueError) as error:
        source = source if "source" in locals() and isinstance(source, dict) else {}
        print(status_line(source, f"error: {error}"))
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
