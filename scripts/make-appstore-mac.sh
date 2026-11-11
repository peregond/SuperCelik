#!/usr/bin/env bash
# Builds the Mac App Store package (sandboxed app + CryptoTokenKit extension, no self-updater) and, with
# credentials, signs it and produces a .pkg for App Store Connect (run on macOS).
#
# Usage:  bash scripts/make-appstore-mac.sh <version> <build>
#   UNSIGNED=1                       ad-hoc signed app only (CI compile / layout check, not uploadable)
# Otherwise set:
#   TEAM_ID                          10-character Apple team id
#   APP_IDENTITY                     "3rd Party Mac Developer Application: Name (TEAMID)" (or "Apple Distribution: ...")
#   INSTALLER_IDENTITY               "3rd Party Mac Developer Installer: Name (TEAMID)"
#   APP_PROFILE, EXT_PROFILE         paths of the Mac App Store provisioning profiles (.provisionprofile)
#                                    for com.peregond.supercelik and com.peregond.supercelik.token
# Result: dist/SuperCelik-<version>-appstore.pkg  (upload with Transporter or `xcrun altool --upload-app`)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?version}"; BUILD="${2:?build number}"
APP="dist/SuperCelik.app"
PB=/usr/libexec/PlistBuddy

# Same code as the direct-download build, compiled with the APPSTORE flag (no updater, no helper processes).
swift build -c release --arch arm64 --arch x86_64 -Xswiftc -DAPPSTORE
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 -Xswiftc -DAPPSTORE --show-bin-path)"

rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SerbiaID" "$APP/Contents/MacOS/SerbiaID"
cp -R "$BIN_DIR"/SerbiaID_SerbiaID.bundle "$APP/Contents/Resources/"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp macos/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"

PLIST="$APP/Contents/Info.plist"
sed "s/__VERSION__/$VERSION/g" scripts/Info.plist > "$PLIST"
$PB -c "Set :CFBundleVersion $BUILD" "$PLIST"
$PB -c "Add :LSApplicationCategoryType string public.app-category.utilities" "$PLIST"
$PB -c "Add :ITSAppUsesNonExemptEncryption bool false" "$PLIST"
$PB -c "Add :NSHumanReadableCopyright string Super Celik. Independent app, not affiliated with MUP RS or NetSeT/Veridos." "$PLIST"

# CryptoTokenKit extension
APPEX="$APP/Contents/PlugIns/SuperCelikToken.appex"
mkdir -p "$APPEX/Contents/MacOS" dist/token
SLICES=()
for a in arm64 x86_64; do
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
$PB -c "Set :CFBundleVersion $BUILD" "$APPEX/Contents/Info.plist"

if [ "${UNSIGNED:-0}" = "1" ]; then
  sed "s/TEAMID/TEAMID0000/g" macos/AppStoreToken.entitlements > dist/token.entitlements
  sed "s/TEAMID/TEAMID0000/g" macos/AppStore.entitlements > dist/app.entitlements
  codesign --force --sign - --entitlements dist/token.entitlements "$APPEX"
  codesign --force --sign - --entitlements dist/app.entitlements "$APP"
  codesign --verify --deep --strict "$APP"
  echo "Built $APP (ad-hoc signed, NOT for upload)"
  exit 0
fi

: "${TEAM_ID:?}" "${APP_IDENTITY:?}" "${INSTALLER_IDENTITY:?}" "${APP_PROFILE:?}" "${EXT_PROFILE:?}"
sed "s/TEAMID/$TEAM_ID/g" macos/AppStoreToken.entitlements > dist/token.entitlements
sed "s/TEAMID/$TEAM_ID/g" macos/AppStore.entitlements > dist/app.entitlements
cp "$EXT_PROFILE" "$APPEX/Contents/embedded.provisionprofile"
cp "$APP_PROFILE" "$APP/Contents/embedded.provisionprofile"
# inner (extension) first, then the app
codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" --entitlements dist/token.entitlements "$APPEX"
codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" --entitlements dist/app.entitlements "$APP"
codesign --verify --deep --strict "$APP"

PKG="dist/SuperCelik-$VERSION-appstore.pkg"
productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"
echo "Built $PKG"
