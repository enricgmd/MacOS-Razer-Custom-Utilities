#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Razer Custom Utilities"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
VERSION_FILE="$ROOT_DIR/VERSION"
APP_VERSION="0.0.0"

if [[ -f "$VERSION_FILE" ]]; then
  APP_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
fi

DMG_PATH="$DIST_DIR/$APP_NAME-$APP_VERSION.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/razer-custom-utilities-dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

"$ROOT_DIR/script/build_app.sh" --release --no-launch

rm -f "$DMG_PATH"
cp -R "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created $DMG_PATH"
