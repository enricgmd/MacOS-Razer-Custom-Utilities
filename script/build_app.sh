#!/usr/bin/env bash
set -euo pipefail

PRODUCT_NAME="RazerCustomUtilities"
HELPER_PRODUCT_NAME="razer-hid-tool"
APP_NAME="Razer Custom Utilities"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$APP_DIST_DIR/$APP_NAME.app"
VERSION_FILE="$ROOT_DIR/VERSION"
CONFIGURATION="${CONFIGURATION:-release}"

APP_VERSION="0.0.0"
if [[ -f "$VERSION_FILE" ]]; then
  APP_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
fi

usage() {
  cat >&2 <<USAGE
usage: $0 [--release|--debug|--no-launch|--help]

Build, package, sign when possible, and launch Razer Custom Utilities.

Options:
  --release   Build optimized release binaries. Default.
  --debug     Build debug binaries for local development.
  --no-launch Build the app bundle without opening it afterwards.
  --help      Show this help.
USAGE
}

LAUNCH_APP=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release|release)
      CONFIGURATION="release"
      shift
      ;;
    --debug|debug)
      CONFIGURATION="debug"
      shift
      ;;
    --no-launch)
      LAUNCH_APP=0
      shift
      ;;
    --help|-h|help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

APP_BINARY="$ROOT_DIR/.build/$CONFIGURATION/$PRODUCT_NAME"
HELPER_BINARY="$ROOT_DIR/.build/$CONFIGURATION/$HELPER_PRODUCT_NAME"

codesign_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$CODESIGN_IDENTITY"
    return 0
  fi

  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
    | head -n 1
}

generate_app_icon() {
  local source_png="$ROOT_DIR/Sources/RazerCustomUtilitiesCore/Resources/graphics/app_logo.png"
  local iconset="$APP_DIST_DIR/AppIcon.iconset"
  local icns="$APP_BUNDLE/Contents/Resources/AppIcon.icns"

  [[ -f "$source_png" ]] || return 0

  rm -rf "$iconset"
  mkdir -p "$iconset"

  sips -z 16 16 "$source_png" --out "$iconset/icon_16x16.png" >/dev/null
  sips -z 32 32 "$source_png" --out "$iconset/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$source_png" --out "$iconset/icon_32x32.png" >/dev/null
  sips -z 64 64 "$source_png" --out "$iconset/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$source_png" --out "$iconset/icon_128x128.png" >/dev/null
  sips -z 256 256 "$source_png" --out "$iconset/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$source_png" --out "$iconset/icon_256x256.png" >/dev/null
  sips -z 512 512 "$source_png" --out "$iconset/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$source_png" --out "$iconset/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$source_png" --out "$iconset/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "$iconset" -o "$icns"
  rm -rf "$iconset"
}

copy_runtime_graphics() {
  local target_dir="$APP_BUNDLE/Contents/Resources/graphics"
  mkdir -p "$target_dir"

  cp "$ROOT_DIR/Sources/RazerCustomUtilitiesCore/Resources/graphics/keyboard.png" "$target_dir/keyboard.png"
  cp "$ROOT_DIR/Sources/RazerCustomUtilitiesCore/Resources/graphics/razer-ths-logo.png" "$target_dir/razer-ths-logo.png"
  cp "$ROOT_DIR/Sources/RazerCustomUtilitiesCore/Resources/graphics/mouseHQ.png" "$target_dir/mouseHQ.png"
}

pkill -x "$PRODUCT_NAME" 2>/dev/null || true
swift build -c "$CONFIGURATION" --product "$PRODUCT_NAME"
swift build -c "$CONFIGURATION" --product "$HELPER_PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources/bin"
cp "$APP_BINARY" "$APP_BUNDLE/Contents/MacOS/$PRODUCT_NAME"
cp "$HELPER_BINARY" "$APP_BUNDLE/Contents/Resources/bin/$HELPER_PRODUCT_NAME"
copy_runtime_graphics
generate_app_icon

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>com.henry.RazerCustomUtilities</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>${APP_VERSION//./}</string>
  <key>LSMinimumSystemVersion</key>
  <string>10.15</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

SIGN_IDENTITY="$(codesign_identity || true)"
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --identifier "com.henry.RazerCustomUtilities.helper" "$APP_BUNDLE/Contents/Resources/bin/$HELPER_PRODUCT_NAME"
  codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
  echo "Signed $APP_NAME $APP_VERSION with $SIGN_IDENTITY"
else
  echo "No codesigning identity found; TCC permissions may reset after rebuilds." >&2
fi

touch "$APP_BUNDLE"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP_BUNDLE" 2>/dev/null || true

if [[ "$LAUNCH_APP" == "1" ]]; then
  /usr/bin/open -n "$APP_BUNDLE"
  echo "$APP_NAME is running from $APP_BUNDLE"
else
  echo "$APP_NAME was built at $APP_BUNDLE"
fi
