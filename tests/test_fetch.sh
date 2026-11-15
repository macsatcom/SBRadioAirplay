#!/bin/sh
# Verifies build/fetch-deps.sh produced all pinned dependencies and is idempotent.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
fail=0
check() { if [ -e "$1" ]; then echo "ok   $1"; else echo "FAIL missing $1"; fail=1; fi; }

check third_party/libraop/src/raop_server.c
check third_party/libraop/libmdns/mdnssvc/mdnsd.c
check third_party/libraop/libmdns/mdnssd/mdnssd.c
check third_party/libraop/dmap-parser/dmap_parser.c
check third_party/libraop/libcodecs/addons/encoder.h
check third_party/wolfssl/configure.ac
check third_party/linux26-compat/linux26-compat.c

want=c14088da44df37f58ef7a45b8ce8a3cbc051c5e4
got=$(git -C third_party/libraop rev-parse HEAD 2>/dev/null || echo none)
[ "$got" = "$want" ] && echo "ok   libraop pinned" || { echo "FAIL libraop at $got"; fail=1; }

cc=build/toolchains/armv5-eabi--musl--stable-2020.02-2/bin/arm-buildroot-linux-musleabi-gcc
"$cc" --version >/dev/null 2>&1 && echo "ok   toolchain" || { echo "FAIL toolchain"; fail=1; }

[ $fail = 0 ] || exit 1
out=$(sh build/fetch-deps.sh 2>&1) || { echo "FAIL re-run exit"; exit 1; }
echo "$out" | grep -qi "download" && { echo "FAIL re-run downloaded again"; exit 1; }
echo "ok   idempotent"
