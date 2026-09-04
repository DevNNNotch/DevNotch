# Releasing DevNotch

DevNotch publishes only Developer ID signed and Apple-notarized DMGs. A GitHub tag is not a release candidate until the local release command and Gatekeeper verification succeed.

## Repository layout

- `DevNNNotch/DevNotch`: application source and GitHub Releases
- `DevNNNotch/homebrew-devnotch`: Homebrew tap containing `Casks/devnotch.rb`

The organization owner can differ, but the application and tap must share the same owner for the automated tap update.

## One-time Apple setup

1. Enroll the organization or responsible maintainer in the Apple Developer Program.
2. Create a `Developer ID Application` certificate and export it as a password-protected `.p12` file.
3. Create an App Store Connect API key with permission to submit notarization requests. Record its key ID and issuer ID and download the `.p8` file once.
4. Confirm the certificate locally with `security find-identity -v -p codesigning`.

Never commit the `.p12`, `.p8`, passwords, or tokens.

## GitHub Actions secrets

Configure these Actions secrets in the application repository:

| Secret | Value |
| --- | --- |
| `APPLE_DEVELOPMENT_TEAM` | Ten-character Apple Developer Team ID |
| `APPLE_SIGNING_IDENTITY` | Full Developer ID identity, including team suffix |
| `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded `.p12` file |
| `APPLE_CERTIFICATE_PASSWORD` | `.p12` export password |
| `APPLE_KEYCHAIN_PASSWORD` | Random password used only for the CI temporary keychain |
| `APPLE_NOTARY_KEY_ID` | App Store Connect API key ID |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect issuer UUID |
| `APPLE_NOTARY_PRIVATE_KEY_BASE64` | Base64-encoded `.p8` file |
| `HOMEBREW_TAP_TOKEN` | Fine-grained token with Contents write access only to `homebrew-devnotch` |

Create a GitHub environment named `release`, restrict it to protected release tags, and require a maintainer review before exposing the Apple secrets. Create a separate `homebrew` environment containing only `HOMEBREW_TAP_TOKEN`. The workflow rejects tags whose commit is not contained in `main`.

Encode binary secret files without line wrapping:

```sh
base64 -i DeveloperID.p12 | pbcopy
base64 -i AuthKey_KEYID.p8 | pbcopy
```

## Local release verification

Use a clean checkout and an empty `dist` directory. The scripts refuse to overwrite release output.

```sh
export DEVNOTCH_DEVELOPMENT_TEAM='TEAMID1234'
export DEVNOTCH_SIGNING_IDENTITY='Developer ID Application: Legal Name (TEAMID1234)'
scripts/build-release 0.1.0 1
```

Configure notarization credentials once in the Keychain:

```sh
xcrun notarytool store-credentials DevNotchNotary \
  --key AuthKey_KEYID.p8 \
  --key-id KEYID \
  --issuer ISSUER_UUID
export DEVNOTCH_NOTARY_KEYCHAIN_PROFILE='DevNotchNotary'
scripts/notarize-release dist/DevNotch-0.1.0.dmg
```

The notarization script staples the ticket, asks Gatekeeper to assess the DMG, and writes a SHA-256 checksum. Failure at any stage exits nonzero and must be fixed before tagging.

## Publish

1. Ensure `main` is green and the version in the Xcode project matches the intended stable release.
2. Create and push an annotated tag: `git tag -a v0.1.0 -m 'DevNotch 0.1.0' && git push origin v0.1.0`.
3. The release job rebuilds, signs, notarizes, and publishes the DMG and checksum. A separate least-privilege job then downloads that exact published DMG and updates the Homebrew Cask.
4. On a clean Mac, run `brew install --cask DevNNNotch/devnotch/devnotch`, launch DevNotch, and verify Gatekeeper reports no warning.

Tags containing a pre-release suffix publish a GitHub pre-release and intentionally do not update Homebrew.
