#!/usr/bin/env bash
# Builds SuperCelik.app and a drag-to-Applications .dmg installer (run on macOS).
# Usage: bash scripts/make-app.sh <version> <arch>
#   arch: arm64 (Apple Silicon) | x86_64 (Intel) | universal
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.0.0}"
ARCH="${2:-universal}"
case "$ARCH" in
  arm64)     ARCHFLAGS=(--arch arm64);               LABEL="apple-silicon" ;;
  x86_64)    ARCHFLAGS=(--arch x86_64);              LABEL="intel" ;;
  universal) ARCHFLAGS=(--arch arm64 --arch x86_64); LABEL="universal" ;;
  *) echo "unknown arch $ARCH"; exit 1 ;;
esac

APP="dist/SuperCelik.app"
swift build -c release "${ARCHFLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCHFLAGS[@]}" --show-bin-path)"

rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Executable name matches CFBundleExecutable in Info.plist
cp "$BIN_DIR/SerbiaID" "$APP/Contents/MacOS/SerbiaID"
# SwiftPM resource bundle (contains the MUP CA certificates)
cp -R "$BIN_DIR"/SerbiaID_SerbiaID.bundle "$APP/Contents/Resources/"
sed "s/__VERSION__/$VERSION/g" scripts/Info.plist > "$APP/Contents/Info.plist"

# Ad-hoc signature (no Developer ID): first launch needs right-click > Open.
codesign --force --deep --sign - "$APP"

# DMG with an /Applications shortcut
STAGE="dist/dmg"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="dist/SuperCelik-$VERSION-macOS-$LABEL.dmg"
hdiutil create -volname "Super Celik $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "Built $DMG"
