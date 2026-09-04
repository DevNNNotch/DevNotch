#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

if [[ $# -ne 3 ]]; then
  die "Usage: $0 <app-path> <dmg-output> <volume-name>"
fi

APP_PATH="$1"
DMG_OUTPUT="$2"
VOLUME_NAME="$3"

[[ "$APP_PATH" == *.app ]] || die "App path must end in .app: $APP_PATH"
[[ -d "$APP_PATH" ]] || die "App bundle not found: $APP_PATH"
[[ -f "$APP_PATH/Contents/Info.plist" ]] || die "Invalid app bundle; Contents/Info.plist is missing: $APP_PATH"
[[ "$DMG_OUTPUT" == *.dmg ]] || die "Output path must end in .dmg: $DMG_OUTPUT"
[[ ! -e "$DMG_OUTPUT" ]] || die "Refusing to overwrite existing output: $DMG_OUTPUT"
[[ -n "$VOLUME_NAME" ]] || die "Volume name must not be empty"
command -v hdiutil >/dev/null 2>&1 || die "hdiutil is required and was not found"
command -v ditto >/dev/null 2>&1 || die "ditto is required and was not found"

OUTPUT_DIRECTORY="$(dirname "$DMG_OUTPUT")"
mkdir -p "$OUTPUT_DIRECTORY"
OUTPUT_DIRECTORY="$(cd "$OUTPUT_DIRECTORY" && pwd -P)"
DMG_OUTPUT="$OUTPUT_DIRECTORY/$(basename "$DMG_OUTPUT")"
APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd -P)/$(basename "$APP_PATH")"

STAGING_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/devnotch-dmg.XXXXXX")"
cleanup() {
  rm -rf "$STAGING_DIRECTORY"
}
trap cleanup EXIT

ditto "$APP_PATH" "$STAGING_DIRECTORY/DevNotch.app"
ln -s /Applications "$STAGING_DIRECTORY/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIRECTORY" \
  -ov \
  -format UDZO \
  "$DMG_OUTPUT"

[[ -f "$DMG_OUTPUT" ]] || die "hdiutil completed without creating: $DMG_OUTPUT"
printf 'Created %s\n' "$DMG_OUTPUT"
