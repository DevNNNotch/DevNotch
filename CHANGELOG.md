# Changelog

All notable DevNotch changes are documented here. This project is currently in development preview and has no published DevNotch release.

## Unreleased

### Added

- Developer dashboard for system status, source-labeled AI token usage, clipboard context, and external task events.
- OpenAI organization Usage API integration with Keychain credential storage.
- Local Codex session and Claude Code status-line adapters.
- Authenticated localhost API plus Python and shell clients for usage, logs, tasks, and builds.
- Ollama clipboard actions and Ollama/vLLM health checks.
- DevNotch application icon, community governance, issue forms, and Organization repository plan.

### Changed

- DevNotch is the default notch workspace and settings section.
- Application and embedded XPC service use DevNotch-specific bundle identifiers.
- System monitor failures and unsupported GPU/headphone metrics display explicit unavailable states.
- Upstream Boring Notch updater, release, Crowdin, funding, and automated version workflows are disabled or removed pending DevNotch-owned infrastructure.

### Fixed

- Local API listener binding no longer configures the port twice.
- Repeated cumulative client snapshots replace the same session instead of inflating totals.
- Usage history retains the newest 2,000 samples rather than deleting them.

## Upstream baseline

DevNotch started from TheBoredTeam/boring.notch commit `99900bf`. Earlier history belongs to that upstream project and remains available in Git.
