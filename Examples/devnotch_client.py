#!/usr/bin/env python3
"""Push structured developer events to a running DevNotch instance."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request


DEFAULT_BASE_URL = "http://127.0.0.1:54731"


def post(path: str, payload: dict[str, object]) -> None:
    token = os.environ.get("DEVNOTCH_API_TOKEN")
    if not token:
        raise RuntimeError(
            "DEVNOTCH_API_TOKEN is missing. Copy it from DevNotch Settings > Developer."
        )

    base_url = os.environ.get("DEVNOTCH_API_URL", DEFAULT_BASE_URL).rstrip("/")
    request = urllib.request.Request(
        f"{base_url}{path}",
        data=json.dumps(payload, separators=(",", ":")).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(request, timeout=5) as response:
            if response.status != 202:
                raise RuntimeError(f"DevNotch returned unexpected HTTP {response.status}")
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"DevNotch returned HTTP {error.code}: {body}") from error
    except urllib.error.URLError as error:
        raise RuntimeError(f"DevNotch is unreachable at {base_url}: {error.reason}") from error


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    commands = root.add_subparsers(dest="command", required=True)

    for name in ("log", "task", "build"):
        command = commands.add_parser(name)
        command.add_argument("title")
        command.add_argument("--detail")
        command.add_argument(
            "--state",
            choices=("queued", "running", "succeeded", "failed", "cancelled"),
            default="running",
        )
        command.add_argument("--progress", type=float)

    usage = commands.add_parser("usage")
    usage.add_argument(
        "--provider",
        choices=("openai", "codex", "claude-code", "trae", "external"),
        required=True,
    )
    usage.add_argument("--input", type=int, required=True, dest="input_tokens")
    usage.add_argument("--cached-input", type=int, default=0, dest="cached_input_tokens")
    usage.add_argument("--output", type=int, required=True, dest="output_tokens")
    usage.add_argument("--model")
    usage.add_argument("--session-id")
    usage.add_argument("--workspace")
    usage.add_argument("--timestamp", required=True, help="ISO-8601 timestamp")
    return root


def main() -> int:
    arguments = parser().parse_args()
    if arguments.command == "usage":
        counts = (arguments.input_tokens, arguments.cached_input_tokens, arguments.output_tokens)
        if any(value < 0 for value in counts):
            raise ValueError("Token counts must be non-negative")
        payload = {
            "provider": arguments.provider,
            "inputTokens": arguments.input_tokens,
            "cachedInputTokens": arguments.cached_input_tokens,
            "outputTokens": arguments.output_tokens,
            "timestamp": arguments.timestamp,
        }
        optional = {
            "model": arguments.model,
            "sessionID": arguments.session_id,
            "accountOrWorkspace": arguments.workspace,
        }
        payload.update({key: value for key, value in optional.items() if value is not None})
        post("/v1/usage/events", payload)
    else:
        if arguments.progress is not None and not 0 <= arguments.progress <= 1:
            raise ValueError("Progress must be between 0 and 1")
        payload = {"title": arguments.title, "state": arguments.state}
        if arguments.detail is not None:
            payload["detail"] = arguments.detail
        if arguments.progress is not None:
            payload["progress"] = arguments.progress
        post(f"/v1/events/{arguments.command}", payload)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, ValueError) as error:
        print(f"devnotch-client: {error}", file=sys.stderr)
        raise SystemExit(1)
