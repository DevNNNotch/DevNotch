# Security Policy

## Reporting a vulnerability

Use the repository's private **Security > Report a vulnerability** form. Do not disclose security issues in public Issues or Discussions.

Include:

- Affected commit or version.
- Reproduction steps.
- Expected security boundary and observed behavior.
- Whether credentials, clipboard data, local files, or network access are involved.

Never include real API keys, local API tokens, private prompts, or proprietary source code. Use synthetic data and revoke any credential that may have been exposed.

## Sensitive areas

Changes involving Keychain, clipboard access, the localhost API, provider credentials, entitlements, Ollama endpoints, or source-log parsing require explicit security review.

DevNotch accepts only authenticated local API requests, rejects unknown fields and oversized bodies, and does not execute commands from event payloads. A bypass of any of these controls is considered a security issue.

Security support covers the current release line after releases exist. Until then, reports should reference the exact commit.
