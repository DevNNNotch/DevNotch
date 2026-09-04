#!/usr/bin/env python3
"""Report local Codex session token snapshots to DevNotch.

This adapter reads only session metadata, model names, and `token_count` events.
It never sends prompts, responses, tool output, or repository contents.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import pathlib
import time
from dataclasses import dataclass

from devnotch_client import post


@dataclass(frozen=True)
class CodexSessionUsage:
    session_id: str
    workspace: str | None
    model: str | None
    input_tokens: int
    cached_input_tokens: int
    output_tokens: int
    total_tokens: int
    timestamp: str

    def payload(self) -> dict[str, object]:
        result: dict[str, object] = {
            "provider": "codex",
            "sessionID": self.session_id,
            "inputTokens": self.input_tokens,
            "cachedInputTokens": self.cached_input_tokens,
            "outputTokens": self.output_tokens,
            "totalTokens": self.total_tokens,
            "timestamp": self.timestamp,
        }
        if self.workspace:
            result["accountOrWorkspace"] = self.workspace
        if self.model:
            result["model"] = self.model
        return result


def non_negative_integer(value: object, field: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise ValueError(f"{field} must be a non-negative integer")
    return value


def parse_session(path: pathlib.Path) -> CodexSessionUsage | None:
    session_id: str | None = None
    workspace: str | None = None
    model: str | None = None
    latest_usage: dict[str, object] | None = None
    latest_timestamp: str | None = None

    try:
        with path.open("r", encoding="utf-8") as stream:
            for line_number, line in enumerate(stream, start=1):
                try:
                    record = json.loads(line)
                except json.JSONDecodeError as error:
                    raise ValueError(f"{path}:{line_number}: invalid JSON: {error.msg}") from error
                if not isinstance(record, dict):
                    continue
                payload = record.get("payload")
                if not isinstance(payload, dict):
                    continue

                if record.get("type") == "session_meta":
                    identifier = payload.get("id") or payload.get("session_id")
                    if isinstance(identifier, str) and identifier:
                        session_id = identifier
                    if isinstance(payload.get("cwd"), str):
                        workspace = payload["cwd"]
                elif record.get("type") == "turn_context" and isinstance(payload.get("model"), str):
                    model = payload["model"]
                elif record.get("type") == "event_msg" and payload.get("type") == "token_count":
                    info = payload.get("info")
                    if not isinstance(info, dict):
                        continue
                    total = info.get("total_token_usage")
                    if isinstance(total, dict):
                        latest_usage = total
                        if isinstance(record.get("timestamp"), str):
                            latest_timestamp = record["timestamp"]
    except OSError as error:
        raise ValueError(f"Cannot read Codex session log {path}: {error}") from error

    if latest_usage is None:
        return None
    if session_id is None:
        session_id = path.stem
    if latest_timestamp is None:
        latest_timestamp = datetime.datetime.fromtimestamp(
            path.stat().st_mtime, tz=datetime.timezone.utc
        ).isoformat(timespec="seconds").replace("+00:00", "Z")

    input_tokens = non_negative_integer(latest_usage.get("input_tokens"), "input_tokens")
    cached_tokens = non_negative_integer(
        latest_usage.get("cached_input_tokens", 0), "cached_input_tokens"
    )
    output_tokens = non_negative_integer(latest_usage.get("output_tokens"), "output_tokens")
    total_tokens = non_negative_integer(
        latest_usage.get("total_tokens", input_tokens + output_tokens), "total_tokens"
    )
    if total_tokens < input_tokens + output_tokens:
        raise ValueError("total_tokens cannot be smaller than input_tokens + output_tokens")

    return CodexSessionUsage(
        session_id=session_id,
        workspace=workspace,
        model=model,
        input_tokens=input_tokens,
        cached_input_tokens=cached_tokens,
        output_tokens=output_tokens,
        total_tokens=total_tokens,
        timestamp=latest_timestamp,
    )


def recent_session_logs(root: pathlib.Path, days: int) -> list[pathlib.Path]:
    if not root.is_dir():
        raise ValueError(f"Codex sessions directory does not exist: {root}")
    cutoff = time.time() - days * 86_400
    return sorted(
        path for path in root.rglob("*.jsonl") if path.stat().st_mtime >= cutoff
    )


def sync_once(root: pathlib.Path, days: int) -> int:
    count = 0
    for path in recent_session_logs(root, days):
        usage = parse_session(path)
        if usage is None:
            continue
        post("/v1/usage/events", usage.payload())
        count += 1
    return count


def parser() -> argparse.ArgumentParser:
    default_root = pathlib.Path(os.environ.get("CODEX_HOME", pathlib.Path.home() / ".codex")) / "sessions"
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--sessions-dir", type=pathlib.Path, default=default_root)
    result.add_argument("--days", type=int, default=7)
    result.add_argument(
        "--watch",
        type=float,
        metavar="SECONDS",
        help="Repeat synchronization at this interval; the minimum is 10 seconds.",
    )
    return result


def main() -> int:
    arguments = parser().parse_args()
    if arguments.days < 1:
        raise ValueError("--days must be at least 1")
    if arguments.watch is not None and arguments.watch < 10:
        raise ValueError("--watch must be at least 10 seconds")

    while True:
        count = sync_once(arguments.sessions_dir, arguments.days)
        print(f"Reported {count} Codex session snapshot(s) to DevNotch", flush=True)
        if arguments.watch is None:
            return 0
        time.sleep(arguments.watch)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, ValueError) as error:
        raise SystemExit(f"codex-usage-sync: {error}") from error
