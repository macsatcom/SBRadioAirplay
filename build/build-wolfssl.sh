#!/bin/sh
# Build static wolfSSL (OpenSSL compat layer) for host, baby or fab4.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TARGET=${1:-host}
. "$ROOT/build/targets.sh"

PREFIX="$ROOT/build/work/$TARGET/wolfssl-prefix"

# RSA-2048 private ops dominate session setup on the Radio (1.4 s each with
# generic math, 384 ms with SP ARM assembly, measured on a Radio). Disable the
# assembly with WOLFSSL_SP_ASM=0.
WOLF_OPT="--enable-sp=yes --enable-sp-math-all"
WOLF_CFLAGS=$(echo "$TARGET_CFLAGS" | sed 's/-Os/-O2/')
if [ "${WOLFSSL_SP_ASM:-1}" = 1 ]; then
    WOLF_OPT="$WOLF_OPT --enable-sp-asm"
    # Select sp_arm32 code paths without UMAAL (ARMv6+) on the ARMv5 Radio.
    case "$TARGET" in baby) WOLF_CFLAGS="$WOLF_CFLAGS -DWOLFSSL_ARM_ARCH=5" ;; fab4) WOLF_CFLAGS="$WOLF_CFLAGS -DWOLFSSL_ARM_ARCH=6" ;; esac
fi
STAMP="$WOLF_OPT|$WOLF_CFLAGS"
if [ -f "$PREFIX/lib/libwolfssl.a" ] && [ "$(cat "$PREFIX/.build-flags" 2>/dev/null)" = "$STAMP" ]; then
    echo "wolfssl ($TARGET) already built"
    exit 0
fi
rm -rf "$PREFIX"

SRC="$ROOT/third_party/wolfssl"
[ -x "$SRC/configure" ] || (cd "$SRC" && ./autogen.sh >/dev/null)

BUILD="$ROOT/build/work/$TARGET/wolfssl-build"
rm -rf "$BUILD"
mkdir -p "$BUILD"
cd "$BUILD"

set -- --prefix="$PREFIX" --enable-static --disable-shared \
    --enable-opensslextra --enable-opensslall --enable-keygen \
    --enable-aescbc --disable-examples --disable-crypttests --disable-benchmark \
    $WOLF_OPT
if [ "$TARGET" != host ]; then
    set -- "$@" --host="$TARGET_TRIPLE"
fi

CC="$TARGET_CC" CFLAGS="$WOLF_CFLAGS -DWC_RSA_NO_PADDING -DWOLFSSL_KEY_GEN" \
    "$SRC/configure" "$@" >configure.log 2>&1 || { tail -20 configure.log; exit 1; }
make -j"$(nproc)" >make.log 2>&1 || { tail -30 make.log; exit 1; }
make install >/dev/null
echo "$STAMP" > "$PREFIX/.build-flags"
echo "wolfssl ($TARGET) built in $PREFIX"
