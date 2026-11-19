#!/usr/bin/env bash
# Flatpak bundle from the files that scripts/make-linux.sh published (run that first with KEEP_PUBLISH=1). Needs flatpak and
# flatpak-builder, and runs on the target architecture (no cross-building).
#   bash scripts/make-linux-flatpak.sh <version> [x64|arm64]   -> dist/SuperCelik-<version>-linux-<x86_64|aarch64>.flatpak
set -euo pipefail
VERSION="${1:-0.0.0}"
ARCH="${2:-x64}"
case "$ARCH" in
  x64)   FA=x86_64 ;;
  arm64) FA=aarch64 ;;
  *) echo "arch: x64 or arm64" >&2; exit 1 ;;
esac
cd "$(dirname "$0")/.."
OUT="$PWD/dist"; ID=io.github.peregond.SuperCelik; PK=linux/packaging/flatpak
[ -d "$OUT/publish-$ARCH" ] || { echo "run: KEEP_PUBLISH=1 bash scripts/make-linux.sh $VERSION $ARCH" >&2; exit 1; }

WORK="$OUT/flatpak-$ARCH"; rm -rf "$WORK"; mkdir -p "$WORK"
cp -a "$OUT/publish-$ARCH" "$WORK/publish"
cp "$PK/$ID.yml" "$WORK/"
cp linux/SerbiaID.Linux/Assets/icon.png "$WORK/icon.png"
sed "s/^Icon=supercelik$/Icon=$ID/" linux/packaging/supercelik.desktop > "$WORK/$ID.desktop"
sed -e "s/VERSION_PLACEHOLDER/${VERSION%%-*}/" -e "s/DATE_PLACEHOLDER/$(date -u +%F)/" "$PK/$ID.metainfo.xml" > "$WORK/$ID.metainfo.xml"

cd "$WORK"
flatpak-builder --force-clean --user --install-deps-from=flathub --disable-rofiles-fuse --repo=repo build "$ID.yml"
flatpak build-bundle --arch="$FA" --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo repo \
  "$OUT/SuperCelik-$VERSION-linux-$FA.flatpak" "$ID"
cd "$OUT"; rm -rf "$WORK"
ls -l "$OUT"/*.flatpak
