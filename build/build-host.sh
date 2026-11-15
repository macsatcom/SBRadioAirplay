#!/bin/sh
# Host (x86) build of airplay-receiver plus unit tests.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
sh "$ROOT/build/build-wolfssl.sh" host
cmake -S "$ROOT" -B "$ROOT/build/host" -DWOLFSSL_PREFIX="$ROOT/build/work/host/wolfssl-prefix" >/dev/null
cmake --build "$ROOT/build/host" -j"$(nproc)"
mkdir -p "$ROOT/build/out/host"
cp "$ROOT/build/host/airplay-receiver" "$ROOT/build/out/host/"
