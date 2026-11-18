#!/usr/bin/env bash
# Linux build: a self-contained .tar.gz and a .deb (needs the .NET 8 SDK and dpkg-deb).
#   bash scripts/make-linux.sh <version> [x64|arm64]      -> dist/SuperCelik-<version>-linux-<arch>.tar.gz / .deb
set -euo pipefail
VERSION="${1:-0.0.0}"
ARCH="${2:-x64}"
case "$ARCH" in
  x64)   RID=linux-x64;   DEB=amd64 ;;
  arm64) RID=linux-arm64; DEB=arm64 ;;
  *) echo "arch: x64 or arm64" >&2; exit 1 ;;
esac
cd "$(dirname "$0")/.."
OUT="$PWD/dist"; PUB="$OUT/linux-$ARCH"
rm -rf "$PUB"; mkdir -p "$OUT"

dotnet publish linux/SerbiaID.Linux -c Release -r "$RID" --self-contained -p:Version="$VERSION" -p:DebugType=None -o "$PUB"
chmod +x "$PUB/SuperCelik"

# ---- tar.gz: unpack anywhere, run ./SuperCelik
NAME="SuperCelik-$VERSION-linux-$ARCH"
rm -rf "$OUT/$NAME"; cp -R "$PUB" "$OUT/$NAME"
cp linux/packaging/supercelik.desktop linux/SerbiaID.Linux/Assets/icon.png "$OUT/$NAME/"
tar -C "$OUT" -czf "$OUT/$NAME.tar.gz" "$NAME"
rm -rf "$OUT/$NAME"

# ---- .deb
if command -v dpkg-deb >/dev/null; then
  ROOT="$OUT/deb-$ARCH"; rm -rf "$ROOT"
  mkdir -p "$ROOT/DEBIAN" "$ROOT/opt/supercelik" "$ROOT/usr/bin" "$ROOT/usr/share/applications" "$ROOT/usr/share/icons/hicolor/256x256/apps"
  cp -R "$PUB/." "$ROOT/opt/supercelik/"
  ln -s /opt/supercelik/SuperCelik "$ROOT/usr/bin/supercelik"
  cp linux/packaging/supercelik.desktop "$ROOT/usr/share/applications/supercelik.desktop"
  cp linux/SerbiaID.Linux/Assets/icon.png "$ROOT/usr/share/icons/hicolor/256x256/apps/supercelik.png"
  SIZE=$(du -sk "$ROOT" | cut -f1)
  DEBV="${VERSION//-/~}"
  cat > "$ROOT/DEBIAN/control" <<CTL
Package: supercelik
Version: $DEBV
Section: utils
Priority: optional
Architecture: $DEB
Installed-Size: $SIZE
Depends: pcscd, libpcsclite1, libfontconfig1, libx11-6, libice6, libsm6
Recommends: xdg-utils
Maintainer: Super Čelik <noreply@users.noreply.github.com>
Homepage: https://github.com/peregond/SuperCelik
Description: Serbian electronic ID card reader
 Reads the Serbian eID, foreigner ID card and residence permit through a USB
 smart card reader: personal data, signature check, token certificates, PIN
 change, file signing, PDF printout. Independent implementation, not affiliated
 with MUP RS or NetSeT/Veridos.
CTL
  dpkg-deb --root-owner-group --build "$ROOT" "$OUT/SuperCelik-$VERSION-linux-$DEB.deb"
  rm -rf "$ROOT"
fi
rm -rf "$PUB"
ls -l "$OUT"
