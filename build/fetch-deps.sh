#!/bin/sh
# Fetch pinned third-party sources and the Bootlin ARM musl toolchain.
# Idempotent: anything already present is left alone.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TP="$ROOT/third_party"
TC="$ROOT/build/toolchains"
mkdir -p "$TP" "$TC"

LIBRAOP_URL=https://github.com/philippe44/libraop
LIBRAOP_REV=c14088da44df37f58ef7a45b8ce8a3cbc051c5e4
WOLFSSL_URL=https://github.com/wolfSSL/wolfssl
WOLFSSL_TAG=v5.7.2-stable
SPOTIFY_URL=https://github.com/ssbrandsma/squeezebox-radio-spotify-connect
TOOLCHAIN=armv5-eabi--musl--stable-2020.02-2
TOOLCHAIN_URL=https://toolchains.bootlin.com/downloads/releases/toolchains/armv5-eabi/tarballs/$TOOLCHAIN.tar.bz2

if [ ! -d "$TP/libraop/.git" ]; then
    echo "download libraop $LIBRAOP_REV"
    git clone -q "$LIBRAOP_URL" "$TP/libraop"
    git -C "$TP/libraop" checkout -q "$LIBRAOP_REV"
    git -C "$TP/libraop" submodule update -q --init --recursive
fi

if [ ! -d "$TP/wolfssl/.git" ]; then
    echo "download wolfssl $WOLFSSL_TAG"
    git clone -q --depth 1 --branch "$WOLFSSL_TAG" "$WOLFSSL_URL" "$TP/wolfssl"
fi

if [ ! -f "$TP/linux26-compat/linux26-compat.c" ]; then
    echo "download linux26-compat"
    tmp=$(mktemp -d)
    git clone -q --depth 1 "$SPOTIFY_URL" "$tmp/sc"
    mkdir -p "$TP/linux26-compat"
    cp "$tmp/sc/native/linux26-compat/"* "$TP/linux26-compat/"
    git -C "$tmp/sc" rev-parse HEAD > "$TP/linux26-compat/REVISION"
    rm -rf "$tmp"
fi

if [ ! -x "$TC/$TOOLCHAIN/bin/arm-buildroot-linux-musleabi-gcc" ]; then
    echo "download toolchain $TOOLCHAIN"
    curl -fsSL "$TOOLCHAIN_URL" | tar -xj -C "$TC"
    # Bootlin toolchains are relocatable but need this once after moving.
    [ -x "$TC/$TOOLCHAIN/relocate-sdk.sh" ] && "$TC/$TOOLCHAIN/relocate-sdk.sh" >/dev/null
fi

# Local changes to third-party code live in patches/<project>-*.patch.
for p in "$ROOT"/patches/*.patch; do
    [ -f "$p" ] || continue
    proj=$(basename "$p" | cut -d- -f2)
    dir="$TP/$proj"
    if git -C "$dir" apply --check "$p" 2>/dev/null; then
        git -C "$dir" apply "$p"
        echo "applied $(basename "$p")"
    elif git -C "$dir" apply --reverse --check "$p" 2>/dev/null; then
        :
    else
        echo "patch does not apply: $p" >&2
        exit 1
    fi
done

{
    echo "libraop $(git -C "$TP/libraop" rev-parse HEAD)"
    git -C "$TP/libraop" submodule status --recursive | awk '{print "libraop/" $2 " " $1}'
    echo "wolfssl $WOLFSSL_TAG $(git -C "$TP/wolfssl" rev-parse HEAD)"
    echo "linux26-compat $(cat "$TP/linux26-compat/REVISION")"
    echo "toolchain $TOOLCHAIN"
} > "$TP/VERSIONS"
