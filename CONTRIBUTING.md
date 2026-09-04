# Contributing to DevNotch

DevNotch welcomes focused fixes, provider adapters, documentation, tests, and accessibility improvements.

## Before coding

- Search existing issues and Discussions.
- Open a design discussion before adding a token source, persistent collection, network listener, entitlement, or system permission.
- A provider integration must cite an official or user-authorized structured data source and define its failure behavior.
- Never submit captured prompts, API keys, private repository content, or undocumented traffic interception.

## Development

Requirements currently follow the upstream application: macOS 14+, Xcode 16.4+, and Swift 6 tooling.

```sh
git clone https://github.com/DevNNNotch/DevNotch.git
cd DevNotch
git switch -c feature/short-description
swift build
swift test
open boringNotch.xcodeproj
```

Use the existing Swift style. Keep changes scoped, surface errors with actionable messages, and do not add fallback data that makes an unavailable integration appear healthy.

## Pull requests

Include:

- The problem and root cause.
- The implementation and privacy impact.
- Commands used to verify the change.
- Screenshots or a recording for UI changes.
- Fixtures that contain no real user data for parser changes.
- Updated compatibility and implementation status when support changes.

DevNotch is derived from Boring Notch and distributed under GPL-3.0. Contributions must be compatible with that license and retain required attribution.
