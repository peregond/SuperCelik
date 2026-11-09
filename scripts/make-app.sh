#!/usr/bin/env bash
# Builds a universal (arm64 + x86_64) SerbiaID.app and a zip next to it.
# Usage: scripts/make-app.sh [version]   (run on macOS)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.0.0}"
APP="dist/SerbiaID.app"

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SerbiaID" "$APP/Contents/MacOS/SerbiaID"
# SwiftPM resource bundle (contains the MUP CA certificates)
cp -R "$BIN_DIR"/SerbiaID_SerbiaID.bundle "$APP/Contents/Resources/"
sed "s/__VERSION__/$VERSION/g" scripts/Info.plist > "$APP/Contents/Info.plist"

# Ad-hoc signature (no Developer ID): users must right-click > Open the first time.
codesign --force --deep --sign - "$APP"

(cd dist && ditto -c -k --keepParent SerbiaID.app "SerbiaID-$VERSION-macOS-universal.zip")
echo "Built dist/SerbiaID-$VERSION-macOS-universal.zip"
