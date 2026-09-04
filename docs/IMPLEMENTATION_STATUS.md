# Implementation Status

Last audited: 2026-09-04

DevNotch is currently a development branch derived from TheBoredTeam's `boring.notch` at upstream commit `99900bf`. The inherited code is GPL-3.0 licensed; DevNotch remains GPL-3.0.

## Verified locally

- The branch is based directly on `upstream/main`.
- The DevNotch core builds with Apple Swift 6.3.2 using `swift build`.
- Core sources type-check for `arm64-apple-macosx14.0`.
- The Xcode project, Info.plist, and entitlements pass `plutil -lint`.
- The Python event client parses its CLI and byte-compiles.
- Python tests verify Claude Code and Codex adapters without collecting prompt content.
- The Codex adapter successfully parses the current local Codex session log schema and extracts cumulative token counters.
- The localhost API passes an end-to-end smoke test covering authenticated health, accepted usage, missing authentication, and invalid token counts.
- The replacement macOS icon is generated reproducibly from the repository SVG source and every asset slot has the expected pixel dimensions.
- The native DMG and Homebrew Cask packaging paths pass a local mount-and-parse smoke test.
- A standalone prototype launched successfully before its services were migrated into the upstream application.

## Implemented, awaiting full Xcode verification

- Developer tab integrated into the existing notch navigation.
- System CPU, memory, network, and battery sampling using public system interfaces.
- Explicit unavailable states for system-wide GPU utilization and headphone battery instead of synthetic zero values.
- Clipboard classification for code, errors, Git diffs, text, and common secret formats.
- Ollama model health check and cancellable streaming chat.
- vLLM OpenAI-compatible model endpoint health check.
- OpenAI organization Usage API provider with Keychain credential storage.
- Codex local-session adapter with an explicit boundary around subscription quota and unsynchronized cloud tasks.
- Claude Code official status-line adapter with session-level upsert semantics.
- Explicit unsupported states for Codex subscription quota, unsynchronized Codex Cloud tasks, and Trae.
- Authenticated localhost event API for logs, tasks, builds, and client-reported token usage.
- Developer settings for monitoring, Ollama, OpenAI API usage, and the local event server.
- DevNotch-specific application and embedded XPC service bundle identifiers.
- Swift core tests and a GitHub Actions workflow.
- Reproducible source-build/install, Developer ID signing, Apple notarization, GitHub Release, and Homebrew Cask automation.

## Not yet verified or delivered

- Full `xcodebuild` Debug and Release builds. The active developer directory contains Command Line Tools only; complete Xcode is not installed or selected.
- Swift tests. The installed Command Line Tools do not contain XCTest or Swift Testing; CI and full Xcode must run them.
- A signed and notarized public release. The pipeline exists, but it cannot produce a trusted artifact until the GitHub repositories and Apple release credentials are configured.
- Runtime verification of the integrated upstream app and visual QA of the Developer tab.
- Real OpenAI Usage API results because no Admin Key has been provided.
- A real Ollama generation because service/model availability has not been confirmed.
- Any verified Trae provider.
- GPU, external-display brightness, and Bluetooth headphone battery metrics.
- A supported Trae export API or hook. TRAE currently documents usage in its IDE and account profile, but no public machine-readable integration surface.
- GitHub application repository, Homebrew tap, Discussions, labels, rulesets, or remote push. The `DevNNNotch` Organization exists, but its repositories have not been created.
- macOS 13 support. The selected upstream baseline targets macOS 14; backport feasibility has not been established.

## Security boundaries

- Provider credentials and the local API token use Keychain.
- The HTTP listener binds to `127.0.0.1` and requires a Bearer token.
- Unknown JSON fields, oversized bodies, invalid progress, and negative token counts are rejected.
- Clipboard text is not persisted. Common credential formats disable AI actions.
- DevNotch never executes commands delivered through the local API.

## Known upstream constraints

The upstream project contains private-framework integration for existing Boring Notch behavior. New DevNotch modules use public frameworks only. Removing or replacing inherited private-framework functionality requires a separate compatibility audit.
