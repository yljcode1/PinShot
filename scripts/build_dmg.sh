#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-0.3.2}"
APP_NAME="PinShot.app"
VOLUME_NAME="PinShot"
BACKGROUND_REL=".background/dmg-background.png"
BACKGROUND_HFS=".background:dmg-background.png"
BACKGROUND_ABS="$ROOT_DIR/Support/dmg-background.png"
FINAL_DMG="$ROOT_DIR/dist/PinShot-${VERSION}-macos-arm64.dmg"
TEMP_DMG="$ROOT_DIR/dist/PinShot-${VERSION}-temp.dmg"
STAGING_DIR="$(mktemp -d /tmp/pinshot-dmg-staging.XXXXXX)"
MOUNT_DIR=""

cleanup() {
  if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
    hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
  fi
  rm -rf "$STAGING_DIR"
  rm -f "$TEMP_DMG"
}
trap cleanup EXIT

if [[ ! -f "$BACKGROUND_ABS" ]]; then
  python3 "$ROOT_DIR/scripts/generate_dmg_background.py" >/dev/null
fi

rm -f "$FINAL_DMG"
mkdir -p "$ROOT_DIR/dist"
mkdir -p "$STAGING_DIR/.background"

cp -R "$ROOT_DIR/$APP_NAME" "$STAGING_DIR/$APP_NAME"
cp "$BACKGROUND_ABS" "$STAGING_DIR/$BACKGROUND_REL"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs "APFS" \
  -format UDRW \
  -ov \
  "$TEMP_DMG" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach "$TEMP_DMG" -nobrowse -readwrite)"
MOUNT_DIR="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/\/Volumes\// {print $NF}' | tail -n 1)"
VOLUME_DISPLAY_NAME="$(basename "$MOUNT_DIR")"

sleep 1

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME_DISPLAY_NAME"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {140, 120, 800, 540}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 16
    set background picture of viewOptions to file "$BACKGROUND_HFS"
    set position of item "$APP_NAME" of container window to {170, 235}
    set position of item "Applications" of container window to {490, 235}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR" >/dev/null
MOUNT_DIR=""

hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$FINAL_DMG" >/dev/null

echo "$FINAL_DMG"
