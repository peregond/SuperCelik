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

# ---- PKCS#11 module for browser sign-in (srb-id-pkcs11 by ubavic, Unlicense = public domain). Upstream publishes a Linux build
# for x86_64 only, so only x64 gets it. The app connects it to Firefox / Chrome when the user agrees (BrowserSetup.cs).
P11_VER=0.6.0
P11_SHA=8f2f55e69459df21035982948719213fe595e97bb9b9bca9dabc85047204453c
if [ "$ARCH" = x64 ]; then
  mkdir -p "$PUB/pkcs11"
  curl -fsSL --retry 3 -o "$PUB/pkcs11/libsrb-id-pkcs11.so" "https://github.com/ubavic/srb-id-pkcs11/releases/download/v$P11_VER/libsrb-id-pkcs11.so.$P11_VER"
  if command -v sha256sum >/dev/null; then GOT=$(sha256sum "$PUB/pkcs11/libsrb-id-pkcs11.so" | cut -d' ' -f1); else GOT=$(shasum -a 256 "$PUB/pkcs11/libsrb-id-pkcs11.so" | cut -d' ' -f1); fi
  [ "$GOT" = "$P11_SHA" ] || { echo "srb-id-pkcs11 checksum mismatch: $GOT" >&2; exit 1; }
  cat > "$PUB/pkcs11/README.txt" <<TXT
libsrb-id-pkcs11.so is srb-id-pkcs11 $P11_VER, a PKCS#11 module for Serbian eID cards.
Source and licence (Unlicense, public domain): https://github.com/ubavic/srb-id-pkcs11
Super Čelik registers it in Firefox and Chrome / Chromium on request (button "Set up browser sign-in").
TXT
fi

# ---- tar.gz: unpack anywhere, run ./SuperCelik
NAME="SuperCelik-$VERSION-linux-$ARCH"
rm -rf "$OUT/$NAME"; cp -R "$PUB" "$OUT/$NAME"
cp linux/packaging/supercelik.desktop linux/SerbiaID.Linux/Assets/icon.png "$OUT/$NAME/"
tar -C "$OUT" -czf "$OUT/$NAME.tar.gz" "$NAME"
# delta update files: a zip the app can read entry by entry + a manifest with the SHA-256 of every file (same content as the .tar.gz)
python3 scripts/make-linux-delta.py "$OUT/$NAME" "$OUT/$NAME" "$VERSION"
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
  DEBV="$(printf %s "$VERSION" | tr - "~")"
  cat > "$ROOT/DEBIAN/control" <<CTL
Package: supercelik
Version: $DEBV
Section: utils
Priority: optional
Architecture: $DEB
Installed-Size: $SIZE
Depends: pcscd, libccid, libpcsclite1, libnss3-tools, libfontconfig1, libx11-6, libice6, libsm6
Recommends: xdg-utils
Maintainer: Super Čelik <noreply@users.noreply.github.com>
Homepage: https://github.com/peregond/SuperCelik
Description: Serbian electronic ID card reader
 Reads the Serbian eID, foreigner ID card and residence permit through a USB
 smart card reader: personal data, signature check, token certificates, PIN
 change, file signing, PDF printout. Independent implementation, not affiliated
 with MUP RS or NetSeT/Veridos.
CTL
  # make sure the smart card service runs right after the installation (pcscd is socket-activated on Debian / Ubuntu)
  cat > "$ROOT/DEBIAN/postinst" <<'POST'
#!/bin/sh
set -e
if [ "$1" = configure ] && [ -d /run/systemd/system ]; then
  systemctl enable pcscd.socket >/dev/null 2>&1 || true
  systemctl start pcscd.socket >/dev/null 2>&1 || true
fi
exit 0
POST
  chmod 755 "$ROOT/DEBIAN/postinst"
  dpkg-deb --root-owner-group --build "$ROOT" "$OUT/SuperCelik-$VERSION-linux-$DEB.deb"
  rm -rf "$ROOT"
fi
rm -rf "$PUB"
ls -l "$OUT"
