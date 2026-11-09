#!/usr/bin/env bash
# Builds SuperCelik.app and a drag-to-Applications .dmg installer (run on macOS).
# Usage: bash scripts/make-app.sh <version> <arch>
#   arch: arm64 (Apple Silicon) | x86_64 (Intel) | universal
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.0.0}"
ARCH="${2:-universal}"
case "$ARCH" in
  arm64)     ARCHFLAGS=(--arch arm64);               LABEL="apple-silicon"; ARCHS=(arm64) ;;
  x86_64)    ARCHFLAGS=(--arch x86_64);              LABEL="intel";         ARCHS=(x86_64) ;;
  universal) ARCHFLAGS=(--arch arm64 --arch x86_64); LABEL="universal";     ARCHS=(arm64 x86_64) ;;
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
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed "s/__VERSION__/$VERSION/g" scripts/Info.plist > "$APP/Contents/Info.plist"

# CryptoTokenKit extension: makes the eID / token certificates visible in the macOS keychain,
# which is the only place Chrome and Safari look for TLS client certificates (eid.gov.rs login).
# Built with swiftc because SwiftPM cannot produce an .appex; the entry point is NSExtensionMain.
APPEX="$APP/Contents/PlugIns/SuperCelikToken.appex"
mkdir -p "$APPEX/Contents/MacOS" dist/token
SLICES=()
for a in "${ARCHS[@]}"; do
  xcrun --sdk macosx swiftc -O -parse-as-library -module-name SuperCelikToken \
    -target "$a-apple-macos13.0" \
    -framework CryptoTokenKit -framework Security -framework Foundation \
    -Xlinker -e -Xlinker _NSExtensionMain \
    TokenExtension/*.swift -o "dist/token/SuperCelikToken-$a"
  SLICES+=("dist/token/SuperCelikToken-$a")
done
lipo -create "${SLICES[@]}" -output "$APPEX/Contents/MacOS/SuperCelikToken"
rm -rf dist/token
sed "s/__VERSION__/$VERSION/g" TokenExtension/Info.plist > "$APPEX/Contents/Info.plist"

# Ad-hoc signature (no Developer ID): first launch needs right-click > Open.
# The extension is signed first, with its sandbox + smart card entitlements; the app is then
# signed without --deep so that nested signature (and its entitlements) is kept.
codesign --force --sign - --entitlements TokenExtension/Token.entitlements "$APPEX"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

# DMG with an /Applications shortcut
STAGE="dist/dmg"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="dist/SuperCelik-$VERSION-macOS-$LABEL.dmg"
hdiutil create -volname "Super Celik $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "Built $DMG"
