# DevNotch Local API

DevNotch accepts structured task, build, log, and token usage events from tools running on the same Mac. The server binds only to `127.0.0.1:54731` and is disabled by default.

## Authentication

Enable the server in **Settings > Developer > Local event API**, then copy its access token. Store it in the calling process environment:

```sh
export DEVNOTCH_API_TOKEN='value-copied-from-keychain'
```

Do not commit this value. Every endpoint, including health, requires `Authorization: Bearer $DEVNOTCH_API_TOKEN`.

## Command-line client

```sh
scripts/devnotch-event build "Compile DevNotch" --state running --progress 0.4
scripts/devnotch-event task "Run unit tests" --state succeeded --progress 1
scripts/devnotch-event log "Deployment failed" --state failed --detail "codesign exited 1"
scripts/devnotch-event usage \
  --provider claude-code \
  --input 4200 \
  --cached-input 1800 \
  --output 720 \
  --model claude-sonnet \
  --timestamp 2026-09-04T12:00:00Z
```

The Python client uses only the standard library. Set `DEVNOTCH_API_URL` to override the default endpoint for local testing.

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/v1/health` | Check the local service |
| `POST` | `/v1/events/log` | Publish a structured log event |
| `POST` | `/v1/events/task` | Publish task state and progress |
| `POST` | `/v1/events/build` | Publish build state and progress |
| `POST` | `/v1/usage/events` | Publish client-reported token counts |

Requests must be JSON objects. Unknown fields are rejected. Bodies larger than 1 MiB are rejected, and the server enforces a per-process request limit.

### Developer event

```json
{
  "id": "2AD09B45-A614-45B7-861E-EA917E50751B",
  "title": "Compile DevNotch",
  "detail": "Building arm64 target",
  "progress": 0.4,
  "state": "running",
  "timestamp": "2026-09-04T12:00:00Z"
}
```

`title` is required. `state` must be `queued`, `running`, `succeeded`, `failed`, or `cancelled`. `progress`, when present, must be between `0` and `1`.

### Usage event

```json
{
  "provider": "claude-code",
  "accountOrWorkspace": "local-project",
  "model": "claude-sonnet",
  "sessionID": "session-123",
  "inputTokens": 4200,
  "cachedInputTokens": 1800,
  "outputTokens": 720,
  "totalTokens": 4920,
  "timestamp": "2026-09-04T12:00:00Z"
}
```

Token counts must be non-negative integers. DevNotch labels these values as client-reported; it does not present them as provider-authoritative billing data.

## Errors

Errors use a non-2xx HTTP status with a JSON body:

```json
{"error":"Request validation failed: progress must be between 0 and 1"}
```

DevNotch never executes commands supplied through this API.

## Claude Code status line

`Examples/claude_statusline.py` consumes Claude Code's official status-line JSON and sends only the session ID, model ID, project directory, and current token counters to DevNotch. It does not read the transcript or prompt fields.

Make the adapter executable and configure its absolute path in Claude Code settings:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/absolute/path/to/DevNotch/Examples/claude_statusline.py"
  }
}
```

The adapter expects `DEVNOTCH_API_TOKEN` in its environment. Claude Code 2.1.132 and newer describes these fields as the latest context snapshot, not cumulative session billing. DevNotch therefore replaces the existing sample for the same Claude Code session instead of adding each refresh again.

## Codex local session adapter

The Codex adapter reads only `session_meta`, `turn_context.model`, and cumulative
`token_count` events from local session JSONL files. It does not collect prompts,
responses, tool output, or repository contents.

```sh
export DEVNOTCH_API_TOKEN='value-copied-from-keychain'
python3 Examples/codex_usage_sync.py --watch 30
```

This is local session telemetry, not Codex subscription quota. Codex Cloud tasks
are visible only after the installed client has synchronized corresponding logs.
