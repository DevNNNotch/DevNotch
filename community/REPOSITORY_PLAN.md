# Community Repository Plan

The Organization starts with two repositories:

| Repository | Purpose | Creation rule |
| --- | --- | --- |
| `DevNotch` | macOS app, local API, adapters, documentation, releases | Create immediately |
| `.github` | Organization profile and default community health files | Create immediately |

Additional repositories are created only when maintained code has a separate release lifecycle. Empty SDK, plugin, roadmap, and examples repositories are not created for appearance; those materials remain in `DevNotch` until separation removes real coupling.

## Initial GitHub settings

- Public visibility and GPL-3.0 license.
- Discussions enabled with `Announcements`, `Ideas`, `Integrations`, `Q&A`, and `Show and tell` categories.
- Issues enabled; blank issues disabled.
- Default branch `main`, delete head branches after merge.
- Branch protection requires pull requests, the DevNotch Core check, resolved conversations, and no force pushes.
- Secret scanning, push protection, Dependabot alerts, and private vulnerability reporting enabled where the GitHub plan supports them.

The contents of `ORGANIZATION_PROFILE.md` become `.github/profile/README.md` in the Organization profile repository.
