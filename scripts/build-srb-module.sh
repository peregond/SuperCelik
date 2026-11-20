#!/usr/bin/env bash
# Builds the PKCS#11 module srb-id-pkcs11 (by ubavic, Unlicense = public domain, written in Zig) from source for old and new Linux systems:
# the binary that upstream publishes needs glibc 2.36 (arc4random_buf), which Ubuntu 22.04 and Linux Mint 21 do not have, and upstream
# publishes no arm64 build. Zig can target an old glibc, so the module built here loads from glibc 2.28 on.
#   bash scripts/build-srb-module.sh <x64|arm64>      -> dist/p11/srb-id-pkcs11-<arch>/libsrb-id-pkcs11.so
# Run it on a machine of that architecture (CI: ubuntu-22.04 / ubuntu-22.04-arm); needs python3 with pip, git and libpcsclite-dev.
# Everything that is downloaded is pinned: the source by its commit (git checks the hash), Zig by the hashes in
# scripts/ziglang-requirements.txt, and the Zig package the module depends on by the hash in its build.zig.zon.
set -euo pipefail
ARCH="${1:?usage: build-srb-module.sh x64|arm64}"
case "$ARCH" in
  x64)   TARGET=x86_64-linux-gnu.2.28 ;;
  arm64) TARGET=aarch64-linux-gnu.2.28 ;;
  *) echo "arch: x64 or arm64" >&2; exit 1 ;;
esac
SRC_URL=https://github.com/ubavic/srb-id-pkcs11
SRC_COMMIT=a276e48d0f2ca9d85c98e79b8a1b20a6f50e0c70      # tag v0.6.0
MAX_GLIBC=2.35                                            # the module must not need a newer glibc than Ubuntu 22.04 has (2.28 is the target)
cd "$(dirname "$0")/.."
OUT="$PWD/dist/p11/srb-id-pkcs11-$ARCH"; WORK="$PWD/dist/p11-work-$ARCH"
rm -rf "$OUT" "$WORK"; mkdir -p "$OUT" "$WORK"

echo "== Zig"
python3 -m pip install --quiet --disable-pip-version-check --require-hashes --target "$WORK/zig" -r scripts/ziglang-requirements.txt
zig() { PYTHONPATH="$WORK/zig" python3 -m ziglang "$@"; }
zig version

echo "== source $SRC_COMMIT"
git init -q "$WORK/src"
git -C "$WORK/src" fetch -q --depth 1 "$SRC_URL" "$SRC_COMMIT"
git -C "$WORK/src" checkout -q FETCH_HEAD
[ "$(git -C "$WORK/src" rev-parse HEAD)" = "$SRC_COMMIT" ] || { echo "unexpected source commit" >&2; exit 1; }

# With an explicit target Zig does not look in the system library folders, so libpcsclite (the development package) is shown to it:
# a prefix with lib/libpcsclite.so pointing at the system's copy. The headers are found through /usr/include/PCSC by the module's own build.
PCSC=$(ls /usr/lib/*/libpcsclite.so /usr/lib/libpcsclite.so 2>/dev/null | head -1 || true)
[ -n "$PCSC" ] || { echo "libpcsclite.so not found: install libpcsclite-dev" >&2; exit 1; }
mkdir -p "$WORK/pcsc-prefix/lib"; ln -s "$PCSC" "$WORK/pcsc-prefix/lib/libpcsclite.so"

echo "== build for $TARGET (libpcsclite: $PCSC)"
(cd "$WORK/src" && zig build -Dtarget="$TARGET" -Doptimize=ReleaseSafe --search-prefix "$WORK/pcsc-prefix" --global-cache-dir "$WORK/zig-cache" --cache-dir "$WORK/zig-local-cache")
cp -L "$WORK/src/zig-out/lib/libsrb-id-pkcs11.so" "$OUT/libsrb-id-pkcs11.so"

echo "== checks"
file "$OUT/libsrb-id-pkcs11.so"
readelf -d "$OUT/libsrb-id-pkcs11.so" | grep NEEDED
NEWEST=$(objdump -T "$OUT/libsrb-id-pkcs11.so" | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -uV | tail -1 || true)
echo "newest glibc symbol version needed: ${NEWEST:-none}"
if [ -n "$NEWEST" ] && [ "$(printf '%s\n%s\n' "$NEWEST" "$MAX_GLIBC" | sort -V | tail -1)" != "$MAX_GLIBC" ]; then
  echo "the module needs glibc $NEWEST, more than the $MAX_GLIBC allowed" >&2; exit 1
fi
cat > "$OUT/README.txt" <<TXT
libsrb-id-pkcs11.so is srb-id-pkcs11 0.6.0 ($SRC_COMMIT), a PKCS#11 module for Serbian eID cards,
built from source for glibc 2.28 and newer with scripts/build-srb-module.sh.
Source and licence (Unlicense, public domain): $SRC_URL
TXT
echo "built $OUT/libsrb-id-pkcs11.so"
