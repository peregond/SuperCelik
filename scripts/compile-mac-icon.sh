#!/usr/bin/env bash
# Compiles the Icon Composer document into the macOS app icon: Assets.car (Liquid Glass on macOS 26+,
# flat renditions for older systems) and the AppIcon.icns fallback. Needs Xcode 26 or newer.
# Usage: bash scripts/compile-mac-icon.sh <Contents/Resources directory>
set -euo pipefail
cd "$(dirname "$0")/.."
# actool's helper process does not reliably share our working directory: pass absolute paths only.
OUT="$(cd "${1:?output directory}" && pwd)"
PARTIAL="$(mktemp)"
trap 'rm -f "$PARTIAL"' EXIT
xcrun actool "$PWD/assets/AppIcon.icon" --compile "$OUT" --app-icon AppIcon --output-partial-info-plist "$PARTIAL" \
  --platform macosx --target-device mac --minimum-deployment-target 12.0 --errors --warnings >/dev/null
test -f "$OUT/Assets.car" && test -f "$OUT/AppIcon.icns"
