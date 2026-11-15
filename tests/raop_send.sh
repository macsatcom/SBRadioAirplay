#!/bin/sh
# Build (once) libraop's own raop_play sender for host, using its prebuilt
# host libraries. Test-only tool; prints the binary path.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/work/host/raop_play"
BIN="$OUT/raop_play-linux-x86_64"
if [ ! -x "$BIN" ]; then
    cmake -S "$ROOT/third_party/libraop" -B "$OUT" -DHOST=linux -DPLATFORM=x86_64 >/dev/null
    cmake --build "$OUT" -j"$(nproc)" >/dev/null
fi
echo "$BIN"
