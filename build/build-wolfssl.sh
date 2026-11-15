#!/bin/sh
# Build static wolfSSL (OpenSSL compat layer) for host, baby or fab4.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TARGET=${1:-host}
. "$ROOT/build/targets.sh"

PREFIX="$ROOT/build/work/$TARGET/wolfssl-prefix"
if [ -f "$PREFIX/lib/libwolfssl.a" ]; then
    echo "wolfssl ($TARGET) already built"
    exit 0
fi

SRC="$ROOT/third_party/wolfssl"
[ -x "$SRC/configure" ] || (cd "$SRC" && ./autogen.sh >/dev/null)

BUILD="$ROOT/build/work/$TARGET/wolfssl-build"
rm -rf "$BUILD"
mkdir -p "$BUILD"
cd "$BUILD"

set -- --prefix="$PREFIX" --enable-static --disable-shared \
    --enable-opensslextra --enable-opensslall --enable-keygen \
    --enable-aescbc --disable-examples --disable-crypttests --disable-benchmark \
    --disable-asm
if [ "$TARGET" != host ]; then
    set -- "$@" --host="$TARGET_TRIPLE"
fi

CC="$TARGET_CC" CFLAGS="$TARGET_CFLAGS -DWC_RSA_NO_PADDING -DWOLFSSL_KEY_GEN" \
    "$SRC/configure" "$@" >configure.log 2>&1 || { tail -20 configure.log; exit 1; }
make -j"$(nproc)" >make.log 2>&1 || { tail -30 make.log; exit 1; }
make install >/dev/null
echo "wolfssl ($TARGET) built in $PREFIX"
